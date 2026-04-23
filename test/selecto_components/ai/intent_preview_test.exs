defmodule SelectoComponents.AI.IntentPreviewTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.IntentPreview

  test "build returns structural diff between current and next state" do
    preview =
      IntentPreview.build(
        %{
          "intent_version" => 1,
          "mode" => "draft",
          "view_mode" => "aggregate",
          "group_by" => [%{"field" => "status"}],
          "aggregate" => [%{"field" => "revenue", "format" => "sum"}]
        },
        socket()
      )

    assert preview["mode"] == "draft"
    assert preview["preview"]["current_params"]["view_mode"] == "detail"
    assert preview["preview"]["next_params"]["view_mode"] == "aggregate"
    assert "view_mode" in preview["preview"]["diff"]["changed_sections"]
    assert "aggregate" in preview["preview"]["diff"]["changed_sections"]
    assert preview["preview"]["diff"]["counts"]["aggregate"]["to"] == 1
  end

  test "build preserves current and next view configs" do
    preview =
      IntentPreview.build(
        %{
          "intent_version" => 1,
          "mode" => "replace",
          "view_mode" => "detail",
          "selected" => [%{"field" => "status"}]
        },
        socket()
      )

    assert is_map(preview["preview"]["current_view_config"])
    assert is_map(preview["preview"]["next_view_config"])
    assert preview["preview"]["diff"]["counts"]["selected"]["to"] == 1
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
        view_config: %{
          view_mode: "detail",
          filters: [],
          views: %{
            detail: %{
              selected: [],
              order_by: [],
              per_page: "30",
              max_rows: "1000",
              count_mode: "bounded"
            },
            aggregate: %{
              group_by: [],
              aggregate: [],
              per_page: "100",
              grid: false,
              grid_colorize: false,
              grid_color_scale: "linear"
            },
            graph: %{x_axis: [], y_axis: [], series: [], chart_type: "bar", options: %{}}
          }
        },
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
