defmodule SelectoComponents.QueryContract.Guide.Plug do
  @moduledoc """
  Plug endpoint for serving a Markdown Selecto query guide.

  Host applications can mount this beside `SelectoComponents.QueryContract.Plug`
  to expose a readable companion to `query_contract.json`.
  """

  import Plug.Conn

  alias SelectoComponents.QueryContract
  alias SelectoComponents.DomainResolver
  alias SelectoComponents.QueryContract.Guide
  alias SelectoComponents.QueryContract.HttpCache
  alias SelectoComponents.QueryContract.Links

  @behaviour Plug

  @impl Plug
  def init(opts), do: DomainResolver.init!(opts, __MODULE__)

  @impl Plug
  def call(conn, opts) do
    case DomainResolver.resolve(conn, opts, "query guide") do
      {:ok, input, resolved_opts} ->
        send_guide(conn, input, Keyword.merge(opts, resolved_opts))

      {:error, status, code, message} ->
        send_error(conn, status, code, message)
    end
  end

  defp send_guide(conn, input, opts) do
    opts = Links.with_request_defaults(conn, opts, :query_guide)

    case Guide.markdown(input, opts) do
      {:ok, markdown, _diagnostics} ->
        send_markdown(conn, 200, markdown, opts)

      {:error, diagnostics} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(422, Jason.encode!(diagnostics_document(diagnostics)))
        |> halt()
    end
  end

  defp put_link_header(conn, opts) do
    case Links.header(opts, :query_guide) do
      nil -> conn
      header -> put_resp_header(conn, "link", header)
    end
  end

  defp send_markdown(conn, status, markdown, opts) do
    etag = HttpCache.etag(markdown)

    conn
    |> put_resp_content_type("text/markdown")
    |> put_link_header(opts)
    |> HttpCache.put_etag(etag)
    |> maybe_send_cached(status, markdown, etag)
  end

  defp maybe_send_cached(conn, status, markdown, etag) do
    if status == 200 and HttpCache.not_modified?(conn, etag) do
      conn
      |> send_resp(304, "")
      |> halt()
    else
      conn
      |> send_resp(status, markdown)
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

  defp diagnostics_document(diagnostics) do
    QueryContract.json_safe(%{
      error: %{code: :invalid_query_contract_domain, message: "query guide input is invalid"},
      diagnostics: %{
        errors: diagnostics.errors,
        warnings: diagnostics.warnings,
        schema_version: diagnostics.schema_version,
        schema_version_inferred: diagnostics.schema_version_inferred
      }
    })
  end
end
