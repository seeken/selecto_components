defmodule SelectoComponents.AI.IntentApplierTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.IntentApplier

  test "to_params builds detail params with generated ids and indexes" do
    params =
      IntentApplier.to_params(%{
        "intent_version" => 1,
        "mode" => "replace",
        "view_mode" => "detail",
        "filters" => [%{"field" => "status", "comp" => "eq", "value" => "open"}],
        "selected" => [%{"field" => "status"}],
        "order_by" => [%{"field" => "created_at", "dir" => "desc"}],
        "options" => %{"detail_per_page" => 60, "prevent_denormalization" => true}
      })

    assert params["view_mode"] == "detail"
    assert %{"ai-filter-0" => filter} = params["filters"]
    assert filter["comp"] == "="
    assert filter["index"] == "0"
    assert %{"ai-field-0" => selected} = params["selected"]
    assert selected["format"] == "default"
    assert params["per_page"] == "60"
    assert params["prevent_denormalization"] == "true"
  end

  test "to_params builds aggregate grid params" do
    params =
      IntentApplier.to_params(%{
        "intent_version" => 1,
        "mode" => "replace",
        "view_mode" => "aggregate",
        "group_by" => [%{"field" => "status"}, %{"field" => "created_at", "format" => "YYYY-Q"}],
        "aggregate" => [%{"field" => "revenue", "format" => "sum"}],
        "options" => %{"aggregate_grid" => true, "aggregate_grid_color_scale" => "log"}
      })

    assert params["aggregate_grid"] == "true"
    assert params["aggregate_grid_color_scale"] == "log"
    assert map_size(params["group_by"]) == 2
  end

  test "to_params builds graph params from normalized graph intent" do
    params =
      IntentApplier.to_params(%{
        "intent_version" => 1,
        "mode" => "draft",
        "view_mode" => "graph",
        "graph" => %{
          "chart_type" => "line",
          "x_axis" => [%{"field" => "created_at"}],
          "y_axis" => [%{"field" => "revenue", "function" => "sum"}],
          "series" => [%{"field" => "status"}],
          "options" => %{"title" => "Revenue"}
        }
      })

    assert params["chart_type"] == "line"
    assert %{"ai-graph-metric-0" => y_axis} = params["y_axis"]
    assert y_axis["function"] == "sum"
    assert params["options"] == %{"title" => "Revenue"}
  end

  test "apply returns params and derived view_config through existing codec path" do
    result =
      IntentApplier.apply(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "selected" => [%{"field" => "status"}]
        },
        socket()
      )

    assert result.mode == "replace"
    assert result.params["view_mode"] == "detail"
    assert result.view_config.view_mode == "detail"
    assert is_map(result.view_config.views)
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selecto: selecto(),
        views: [
          {:detail, SelectoComponents.Views.Detail, "Detail", %{}},
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", %{}},
          {:graph, SelectoComponents.Views.Graph, "Graph", %{}}
        ],
        view_config: %{view_mode: "detail", filters: [], views: %{}},
        presentation_context: %{}
      }
    }
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
