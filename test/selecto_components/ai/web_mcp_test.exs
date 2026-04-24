defmodule SelectoComponents.AI.WebMCPTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.WebMCP

  test "resources returns contract and guide resources" do
    resources = WebMCP.resources(selecto(), views())

    assert Enum.any?(resources, &(&1["name"] == "query_contract"))
    assert Enum.any?(resources, &(&1["name"] == "query_guide"))
  end

  test "read_resource returns contract payload" do
    resource =
      WebMCP.read_resource(
        "mcp://selecto/orders_reporting/query-contract.json",
        selecto(),
        views()
      )

    assert resource["mimeType"] == "application/json"
    assert resource["text"] =~ "query_contract_version"
    assert resource["data"]["domain"]["id"] == "OrdersReporting"
  end

  test "tools returns validate, normalize, and preview tools" do
    tools = WebMCP.tools(selecto(), views())

    assert Enum.any?(tools, &(&1["name"] == "validate_intent"))
    assert Enum.any?(tools, &(&1["name"] == "normalize_intent"))
    assert Enum.any?(tools, &(&1["name"] == "preview_intent"))
  end

  test "call_tool validate_intent returns structured validation result" do
    result =
      WebMCP.call_tool(
        "validate_intent",
        %{
          "intent" => %{
            "intent_version" => 1,
            "mode" => "replace",
            "view_mode" => "detail",
            "selected" => [%{"field" => "status"}]
          }
        },
        selecto(),
        views()
      )

    assert result["isError"] == false
    assert result["structuredContent"]["ok"] == true
  end

  test "call_tool preview_intent returns error without socket option" do
    result =
      WebMCP.call_tool(
        "preview_intent",
        %{"intent" => %{"intent_version" => 1, "mode" => "replace", "view_mode" => "detail"}},
        selecto(),
        views()
      )

    assert result["isError"] == true
  end

  defp views do
    [
      {:detail, SelectoComponents.Views.Detail, "Detail", %{}},
      {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", %{}},
      {:graph, SelectoComponents.Views.Graph, "Graph", %{}}
    ]
  end

  defp selecto do
    domain = %{
      name: "OrdersReporting",
      description: "Order reporting domain",
      source: %{
        source_table: "orders",
        primary_key: :id,
        fields: [:id, :status, :revenue, :created_at],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          status: %{type: :string, name: "Status", colid: :status, make_filter: true},
          revenue: %{type: :decimal, name: "Revenue", colid: :revenue},
          created_at: %{
            type: :utc_datetime,
            name: "Created At",
            colid: :created_at,
            make_filter: true
          }
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{},
      filters: %{
        "status" => %{id: "status", name: "Status", type: :string, comps: ["=", "!=", "IN"]},
        "created_at" => %{
          id: "created_at",
          name: "Created At",
          type: :utc_datetime,
          comps: [">=", "<=", "SHORTCUT"]
        }
      }
    }

    Selecto.configure(domain, nil, validate: false)
  end
end
