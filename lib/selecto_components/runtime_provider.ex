defmodule SelectoComponents.RuntimeProvider do
  @moduledoc """
  Resolves a live Selecto runtime for a persisted export snapshot.

  Snapshots intentionally contain no connection handle or connection options.
  Host applications provide a runtime at render time, directly or through a
  provider configured under `:selecto_components, :runtime_provider`.
  """

  @callback resolve_runtime(map()) ::
              {:ok, Selecto.Runtime.Context.t() | map() | {module(), term()}}
              | {:error, term()}

  @spec resolve(map(), keyword()) ::
          {:ok, Selecto.Runtime.Context.t()} | {:error, Selecto.Error.t()}
  def resolve(snapshot, opts \\ []) when is_map(snapshot) do
    source =
      Keyword.get(opts, :runtime) ||
        resolve_with_provider(
          Keyword.get(opts, :runtime_provider) ||
            Application.get_env(:selecto_components, :runtime_provider),
          snapshot
        )

    normalize_runtime(source, snapshot)
  end

  defp resolve_with_provider(nil, _snapshot), do: nil

  defp resolve_with_provider(provider, snapshot) when is_function(provider, 1),
    do: provider.(snapshot)

  defp resolve_with_provider(provider, snapshot) when is_atom(provider) do
    if Code.ensure_loaded?(provider) and function_exported?(provider, :resolve_runtime, 1) do
      provider.resolve_runtime(snapshot)
    else
      {:error, {:invalid_runtime_provider, provider}}
    end
  end

  defp resolve_with_provider(provider, _snapshot),
    do: {:error, {:invalid_runtime_provider, provider}}

  defp normalize_runtime({:ok, runtime}, snapshot), do: normalize_runtime(runtime, snapshot)
  defp normalize_runtime({:error, reason}, _snapshot), do: runtime_error(reason)

  defp normalize_runtime(%Selecto.Runtime.Context{} = runtime, snapshot) do
    ensure_adapter_match(runtime, snapshot)
  end

  defp normalize_runtime(%{adapter: adapter, connection: connection} = runtime, snapshot) do
    metadata = Map.get(runtime, :metadata, %{})

    adapter
    |> Selecto.Runtime.Context.new(connection, metadata)
    |> ensure_adapter_match(snapshot)
  rescue
    error -> runtime_error(error)
  end

  defp normalize_runtime({adapter, connection}, snapshot) when is_atom(adapter) do
    normalize_runtime(%{adapter: adapter, connection: connection}, snapshot)
  end

  defp normalize_runtime(nil, _snapshot) do
    runtime_error(:runtime_not_provided)
  end

  defp normalize_runtime(runtime, _snapshot), do: runtime_error({:invalid_runtime, runtime})

  defp ensure_adapter_match(runtime, snapshot) do
    expected = Map.get(snapshot, :adapter)

    if is_nil(expected) or expected == runtime.adapter do
      {:ok, runtime}
    else
      runtime_error(%{
        reason: :adapter_mismatch,
        expected_adapter: expected,
        actual_adapter: runtime.adapter
      })
    end
  end

  defp runtime_error(reason) do
    {:error,
     Selecto.Error.configuration_error(
       "A live adapter runtime is required to render a persisted export snapshot",
       %{reason: reason}
     )}
  end
end
