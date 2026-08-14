defmodule SelectoComponents.DomainResolver do
  @moduledoc """
  Resolves trusted domain inputs for Components HTTP and LiveView boundaries.

  A caller must configure exactly one of `:domain`, `:resolver`, or `:registry`.
  Registry mode resolves the request's opaque domain id through
  `Selecto.Domain.Registry` and never accepts an authored map from the client.
  """

  alias Selecto.Domain.{Ref, Registry, RegistryError}

  @source_keys [:domain, :resolver, :registry]

  @spec init!(keyword(), module()) :: keyword()
  def init!(opts, caller) do
    sources = Enum.filter(@source_keys, &Keyword.has_key?(opts, &1))

    case sources do
      [_source] ->
        opts

      [] ->
        raise ArgumentError, "expected :domain, :resolver, or :registry for #{inspect(caller)}"

      _ ->
        raise ArgumentError, "expected exactly one domain source for #{inspect(caller)}"
    end
  end

  @spec resolve(Plug.Conn.t(), keyword(), String.t()) ::
          {:ok, map(), keyword()} | {:error, pos_integer(), atom(), String.t()}
  def resolve(conn, opts, label) do
    cond do
      Keyword.has_key?(opts, :domain) ->
        {:ok, Keyword.fetch!(opts, :domain), []}

      Keyword.has_key?(opts, :registry) ->
        resolve_registry(conn, opts, label)

      true ->
        resolve_function(conn, Keyword.fetch!(opts, :resolver), label)
    end
  end

  @spec resolve_ref(Ref.t(), map()) :: {:ok, map()} | {:error, RegistryError.t()}
  def resolve_ref(%Ref{} = ref, context \\ %{}) do
    case Registry.resolve(ref.registry, ref.id, context) do
      {:ok, domain, _resolved_ref} -> {:ok, domain}
      {:error, error} -> {:error, error}
    end
  end

  @spec domain_id(Plug.Conn.t(), keyword()) :: term()
  def domain_id(conn, opts) do
    Keyword.get(opts, :domain_id) ||
      fetch_conn_value(conn.path_params, "domain") ||
      fetch_conn_value(conn.path_params, :domain) ||
      fetch_conn_value(conn.params, "domain") ||
      fetch_conn_value(conn.params, :domain) ||
      fetch_conn_value(conn.assigns, :selecto_domain) ||
      fetch_conn_value(conn.assigns, :domain)
  end

  defp resolve_registry(conn, opts, label) do
    registry = Keyword.fetch!(opts, :registry)
    id = domain_id(conn, opts)

    with {:ok, context} <- registry_context(conn, opts, label),
         {:ok, domain, ref} <- Registry.resolve(registry, id, context),
         {:ok, registry_opts} <- registry_options(conn, opts, label) do
      resolved_opts =
        registry_opts
        |> Keyword.put(:domain_id, ref.id)
        |> Keyword.put(:domain_ref, ref)

      {:ok, domain, resolved_opts}
    else
      {:error, %RegistryError{} = error} -> registry_error(error, label)
      {:error, status, code, message} -> {:error, status, code, message}
    end
  end

  defp registry_options(conn, opts, label) do
    case Keyword.get(opts, :registry_options, []) do
      registry_opts when is_list(registry_opts) -> {:ok, registry_opts}
      resolver when is_function(resolver, 1) -> normalize_registry_options(resolver.(conn), label)
      _other -> {:error, 500, :invalid_registry_options, "#{label} registry options are invalid"}
    end
  rescue
    _exception -> {:error, 500, :registry_options_failed, "#{label} registry options failed"}
  end

  defp normalize_registry_options({:ok, registry_opts}, _label) when is_list(registry_opts),
    do: {:ok, registry_opts}

  defp normalize_registry_options({:error, _reason}, label),
    do: {:error, 500, :registry_options_failed, "#{label} registry options failed"}

  defp normalize_registry_options(registry_opts, _label) when is_list(registry_opts),
    do: {:ok, registry_opts}

  defp normalize_registry_options(_registry_opts, label),
    do: {:error, 500, :invalid_registry_options, "#{label} registry options are invalid"}

  defp registry_context(conn, opts, label) do
    case Keyword.get(opts, :registry_context, %{}) do
      context when is_map(context) -> {:ok, context}
      resolver when is_function(resolver, 1) -> normalize_context_result(resolver.(conn), label)
      _other -> {:error, 500, :invalid_registry_context, "#{label} registry context is invalid"}
    end
  rescue
    _exception -> {:error, 500, :registry_context_failed, "#{label} registry context failed"}
  end

  defp normalize_context_result({:ok, context}, _label) when is_map(context), do: {:ok, context}

  defp normalize_context_result({:error, _reason}, label),
    do: {:error, 500, :registry_context_failed, "#{label} registry context failed"}

  defp normalize_context_result(context, _label) when is_map(context), do: {:ok, context}

  defp normalize_context_result(_context, label),
    do: {:error, 500, :invalid_registry_context, "#{label} registry context is invalid"}

  defp resolve_function(conn, resolver, label) do
    result =
      cond do
        is_function(resolver, 1) -> resolver.(conn)
        is_function(resolver, 2) -> resolver.(domain_id(conn, []), conn)
        true -> {:error, :invalid_resolver}
      end

    normalize_resolver_result(result, label)
  rescue
    _exception -> {:error, 500, :resolver_failed, "#{label} resolver failed"}
  end

  defp normalize_resolver_result({:ok, input}, _label), do: {:ok, input, []}

  defp normalize_resolver_result({:ok, input, opts}, _label) when is_list(opts),
    do: {:ok, input, opts}

  defp normalize_resolver_result({:error, :invalid_resolver}, label),
    do: {:error, 500, :invalid_resolver, "#{label} resolver must be a one- or two-arity function"}

  defp normalize_resolver_result({:error, _reason}, label),
    do: {:error, 404, :not_found, "#{label} domain not found"}

  defp normalize_resolver_result(nil, label),
    do: {:error, 404, :not_found, "#{label} domain not found"}

  defp normalize_resolver_result({input, opts}, _label) when is_list(opts),
    do: {:ok, input, opts}

  defp normalize_resolver_result(input, _label), do: {:ok, input, []}

  defp registry_error(%RegistryError{reason: reason}, label)
       when reason in [:not_found, :forbidden],
       do: {:error, 404, :not_found, "#{label} domain not found"}

  defp registry_error(%RegistryError{}, label),
    do: {:error, 500, :registry_failed, "#{label} registry failed"}

  defp fetch_conn_value(map, key) when is_map(map), do: Map.get(map, key)
  defp fetch_conn_value(_map, _key), do: nil
end
