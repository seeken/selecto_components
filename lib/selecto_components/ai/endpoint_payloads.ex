defmodule SelectoComponents.AI.EndpointPayloads do
  @moduledoc """
  Endpoint-ready payload helpers for external AI documentation surfaces.

  This module keeps routing/controller ownership in the host app while giving it
  a stable way to produce contract JSON and guide text/markdown from the same
  SelectoComponents AI foundation.
  """

  alias SelectoComponents.AI.QueryContract
  alias SelectoComponents.AI.QueryGuide

  @spec query_contract(term(), list(), keyword()) :: map()
  def query_contract(selecto, views, opts \\ []) when is_list(views) do
    contract = QueryContract.generate(selecto, views, opts)

    %{
      content_type: "application/json",
      filename: filename(selecto, "query_contract.json"),
      body: Jason.encode!(contract, pretty: true),
      data: contract
    }
  end

  @spec query_guide(term(), list(), keyword()) :: map()
  def query_guide(selecto, views, opts \\ []) when is_list(views) do
    contract = QueryContract.generate(selecto, views, opts)
    guide = QueryGuide.render(contract)
    format = Keyword.get(opts, :format, :markdown)

    content_type =
      case format do
        :text -> "text/plain; charset=utf-8"
        _ -> "text/markdown; charset=utf-8"
      end

    extension = if format == :text, do: "query_guide.txt", else: "query_guide.md"

    %{
      content_type: content_type,
      filename: filename(selecto, extension),
      body: guide,
      data: %{
        "contract" => contract,
        "guide" => guide
      }
    }
  end

  @spec query_guide_link(String.t() | nil, term(), keyword()) :: String.t() | nil
  def query_guide_link(base_url, selecto, opts \\ []) do
    path = Keyword.get(opts, :guide_path)

    case {normalize_base_url(base_url), normalize_path(path), domain_slug(selecto)} do
      {nil, _path, _slug} -> nil
      {_base, nil, _slug} -> nil
      {base, path, _slug} -> base <> path
    end
  end

  @spec query_contract_link(String.t() | nil, term(), keyword()) :: String.t() | nil
  def query_contract_link(base_url, selecto, opts \\ []) do
    path = Keyword.get(opts, :contract_path)

    case {normalize_base_url(base_url), normalize_path(path), domain_slug(selecto)} do
      {nil, _path, _slug} -> nil
      {_base, nil, _slug} -> nil
      {base, path, _slug} -> base <> path
    end
  end

  defp filename(selecto, suffix) do
    "selecto_#{domain_slug(selecto)}_#{suffix}"
  end

  defp domain_slug(selecto) do
    selecto
    |> Selecto.domain()
    |> Map.get(:name, "unknown_domain")
    |> to_string()
    |> Macro.underscore()
  end

  defp normalize_base_url(nil), do: nil

  defp normalize_base_url(base_url) when is_binary(base_url) do
    case String.trim(base_url) do
      "" -> nil
      trimmed -> String.trim_trailing(trimmed, "/")
    end
  end

  defp normalize_base_url(_), do: nil

  defp normalize_path(nil), do: nil

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" ->
        nil

      trimmed ->
        if String.starts_with?(trimmed, "/") do
          trimmed
        else
          "/" <> trimmed
        end
    end
  end

  defp normalize_path(_), do: nil
end
