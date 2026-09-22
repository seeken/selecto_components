defmodule SelectoComponents.TemplateNativeModel do
  @moduledoc """
  Builds an HTML-free, server-owned model for ordinary HEEx templates.

  The model exposes compiled event identities plus current input, state, and
  projected source results. It intentionally excludes the compiled manifest,
  socket, host authority, Selecto query, repository, and database connection.
  """

  alias SelectoComponents.TemplateInstance

  @schema "selecto.template.native-heex-model.v1"

  @spec build(Phoenix.LiveView.Socket.t()) :: {:ok, map()} | {:error, map()}
  def build(socket) do
    with {:ok, manifest, snapshot} <- TemplateInstance.runtime(socket) do
      build(manifest, snapshot)
    end
  end

  @spec build(map(), map()) :: {:ok, map()} | {:error, map()}
  def build(
        %{
          "template" => %{"name" => name, "version" => version},
          "events" => events,
          "view" => %{"schema" => "selecto.template.view.v1", "nodes" => nodes}
        },
        %{
          "instance_id" => instance_id,
          "release_id" => release_id,
          "state_revision" => state_revision,
          "inputs" => inputs,
          "state" => state,
          "sources" => sources
        }
      )
      when is_binary(name) and is_binary(version) and is_list(events) and is_list(nodes) and
             is_binary(instance_id) and instance_id != "" and is_binary(release_id) and
             is_integer(state_revision) and state_revision >= 0 and is_map(inputs) and
             is_map(state) and is_map(sources) do
    with {:ok, event_types} <- event_types(events),
         {:ok, event_forms} <- event_forms(nodes, event_types),
         {:ok, source_models} <- source_models(sources) do
      {:ok,
       %{
         "schema" => @schema,
         "template" => %{
           "name" => name,
           "version" => version,
           "release_id" => release_id
         },
         "instance_id" => instance_id,
         "state_revision" => state_revision,
         "root_id" => "selecto-native-template-#{encode_dom_part(instance_id)}",
         "inputs" => inputs,
         "state" => state,
         "sources" => source_models,
         "events" => event_forms
       }}
    end
  end

  def build(_manifest, _snapshot),
    do: {:error, diagnostic("invalid_native_model", "native template model is invalid")}

  defp event_types(events) do
    Enum.reduce_while(events, {:ok, %{}}, fn
      %{"name" => name, "payload" => %{"value" => type}}, {:ok, types}
      when is_binary(name) and name != "" and is_binary(type) and type != "" ->
        if Map.has_key?(types, name) do
          {:halt,
           {:error, diagnostic("invalid_native_events", "native template events are invalid")}}
        else
          {:cont, {:ok, Map.put(types, name, type)}}
        end

      _event, _acc ->
        {:halt,
         {:error, diagnostic("invalid_native_events", "native template events are invalid")}}
    end)
  end

  defp event_forms(nodes, event_types) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, forms} ->
      case node_event_forms(node, event_types) do
        {:ok, node_forms} -> {:cont, {:ok, forms ++ node_forms}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp node_event_forms(
         %{
           "kind" => "component",
           "name" => component,
           "node_id" => node_id,
           "events" => events
         } = node,
         event_types
       )
       when is_binary(component) and is_binary(node_id) and is_map(events) do
    with {:ok, own_forms} <- component_event_forms(component, node_id, events, event_types),
         {:ok, child_forms} <- child_event_forms(node, event_types) do
      {:ok, own_forms ++ child_forms}
    end
  end

  defp node_event_forms(%{} = node, event_types), do: child_event_forms(node, event_types)

  defp node_event_forms(_node, _event_types),
    do: {:error, diagnostic("invalid_native_view", "native template view is invalid")}

  defp component_event_forms(component, node_id, events, event_types) do
    events
    |> Enum.sort_by(fn {binding, _event} -> binding end)
    |> Enum.reduce_while({:ok, []}, fn
      {binding, event}, {:ok, forms} when is_binary(binding) and is_binary(event) ->
        case event_types do
          %{^event => type} ->
            form = %{
              "component" => component,
              "component_id" => node_id,
              "binding" => binding,
              "event" => event,
              "value_type" => type,
              "input_name" => "value"
            }

            {:cont, {:ok, forms ++ [form]}}

          _other ->
            {:halt,
             {:error,
              diagnostic("invalid_native_events", "native template event binding is invalid")}}
        end

      _event, _acc ->
        {:halt,
         {:error, diagnostic("invalid_native_events", "native template event binding is invalid")}}
    end)
  end

  defp child_event_forms(node, event_types) do
    Enum.reduce_while(["children", "then", "else"], {:ok, []}, fn key, {:ok, forms} ->
      case Map.get(node, key, []) do
        children when is_list(children) ->
          case event_forms(children, event_types) do
            {:ok, child_forms} -> {:cont, {:ok, forms ++ child_forms}}
            {:error, error} -> {:halt, {:error, error}}
          end

        _other ->
          {:halt, {:error, diagnostic("invalid_native_view", "native template view is invalid")}}
      end
    end)
  end

  defp source_models(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn
      {source_id, %{"status" => status, "generation" => generation} = source}, {:ok, models}
      when is_binary(source_id) and is_binary(status) and is_integer(generation) and
             generation >= 1 ->
        with :ok <- valid_optional?(source["result"], &is_list/1),
             :ok <- valid_optional?(source["error"], &is_map/1) do
          model =
            %{"status" => status, "generation" => generation}
            |> maybe_put("rows", source["result"])
            |> maybe_put("error", source["error"])

          {:cont, {:ok, Map.put(models, source_id, model)}}
        else
          :error ->
            {:halt,
             {:error, diagnostic("invalid_native_sources", "native template sources are invalid")}}
        end

      _source, _acc ->
        {:halt,
         {:error, diagnostic("invalid_native_sources", "native template sources are invalid")}}
    end)
  end

  defp valid_optional?(nil, _valid?), do: :ok
  defp valid_optional?(value, valid?), do: if(valid?.(value), do: :ok, else: :error)

  defp maybe_put(model, _key, nil), do: model
  defp maybe_put(model, key, value), do: Map.put(model, key, value)

  defp encode_dom_part(value) do
    for <<byte <- value>>, into: "" do
      if byte in ?0..?9 or byte in ?A..?Z or byte in ?a..?z or byte == ?_ do
        <<byte>>
      else
        "-" <> Base.encode16(<<byte>>)
      end
    end
  end

  defp diagnostic(code, message), do: TemplateInstance.diagnostic(code, message)
end
