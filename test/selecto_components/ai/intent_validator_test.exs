defmodule SelectoComponents.AI.IntentValidatorTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.IntentValidator
  alias SelectoComponents.AI.QueryContract

  test "validates minimal detail intent successfully" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "filters" => [],
          "selected" => [%{"field" => "status"}]
        },
        contract()
      )

    assert result.ok == true
    assert result.errors == []
  end

  test "returns path-based error for unknown field" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "selected" => [%{"field" => "quarter_name"}]
        },
        contract()
      )

    assert result.ok == false
    assert %{"code" => "unknown_field", "path" => ["selected", 0, "field"]} = hd(result.errors)
  end

  test "rejects invalid comparator for a field" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "filters" => [%{"field" => "status", "comp" => "gt", "value" => "open"}]
        },
        contract()
      )

    assert result.ok == false

    assert Enum.any?(
             result.errors,
             &(&1["code"] == "invalid_comparator" and &1["path"] == ["filters", 0, "comp"])
           )
  end

  test "rejects invalid aggregate function" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "aggregate",
          "group_by" => [%{"field" => "status"}],
          "aggregate" => [%{"field" => "status", "format" => "sum"}]
        },
        contract()
      )

    assert result.ok == false

    assert Enum.any?(
             result.errors,
             &(&1["code"] == "invalid_aggregate_function" and
                 &1["path"] == ["aggregate", 0, "format"])
           )
  end

  test "rejects invalid aggregate grid shape" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "aggregate",
          "group_by" => [%{"field" => "status"}],
          "aggregate" => [%{"field" => "revenue", "format" => "sum"}],
          "options" => %{"aggregate_grid" => true}
        },
        contract()
      )

    assert result.ok == false
    assert Enum.any?(result.errors, &(&1["code"] == "invalid_aggregate_grid_shape"))
  end

  test "rejects invalid graph chart type" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "draft",
          "view_mode" => "graph",
          "graph" => %{
            "chart_type" => "radar",
            "x_axis" => [%{"field" => "created_at"}],
            "y_axis" => [%{"field" => "revenue", "function" => "sum"}],
            "series" => []
          }
        },
        contract()
      )

    assert result.ok == false

    assert Enum.any?(
             result.errors,
             &(&1["code"] == "invalid_chart_type" and &1["path"] == ["graph", "chart_type"])
           )
  end

  test "rejects unsupported mode" do
    result =
      IntentValidator.validate(
        %{"intent_version" => 1, "mode" => "patch", "view_mode" => "detail"},
        contract()
      )

    assert result.ok == false

    assert Enum.any?(
             result.errors,
             &(&1["code"] == "unsupported_mode" and &1["path"] == ["mode"])
           )
  end

  test "rejects mismatched domain id" do
    result =
      IntentValidator.validate(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "domain_id" => "OtherDomain"
        },
        contract()
      )

    assert result.ok == false

    assert Enum.any?(
             result.errors,
             &(&1["code"] == "domain_mismatch" and &1["path"] == ["domain_id"])
           )
  end

  defp contract do
    QueryContract.generate(selecto(), views())
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
