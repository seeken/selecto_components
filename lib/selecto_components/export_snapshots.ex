defmodule SelectoComponents.ExportSnapshots do
  @moduledoc """
  Shared snapshot and persistence helpers for export-oriented features.

  Exported views and scheduled exports both need the same persisted Selecto view
  snapshot shape. This module keeps that logic in one place so the query/view
  reconstruction contract stays consistent across features.
  """

  alias SelectoComponents.Form.ParamsState

  @snapshot_version 2

  @doc """
  Build a persisted snapshot payload from current SelectoComponents assigns.
  """
  @spec build_snapshot(map()) :: map()
  def build_snapshot(assigns) when is_map(assigns) do
    selecto = Map.fetch!(assigns, :selecto)

    adapter = Map.get(selecto, :adapter)

    %{
      version: @snapshot_version,
      params: ParamsState.view_config_to_params(Map.fetch!(assigns, :view_config)),
      views: Map.fetch!(assigns, :views),
      domain: Map.fetch!(selecto, :domain),
      adapter: adapter,
      adapter_name: Selecto.AdapterSupport.adapter_name(adapter),
      capability_evidence: snapshot_capabilities(adapter),
      runtime_key: runtime_key(assigns, selecto),
      path: Map.get(assigns, :path) || Map.get(assigns, :my_path),
      context:
        Map.get(assigns, :scheduled_export_context) || Map.get(assigns, :exported_view_context) ||
          Map.get(assigns, :saved_view_context) || Map.get(assigns, :domain) ||
          Map.get(assigns, :path),
      current_user_id: Map.get(assigns, :current_user_id),
      tenant_context: Map.get(assigns, :tenant_context)
    }
  end

  @doc """
  Encode a safe Elixir term for persistence.
  """
  @spec encode_term(term()) :: binary()
  def encode_term(term) do
    blob = :erlang.term_to_binary(term, compressed: 6)

    case decode_term(blob) do
      {:ok, _term} ->
        blob

      {:error, :invalid_blob} ->
        raise ArgumentError,
              "cannot persist snapshot terms that require unsafe deserialization"
    end
  end

  @doc """
  Decode a previously encoded persistence blob.
  """
  @spec decode_term(binary() | nil) :: {:ok, term()} | {:error, :invalid_blob | :missing}
  def decode_term(nil), do: {:error, :missing}

  def decode_term(blob) when is_binary(blob) do
    term = :erlang.binary_to_term(blob, [:safe])

    case persistable_term?(term) do
      true -> {:ok, term}
      false -> {:error, :invalid_blob}
    end
  rescue
    _ -> {:error, :invalid_blob}
  end

  defp persistable_term?(term)
       when is_function(term) or is_pid(term) or is_port(term) or is_reference(term),
       do: false

  defp persistable_term?(term) when is_list(term), do: Enum.all?(term, &persistable_term?/1)

  defp persistable_term?(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.all?(&persistable_term?/1)
  end

  defp persistable_term?(term) when is_map(term) do
    Enum.all?(term, fn {key, value} -> persistable_term?(key) and persistable_term?(value) end)
  end

  defp persistable_term?(_term), do: true

  defp snapshot_capabilities(adapter) do
    %{text_search: Selecto.AdapterSupport.capability(adapter, :text_search)}
  end

  defp runtime_key(assigns, selecto) do
    metadata =
      case Map.get(selecto, :runtime) do
        %Selecto.Runtime.Context{metadata: metadata} -> metadata
        _runtime -> %{}
      end

    Map.get(assigns, :runtime_key) || Map.get(metadata, :key) || Map.get(metadata, "key") ||
      Map.get(assigns, :exported_view_context) || Map.get(assigns, :scheduled_export_context) ||
      Map.get(assigns, :saved_view_context) || Map.get(assigns, :path) ||
      Map.get(assigns, :my_path)
  end
end
