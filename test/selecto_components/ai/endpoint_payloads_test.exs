defmodule SelectoComponents.AI.EndpointPayloadsTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.EndpointPayloads

  test "query_contract returns json-ready payload" do
    payload = EndpointPayloads.query_contract(selecto(), views(), path: "/reports/orders")

    assert payload.content_type == "application/json"
    assert payload.filename == "selecto_orders_reporting_query_contract.json"
    assert is_binary(payload.body)
    assert payload.body =~ "query_contract_version"
    assert payload.data["domain"]["id"] == "OrdersReporting"
  end

  test "query_guide returns markdown-ready payload" do
    payload = EndpointPayloads.query_guide(selecto(), views(), path: "/reports/orders")

    assert payload.content_type == "text/markdown; charset=utf-8"
    assert payload.filename == "selecto_orders_reporting_query_guide.md"
    assert is_binary(payload.body)
    assert payload.body =~ "# Selecto Query Guide"
    assert is_map(payload.data["contract"])
  end

  test "query_guide supports plain text mode" do
    payload = EndpointPayloads.query_guide(selecto(), views(), format: :text)

    assert payload.content_type == "text/plain; charset=utf-8"
    assert payload.filename == "selecto_orders_reporting_query_guide.txt"
  end

  test "link helpers build canonical URLs when given base url and path" do
    assert EndpointPayloads.query_guide_link("https://example.test/", selecto(),
             guide_path: "/selecto/docs/query-guide/orders"
           ) ==
             "https://example.test/selecto/docs/query-guide/orders"

    assert EndpointPayloads.query_contract_link("https://example.test", selecto(),
             contract_path: "selecto/schema/orders/query-contract.json"
           ) ==
             "https://example.test/selecto/schema/orders/query-contract.json"
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
