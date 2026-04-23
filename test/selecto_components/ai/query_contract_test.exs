defmodule SelectoComponents.AI.QueryContractTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.QueryContract

  test "generate returns top-level query contract shape" do
    contract = QueryContract.generate(selecto(), views(), path: "/reports/orders")

    assert contract["query_contract_version"] == 1
    assert contract["domain"]["id"] == "OrdersReporting"
    assert contract["context"]["view_modes"] == ["detail", "aggregate", "graph"]
    assert is_list(contract["fields"])
    assert is_map(contract["params_schema"])
    assert is_map(contract["capabilities"])
    assert is_map(contract["errors"])
  end

  test "generate includes normalized field capabilities" do
    contract = QueryContract.generate(selecto(), views())

    revenue = Enum.find(contract["fields"], &(&1["id"] == "revenue"))
    status = Enum.find(contract["fields"], &(&1["id"] == "status"))
    created_at = Enum.find(contract["fields"], &(&1["id"] == "created_at"))

    assert revenue["type"] == "decimal"
    assert revenue["aggregatable"] == true
    assert revenue["aggregate_functions"] == ["sum", "avg", "min", "max"]

    assert status["filterable"] == true
    assert "eq" in status["comparators"]
    assert status["graph"]["x_axis"] == true

    assert created_at["type"] == "utc_datetime"
    assert "shortcut" in created_at["comparators"]
    assert created_at["shortcut_values"] == ["today", "yesterday", "this_week", "last_month"]
  end

  test "generate includes aggregate grid and export capabilities" do
    contract = QueryContract.generate(selecto(), views(), exports: ["csv", "xlsx"])

    assert contract["capabilities"]["aggregate_grid"]["enabled"] == true
    assert contract["capabilities"]["aggregate_grid"]["requires_group_by_count"] == 2
    assert contract["capabilities"]["exports"]["formats"] == ["csv", "xlsx"]
  end

  test "generate builds default examples when none are supplied" do
    contract = QueryContract.generate(selecto(), views())

    assert is_list(contract["examples"])
    assert length(contract["examples"]) >= 2

    example_ids = Enum.map(contract["examples"], & &1["id"])
    assert "detail_single_field" in example_ids
    assert "aggregate_metric_by_dimension" in example_ids
  end

  test "generate respects allowed field scoping" do
    contract =
      QueryContract.generate(selecto(), views(), allowed_fields: ["status", "created_at"])

    field_ids = Enum.map(contract["fields"], & &1["id"])

    assert field_ids == ["created_at", "status"]
    refute "revenue" in field_ids
  end

  test "generate respects explicit field visibility overrides" do
    contract =
      QueryContract.generate(
        selecto(),
        views(),
        field_visibility: %{"status" => "advanced", "revenue" => "hidden"}
      )

    status = Enum.find(contract["fields"], &(&1["id"] == "status"))
    revenue = Enum.find(contract["fields"], &(&1["id"] == "revenue"))

    assert status["visibility"] == "advanced"
    assert revenue["visibility"] == "hidden"
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
