defmodule SelectoComponents.QueryContract.Plug do
  @moduledoc """
  Plug endpoint for serving a Selecto query contract JSON document.

  Host applications can mount this plug at whatever route makes sense for their
  domain. The plug accepts a direct `:domain`, a compatibility `:resolver`, or
  a trusted `:registry` that resolves an opaque request id.
  """

  import Plug.Conn

  alias SelectoComponents.QueryContract
  alias SelectoComponents.DomainResolver
  alias SelectoComponents.QueryContract.HttpCache
  alias SelectoComponents.QueryContract.Links

  @behaviour Plug

  @impl Plug
  def init(opts), do: DomainResolver.init!(opts, __MODULE__)

  @impl Plug
  def call(conn, opts) do
    case DomainResolver.resolve(conn, opts, "query contract") do
      {:ok, input, resolved_opts} ->
        send_contract(conn, input, Keyword.merge(opts, resolved_opts))

      {:error, status, code, message} ->
        send_error(conn, status, code, message)
    end
  end

  defp send_contract(conn, input, opts) do
    opts = Links.with_request_defaults(conn, opts, :query_contract)

    case QueryContract.encode_json(input, opts) do
      {:ok, json, _diagnostics} ->
        send_json(conn, 200, json, opts)

      {:error, diagnostics} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(diagnostics_document(diagnostics)))
        |> halt()
    end
  end

  defp send_error(conn, status, code, message) do
    payload = QueryContract.json_safe(%{error: %{code: code, message: message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end

  defp send_json(conn, status, json, opts) do
    etag = HttpCache.etag(json)

    conn
    |> put_resp_content_type("application/json")
    |> put_link_header(opts)
    |> HttpCache.put_etag(etag)
    |> maybe_send_cached(status, json, etag)
  end

  defp put_link_header(conn, opts) do
    case Links.header(opts, :query_contract) do
      nil -> conn
      header -> put_resp_header(conn, "link", header)
    end
  end

  defp maybe_send_cached(conn, status, json, etag) do
    if status == 200 and HttpCache.not_modified?(conn, etag) do
      conn
      |> send_resp(304, "")
      |> halt()
    else
      conn
      |> send_resp(status, json)
      |> halt()
    end
  end

  defp diagnostics_document(diagnostics) do
    QueryContract.json_safe(%{
      error: %{code: :invalid_query_contract_domain, message: "query contract input is invalid"},
      diagnostics: %{
        errors: diagnostics.errors,
        warnings: diagnostics.warnings,
        schema_version: diagnostics.schema_version,
        schema_version_inferred: diagnostics.schema_version_inferred
      }
    })
  end
end
