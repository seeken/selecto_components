defmodule SelectoComponents.TemplateRenderer do
  @moduledoc """
  Renders a compiled Selecto template view through an explicit host registry.

  The compiled artifact contains component and element names, never Elixir
  modules or functions. The host maps those names to trusted one-argument
  function components:

      %{
        components: %{"Card" => &MyComponents.card/1},
        elements: %{"h2" => &MyComponents.heading/1},
        include: &MyComponents.include/1
      }

  Every callback receives a Phoenix component assigns map with resolved `:props`
  or `:attributes`, declared `:events`, safe rendered `:children`, and stable
  `:dom_id`/`:node_id` values. Callback output is passed through
  `Phoenix.HTML.Safe`, so a plain string is escaped; callbacks return HEEx or
  another explicit safe value when they intentionally produce markup.
  """

  use Phoenix.Component

  alias Phoenix.HTML.Safe

  @url_attributes ~w(href src poster action formaction xlink:href)

  attr(:manifest, :map, required: true)
  attr(:snapshot, :map, required: true)
  attr(:registry, :map, required: true)

  @doc "Renders a compiled view as a LiveView function component."
  def template(assigns) do
    case render(assigns.manifest, assigns.snapshot, assigns.registry) do
      {:ok, content} ->
        assigns = assign(assigns, :content, content)

        ~H"""
        {@content}
        """

      {:error, diagnostic} ->
        assigns = assign(assigns, :render_error_code, diagnostic["code"])

        ~H"""
        <div data-selecto-template-error={@render_error_code}>Template unavailable.</div>
        """
    end
  end

  @doc "Renders a compiled view to a Phoenix safe value without performing I/O."
  @spec render(map(), map(), map()) :: {:ok, Phoenix.HTML.safe()} | {:error, map()}
  def render(manifest, snapshot, registry), do: render(manifest, snapshot, registry, %{})

  @spec render(map(), map(), map(), map()) :: {:ok, Phoenix.HTML.safe()} | {:error, map()}
  def render(
        %{"view" => %{"schema" => "selecto.template.view.v1", "nodes" => nodes}} = manifest,
        snapshot,
        registry,
        slots
      )
      when is_list(nodes) and is_map(snapshot) and is_map(registry) and is_map(slots) do
    with {:ok, context} <- render_context(snapshot, manifest),
         :ok <- validate_slots(slots),
         {:ok, content} <- render_nodes(nodes, Map.put(context, :slots, slots), registry) do
      {:ok, content}
    end
  end

  def render(_manifest, _snapshot, _registry, _slots),
    do: {:error, diagnostic("invalid_render_input", "template render input is invalid", [])}

  defp validate_slots(slots) do
    if Enum.all?(slots, fn {name, value} ->
         is_binary(name) and match?({:safe, _}, value)
       end) do
      :ok
    else
      {:error, diagnostic("invalid_render_input", "template slots are invalid", [])}
    end
  end

  defp render_nodes(nodes, context, registry) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, chunks} ->
      case render_node(node, context, registry) do
        {:ok, {:safe, iodata}} -> {:cont, {:ok, [chunks, iodata]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, iodata} -> {:ok, {:safe, iodata}}
      error -> error
    end
  end

  defp render_node(
         %{"kind" => "text", "node_id" => node_id, "value" => value},
         _context,
         _registry
       )
       when is_binary(node_id) and is_binary(value) do
    {:ok, {:safe, escaped_iodata(value)}}
  end

  defp render_node(
         %{"kind" => "expression", "node_id" => node_id, "value" => value},
         context,
         _registry
       )
       when is_binary(node_id) do
    with {:ok, resolved} <- resolve_value(value, context, node_id),
         {:ok, iodata} <- display_iodata(resolved, node_id) do
      {:ok, {:safe, iodata}}
    end
  end

  defp render_node(
         %{
           "kind" => "component",
           "node_id" => node_id,
           "name" => name,
           "props" => props,
           "events" => events,
           "children" => children
         },
         context,
         registry
       )
       when is_binary(node_id) and is_binary(name) and is_map(props) and is_map(events) and
              is_list(children) do
    with {:ok, renderer} <- registry_renderer(registry, :components, name, node_id),
         {:ok, resolved_props} <- resolve_values(props, context, node_id),
         :ok <- validate_component_urls(resolved_props, registry, name, node_id),
         {:ok, rendered_children} <- render_nodes(children, context, registry) do
      invoke_renderer(
        renderer,
        %{
          node_id: node_id,
          dom_id: dom_id(context.instance_id, node_id),
          name: name,
          props: resolved_props,
          events: events,
          children: rendered_children
        },
        node_id
      )
    end
  end

  defp render_node(
         %{
           "kind" => "element",
           "node_id" => node_id,
           "name" => name,
           "attributes" => attributes,
           "children" => children
         },
         context,
         registry
       )
       when is_binary(node_id) and is_binary(name) and is_map(attributes) and is_list(children) do
    with {:ok, renderer} <- registry_renderer(registry, :elements, name, node_id),
         {:ok, resolved_attributes} <- resolve_values(attributes, context, node_id),
         :ok <- validate_url_attributes(resolved_attributes, node_id),
         {:ok, rendered_children} <- render_nodes(children, context, registry) do
      invoke_renderer(
        renderer,
        %{
          node_id: node_id,
          dom_id: dom_id(context.instance_id, node_id),
          name: name,
          attributes: resolved_attributes,
          children: rendered_children
        },
        node_id
      )
    end
  end

  defp render_node(
         %{
           "kind" => "condition",
           "node_id" => node_id,
           "test" => test,
           "then" => then_nodes,
           "else" => else_nodes
         },
         context,
         registry
       )
       when is_binary(node_id) and is_list(then_nodes) and is_list(else_nodes) do
    with {:ok, resolved} <- resolve_value(test, context, node_id) do
      case resolved do
        true ->
          render_nodes(then_nodes, context, registry)

        false ->
          render_nodes(else_nodes, context, registry)

        _other ->
          {:error, diagnostic("render_type_mismatch", "condition is not boolean", node_id)}
      end
    end
  end

  defp render_node(
         %{"kind" => "slot", "node_id" => node_id, "name" => name, "children" => children},
         context,
         registry
       )
       when is_binary(node_id) and is_binary(name) and is_list(children) do
    case Map.fetch(context.slots, name) do
      {:ok, content} -> {:ok, content}
      :error -> render_nodes(children, context, registry)
    end
  end

  defp render_node(
         %{
           "kind" => "include",
           "node_id" => node_id,
           "template" => template,
           "bindings" => bindings
         } = node,
         context,
         registry
       )
       when is_binary(node_id) and is_binary(template) and is_map(bindings) do
    with {:ok, renderer} <- include_renderer(registry, node_id),
         {:ok, slots} <- render_slots(Map.get(node, "slots", %{}), context, registry, node_id) do
      render_include(renderer, node_id, template, bindings, slots, context)
    end
  end

  defp render_node(node, _context, _registry) do
    node_id = if is_map(node), do: node["node_id"], else: nil
    {:error, diagnostic("invalid_render_node", "compiled render node is invalid", node_id)}
  end

  defp render_slots(slots, context, registry, node_id) when is_map(slots) do
    Enum.reduce_while(slots, {:ok, %{}}, fn {name, nodes}, {:ok, rendered} ->
      if is_binary(name) and is_list(nodes) do
        case render_nodes(nodes, context, registry) do
          {:ok, content} -> {:cont, {:ok, Map.put(rendered, name, content)}}
          {:error, error} -> {:halt, {:error, error}}
        end
      else
        {:halt,
         {:error, diagnostic("invalid_render_node", "compiled slots are invalid", node_id)}}
      end
    end)
  end

  defp render_slots(_slots, _context, _registry, node_id),
    do: {:error, diagnostic("invalid_render_node", "compiled slots are invalid", node_id)}

  defp render_include(renderer, node_id, template, bindings, slots, context) do
    source_bindings =
      Enum.filter(bindings, fn {_name, value} ->
        match?(%{"kind" => "binding", "type" => "source"}, value)
      end)

    case source_bindings do
      [] ->
        with {:ok, resolved} <- resolve_values(bindings, context, node_id) do
          invoke_include(renderer, node_id, template, resolved, slots, context)
        end

      _ ->
        render_source_include(
          renderer,
          node_id,
          template,
          bindings,
          source_bindings,
          slots,
          context
        )
    end
  end

  defp render_source_include(
         renderer,
         node_id,
         template,
         bindings,
         source_bindings,
         slots,
         context
       ) do
    with {:ok, source, relationships} <- source_relationships(source_bindings, context, node_id),
         {:ok, fixed} <-
           resolve_values(
             Map.drop(bindings, Enum.map(source_bindings, &elem(&1, 0))),
             context,
             node_id
           ),
         {:ok, rows} <- source_rows(context.sources[source], node_id) do
      Enum.with_index(rows)
      |> Enum.reduce_while({:ok, []}, fn {row, index}, {:ok, chunks} ->
        with {:ok, resolved} <- row_relationships(row, relationships, fixed, node_id),
             item_id = "#{node_id}.row.#{index}",
             {:ok, {:safe, content}} <-
               invoke_include(renderer, item_id, template, resolved, slots, context) do
          {:cont, {:ok, [chunks, content]}}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, content} -> {:ok, {:safe, content}}
        error -> error
      end
    end
  end

  defp source_relationships(bindings, context, node_id) do
    relationships =
      Enum.map(bindings, fn {name, value} ->
        case value do
          %{"expression" => expression} when is_binary(expression) ->
            case String.split(expression, ".") do
              [source] ->
                {name, source, nil}

              [source, relationship] when relationship != "rows" ->
                {name, source, relationship}

              _ ->
                :invalid
            end

          _ ->
            :invalid
        end
      end)

    sources =
      Enum.map(relationships, fn
        {_name, source, _relationship} -> source
        :invalid -> nil
      end)

    case Enum.uniq(sources) do
      [source] when is_binary(source) and is_map_key(context.sources, source) ->
        {:ok, source,
         Enum.map(relationships, fn {name, _, relationship} -> {name, relationship} end)}

      _ ->
        {:error,
         diagnostic("render_type_mismatch", "include source bindings are incompatible", node_id)}
    end
  end

  defp source_rows(nil, _node_id), do: {:ok, []}
  defp source_rows(rows, _node_id) when is_list(rows), do: {:ok, rows}

  defp source_rows(_rows, node_id),
    do: {:error, diagnostic("render_type_mismatch", "include source rows are invalid", node_id)}

  defp row_relationships(row, relationships, fixed, node_id) when is_map(row) do
    Enum.reduce_while(relationships, {:ok, fixed}, fn {name, relationship}, {:ok, acc} ->
      value = if is_nil(relationship), do: row, else: row[relationship]

      if is_nil(value) or is_map(value) do
        {:cont, {:ok, Map.put(acc, name, value)}}
      else
        {:halt,
         {:error,
          diagnostic("render_type_mismatch", "include relationship is not an object", node_id)}}
      end
    end)
  end

  defp row_relationships(_row, _relationships, _fixed, node_id),
    do: {:error, diagnostic("render_type_mismatch", "include source row is invalid", node_id)}

  defp invoke_include(renderer, node_id, template, bindings, slots, context) do
    assigns = %{
      node_id: node_id,
      dom_id: dom_id(context.instance_id, node_id),
      template: template,
      bindings: bindings
    }

    assigns = if slots == %{}, do: assigns, else: Map.put(assigns, :slots, slots)

    invoke_renderer(
      renderer,
      assigns,
      node_id
    )
  end

  defp render_context(
         %{
           "instance_id" => instance_id,
           "inputs" => inputs,
           "state" => state,
           "sources" => sources
         },
         manifest
       )
       when is_binary(instance_id) and instance_id != "" and is_map(inputs) and is_map(state) and
              is_map(sources) do
    source_results =
      Map.new(sources, fn {name, source} ->
        result = if is_map(source), do: source["result"], else: nil
        {name, public_rows(result)}
      end)

    source_totals =
      Map.new(sources, fn {name, source} ->
        result = if is_map(source), do: source["result"], else: nil
        {name, if(is_map(result), do: result["totals"], else: nil)}
      end)

    source_ready =
      Map.new(sources, fn {name, source} ->
        {name, is_map(source) and source["status"] == "ready"}
      end)

    source_page_sizes =
      Map.new(manifest["sources"] || [], fn source ->
        {source["id"], get_in(source, ["query", "limit"])}
      end)

    {:ok,
     %{
       instance_id: instance_id,
       inputs: inputs,
       state: state,
       sources: source_results,
       source_totals: source_totals,
       source_ready: source_ready,
       source_page_sizes: source_page_sizes
     }}
  end

  defp render_context(_snapshot, _manifest),
    do: {:error, diagnostic("invalid_render_snapshot", "template snapshot is invalid", [])}

  defp public_rows(%{"rows" => rows} = result) when is_list(rows) do
    if Map.has_key?(result, "pages") and not is_list(result["pages"]),
      do: nil,
      else: rows
  end

  defp public_rows(rows) when is_list(rows), do: rows
  defp public_rows(_result), do: nil

  defp resolve_values(values, context, node_id) do
    Enum.reduce_while(values, {:ok, %{}}, fn {name, value}, {:ok, resolved} ->
      case resolve_value(value, context, node_id) do
        {:ok, item} -> {:cont, {:ok, Map.put(resolved, name, item)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp resolve_value(
         %{"kind" => "literal", "type" => type, "value" => value},
         _context,
         node_id
       ) do
    if value_matches_type?(value, type) do
      {:ok, value}
    else
      {:error,
       diagnostic("render_type_mismatch", "literal render value has the wrong type", node_id)}
    end
  end

  defp resolve_value(
         %{"kind" => "binding", "type" => type, "expression" => expression},
         context,
         node_id
       )
       when is_binary(expression) do
    with {:ok, value} <- resolve_expression(expression, context, node_id),
         true <- is_nil(value) or value_matches_type?(value, type) do
      {:ok, value}
    else
      false ->
        {:error,
         diagnostic("render_type_mismatch", "bound render value has the wrong type", node_id)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp resolve_value(_value, _context, node_id),
    do: {:error, diagnostic("invalid_render_value", "compiled render value is invalid", node_id)}

  defp resolve_expression("present(" <> rest, context, node_id) do
    if String.ends_with?(rest, ")") do
      expression = String.slice(rest, 0, byte_size(rest) - 1)

      case resolve_expression(expression, context, node_id) do
        {:ok, value} -> {:ok, not is_nil(value)}
        error -> error
      end
    else
      unsupported_expression(node_id)
    end
  end

  defp resolve_expression("state." <> name, context, node_id),
    do: resolve_member(context.state, name, node_id)

  defp resolve_expression("input." <> name, context, node_id),
    do: resolve_member(context.inputs, name, node_id)

  defp resolve_expression(expression, context, node_id) do
    case String.split(expression, ".") do
      [source, "rows"] when is_map_key(context.sources, source) ->
        {:ok, context.sources[source]}

      [source, "ready"] when is_map_key(context.source_ready, source) ->
        {:ok, context.source_ready[source]}

      [source, "page_size"] when is_map_key(context.source_page_sizes, source) ->
        case context.source_page_sizes[source] do
          size when is_integer(size) and size > 0 -> {:ok, size}
          _other -> unsupported_expression(node_id)
        end

      [source, "totals", total] when is_map_key(context.source_totals, source) ->
        totals = context.source_totals[source]

        cond do
          is_map(totals) and Map.has_key?(totals, total) -> {:ok, totals[total]}
          context.source_ready[source] -> unsupported_expression(node_id)
          true -> {:ok, nil}
        end

      [input | path] when path != [] and is_map_key(context.inputs, input) ->
        {:ok, resolve_path(context.inputs[input], path)}

      [input] when is_map_key(context.inputs, input) ->
        {:ok, context.inputs[input]}

      _other ->
        unsupported_expression(node_id)
    end
  end

  defp resolve_member(values, name, node_id) do
    if Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, name) and Map.has_key?(values, name) do
      {:ok, values[name]}
    else
      unsupported_expression(node_id)
    end
  end

  defp resolve_path(value, []), do: value

  defp resolve_path(value, [segment | rest]) when is_map(value),
    do: resolve_path(value[segment], rest)

  defp resolve_path(_value, _path), do: nil

  defp registry_renderer(registry, group, name, node_id) do
    renderers = Map.get(registry, group, Map.get(registry, Atom.to_string(group), %{}))

    case is_map(renderers) && renderers[name] do
      renderer when is_function(renderer, 1) ->
        {:ok, renderer}

      _other ->
        {:error, diagnostic("unavailable_renderer", "host renderer is unavailable", node_id)}
    end
  end

  defp include_renderer(registry, node_id) do
    case Map.get(registry, :include, Map.get(registry, "include")) do
      renderer when is_function(renderer, 1) ->
        {:ok, renderer}

      _other ->
        {:error,
         diagnostic("unavailable_include_renderer", "include renderer is unavailable", node_id)}
    end
  end

  defp invoke_renderer(renderer, assigns, node_id) do
    try do
      component_assigns = Map.put(assigns, :__changed__, nil)
      {:ok, {:safe, Safe.to_iodata(renderer.(component_assigns))}}
    rescue
      _exception ->
        {:error, diagnostic("renderer_failed", "host renderer failed", node_id)}
    catch
      _kind, _reason ->
        {:error, diagnostic("renderer_failed", "host renderer failed", node_id)}
    end
  end

  defp display_iodata(nil, _node_id), do: {:ok, []}

  defp display_iodata(value, _node_id)
       when is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value),
       do: {:ok, escaped_iodata(to_string(value))}

  defp display_iodata(_value, node_id),
    do: {:error, diagnostic("invalid_display_value", "render expression is not scalar", node_id)}

  defp escaped_iodata(value), do: value |> Phoenix.HTML.html_escape() |> Safe.to_iodata()

  defp validate_component_urls(props, registry, component, node_id) do
    case Map.get(registry, :url_props) do
      nil ->
        :ok

      policies when is_map(policies) ->
        validate_component_url_policy(props, Map.get(policies, component), node_id)

      _ ->
        {:error, diagnostic("invalid_render_input", "component URL policy is invalid", node_id)}
    end
  end

  defp validate_component_url_policy(_props, nil, _node_id), do: :ok

  defp validate_component_url_policy(props, policy, node_id) when is_map(policy) do
    if Enum.all?(policy, fn
         {prop, attribute} when is_binary(prop) and attribute in @url_attributes ->
           not Map.has_key?(props, prop) or valid_url?(attribute, props[prop])

         _ ->
           false
       end) do
      :ok
    else
      {:error, diagnostic("invalid_url_attribute", "component URL prop is invalid", node_id)}
    end
  end

  defp validate_component_url_policy(_props, _policy, node_id),
    do: {:error, diagnostic("invalid_render_input", "component URL policy is invalid", node_id)}

  defp validate_url_attributes(attributes, node_id) do
    if Enum.all?(attributes, fn
         {name, value} when name in @url_attributes -> valid_url?(name, value)
         _ -> true
       end) do
      :ok
    else
      {:error, diagnostic("invalid_url_attribute", "element URL attribute is invalid", node_id)}
    end
  end

  defp valid_url?(_name, nil), do: true

  defp valid_url?(name, value) when is_binary(value) do
    String.valid?(value) and byte_size(value) in 1..2048 and
      not Enum.any?(String.to_charlist(value), &(&1 <= 32 or &1 in [92, 127])) and
      (root_relative_url?(value) or
         (name in ["href", "xlink:href"] and
            (String.starts_with?(value, ["#", "?"]) and byte_size(value) > 1)) or
         (name == "href" and
            (nonempty_scheme?(value, "mailto:") or nonempty_scheme?(value, "tel:"))) or
         (name in ["href", "xlink:href", "src", "poster"] and web_url?(value)))
  end

  defp valid_url?(_name, _value), do: false

  defp root_relative_url?(value),
    do: String.starts_with?(value, "/") and not String.starts_with?(value, "//")

  defp nonempty_scheme?(value, prefix),
    do: String.starts_with?(value, prefix) and byte_size(value) > byte_size(prefix)

  defp web_url?(value) do
    case Regex.run(~r/\Ahttps?:\/\/([^\/?#]+)(?:[\/?#].*)?\z/u, value, capture: :all_but_first) do
      [authority] ->
        not String.contains?(authority, "@") and
          Regex.match?(~r/\A(?:[A-Za-z0-9]|\[)[A-Za-z0-9.:\-\[\]]*\z/, authority)

      _ ->
        false
    end
  end

  defp value_matches_type?(_value, "any"), do: true
  defp value_matches_type?(value, "boolean"), do: is_boolean(value)
  defp value_matches_type?(value, "integer"), do: is_integer(value)
  defp value_matches_type?(value, "rows"), do: is_list(value)
  defp value_matches_type?(value, "string"), do: is_binary(value)
  defp value_matches_type?(_value, _type), do: false

  defp dom_id(instance_id, node_id) do
    "selecto-template-#{encode_dom_part(instance_id)}-#{encode_dom_part(node_id)}"
  end

  defp encode_dom_part(value) do
    for <<byte <- value>>, into: "" do
      if byte in ?0..?9 or byte in ?A..?Z or byte in ?a..?z or byte == ?_ do
        <<byte>>
      else
        "-" <> Base.encode16(<<byte>>)
      end
    end
  end

  defp unsupported_expression(node_id),
    do:
      {:error,
       diagnostic("unsupported_expression", "render expression is not supported", node_id)}

  defp diagnostic(code, message, node_id) do
    path = if is_binary(node_id) and node_id != "", do: ["view", node_id], else: []

    %{
      "schema" => "selecto.template.diagnostic.v1",
      "severity" => "error",
      "code" => code,
      "message" => message,
      "path" => path
    }
  end
end
