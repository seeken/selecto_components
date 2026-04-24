defmodule SelectoComponents.AI.WebMCP do
  @moduledoc """
  WebMCP-ready helpers for exposing SelectoComponents AI resources and tools.

  This module does not implement an HTTP server or router. It gives host apps a
  reusable library-level surface for publishing MCP-style resources and tools on
  top of the existing AI foundation.
  """

  alias SelectoComponents.AI.EndpointPayloads
  alias SelectoComponents.AI.IntentImport
  alias SelectoComponents.AI.IntentNormalizer
  alias SelectoComponents.AI.IntentValidator
  alias SelectoComponents.AI.QueryContract

  @spec resources(term(), list(), keyword()) :: list(map())
  def resources(selecto, views, opts \\ []) when is_list(views) do
    slug = domain_slug(selecto)
    base_uri = Keyword.get(opts, :base_uri, "mcp://selecto/#{slug}")

    [
      %{
        "name" => "query_contract",
        "title" => "Selecto Query Contract",
        "uri" => "#{base_uri}/query-contract.json",
        "mimeType" => "application/json",
        "description" => "Machine-readable contract describing fields, params, and capabilities."
      },
      %{
        "name" => "query_guide",
        "title" => "Selecto Query Guide",
        "uri" => "#{base_uri}/query-guide.md",
        "mimeType" => "text/markdown",
        "description" =>
          "AI-readable guide explaining how to construct valid Selecto query state."
      }
    ]
  end

  @spec read_resource(String.t(), term(), list(), keyword()) :: map()
  def read_resource(uri, selecto, views, opts \\ []) when is_binary(uri) and is_list(views) do
    cond do
      String.ends_with?(uri, "/query-contract.json") ->
        payload = EndpointPayloads.query_contract(selecto, views, opts)
        resource_response(uri, payload.content_type, payload.body, payload.data)

      String.ends_with?(uri, "/query-guide.md") ->
        payload =
          EndpointPayloads.query_guide(selecto, views, Keyword.put(opts, :format, :markdown))

        resource_response(uri, payload.content_type, payload.body, payload.data)

      true ->
        %{
          "uri" => uri,
          "mimeType" => "text/plain; charset=utf-8",
          "text" => "Unknown resource",
          "data" => nil
        }
    end
  end

  @spec tools(term(), list(), keyword()) :: list(map())
  def tools(selecto, views, opts \\ []) when is_list(views) do
    _contract = QueryContract.generate(selecto, views, opts)

    [
      %{
        "name" => "validate_intent",
        "title" => "Validate Selecto AI intent",
        "description" => "Validate structured AI intent JSON against the query contract.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["intent"],
          "properties" => %{
            "intent" => %{"type" => "object"}
          }
        }
      },
      %{
        "name" => "preview_intent",
        "title" => "Preview Selecto AI intent",
        "description" =>
          "Validate and build preview/diff packaging for structured AI intent JSON.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["intent"],
          "properties" => %{
            "intent" => %{"type" => "object"}
          }
        }
      },
      %{
        "name" => "normalize_intent",
        "title" => "Normalize Selecto AI intent",
        "description" => "Normalize AI intent into a stable internal shape before application.",
        "inputSchema" => %{
          "type" => "object",
          "required" => ["intent"],
          "properties" => %{
            "intent" => %{"type" => "object"}
          }
        }
      }
    ]
  end

  @spec call_tool(String.t(), map(), term(), list(), keyword()) :: map()
  def call_tool(name, arguments, selecto, views, opts \\ [])
      when is_binary(name) and is_map(arguments) and is_list(views) do
    contract = QueryContract.generate(selecto, views, opts)
    intent = Map.get(arguments, "intent", Map.get(arguments, :intent, %{}))

    case name do
      "validate_intent" ->
        validation = IntentValidator.validate(intent, contract)
        tool_response(validation, not validation.ok)

      "normalize_intent" ->
        normalized = IntentNormalizer.normalize(intent)
        tool_response(normalized, false)

      "preview_intent" ->
        case Keyword.get(opts, :socket) do
          %Phoenix.LiveView.Socket{} = socket ->
            result = IntentImport.import(Jason.encode!(intent), contract, socket)
            tool_response(result, not result.ok)

          _ ->
            tool_response(%{"error" => "preview_intent requires a socket option"}, true)
        end

      _ ->
        tool_response(%{"error" => "Unknown tool"}, true)
    end
  end

  defp resource_response(uri, mime_type, body, data) do
    %{
      "uri" => uri,
      "mimeType" => mime_type,
      "text" => body,
      "data" => data
    }
  end

  defp tool_response(result, is_error?) do
    structured = json_like(result)
    encoded = Jason.encode!(structured, pretty: true)

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => encoded
        }
      ],
      "structuredContent" => structured,
      "isError" => is_error?
    }
  end

  defp domain_slug(selecto) do
    selecto
    |> Selecto.domain()
    |> Map.get(:name, "unknown_domain")
    |> to_string()
    |> Macro.underscore()
  end

  defp json_like(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_like(value)} end)
  end

  defp json_like(list) when is_list(list), do: Enum.map(list, &json_like/1)
  defp json_like(other), do: other
end
