defmodule SelectoComponents.AI.QueryGuideTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.QueryContract
  alias SelectoComponents.AI.QueryGuide

  test "render builds ai-readable guide from query contract" do
    guide = QueryGuide.render(contract())

    assert guide =~ "# Selecto Query Guide"
    assert guide =~ "## Domain"
    assert guide =~ "OrdersReporting"
    assert guide =~ "## Fields"
    assert guide =~ "`status`"
    assert guide =~ "OrdersReporting: Status"
    assert guide =~ "Comparators"
    assert guide =~ "## Capabilities"
    assert guide =~ "Aggregate grid"
    assert guide =~ "## Examples"
    assert guide =~ "detail_single_field"
    assert guide =~ "## Errors"
    assert guide =~ "unknown_field"
  end

  defp contract do
    QueryContract.generate(selecto(), views(), path: "/reports/orders")
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
