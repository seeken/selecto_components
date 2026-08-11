defmodule SelectoComponents.Views.Graph.FormTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Views.Graph.Form

  test "renders Aggregate query controls with graph-scoped form parameters" do
    html =
      render_graph(%{
        group_by: [{"g1", "category", %{"format" => "default"}}],
        aggregate: [{"a1", "amount", %{"format" => "sum"}}],
        visual: visual(%{type: "auto", x: "g1"})
      })

    assert html =~ "Aggregate query, graph projection"
    assert html =~ "same controls and query semantics as Aggregate View"
    assert html =~ ~s(name="graph_group_by[g1][field]")
    assert html =~ ~s(name="graph_aggregate[a1][field]")
    assert html =~ ~s(name="graph_chart_type")
    assert html =~ ~s(name="graph_x")
    refute html =~ ~s(name="x_axis[)
    refute html =~ ~s(name="y_axis[)
  end

  test "normalizes legacy graph state at the form boundary" do
    html =
      render_graph(%{
        x_axis: [{"x1", "booked_at", %{"format" => "month"}}],
        y_axis: [{"y1", "amount", %{"function" => "sum", "axis" => "right"}}],
        series: [{"s1", "category", %{}}],
        chart_type: "line",
        options: %{"title" => "Monthly revenue"}
      })

    assert html =~ ~s(name="graph_group_by[x1][field]")
    assert html =~ ~s(name="graph_group_by[s1][field]")
    assert html =~ ~s(name="graph_aggregate[y1][field]")
    assert html =~ "Monthly revenue"
    assert html =~ ~s(value="line" selected)
    assert html =~ ~s(name="graph_measure_overrides[y1][axis]")
  end

  test "offers automatic visual defaults and explicit measure overrides" do
    html =
      render_graph(%{
        group_by: [
          {"g1", "booked_at", %{"format" => "month"}},
          {"g2", "category", %{}}
        ],
        aggregate: [{"a1", "amount", %{"format" => "sum"}}],
        visual:
          visual(%{
            type: "auto",
            series: ["g2"],
            stack: "stacked",
            measure_overrides: %{
              "a1" => %{"mark" => "line", "axis" => "right", "color" => "#ff0000"}
            }
          })
      })

    assert html =~ "Auto (first Group By)"
    assert html =~ ~s(name="graph_series[]")
    assert html =~ ~s(value="g2" checked)
    assert html =~ ~s(value="stacked" selected)
    assert html =~ ~s(value="right" selected)
    assert html =~ "#ff0000"
  end

  defp render_graph(graph_state) do
    selecto = selecto()

    render_component(Form, %{
      id: "graph-form-test",
      columns: SelectoComponents.Form.ColumnCatalog.picker_columns(selecto),
      view: {:graph, SelectoComponents.Views.Graph, "Graph View", %{}},
      selecto: selecto,
      view_config: %{views: %{graph: graph_state}}
    })
  end

  defp selecto do
    Selecto.configure(
      %{
        name: "GraphFormTest",
        source: %{
          source_table: "bookings",
          primary_key: :id,
          fields: [:id, :category, :booked_at, :amount],
          redact_fields: [],
          columns: %{
            id: %{type: :integer},
            category: %{type: :string},
            booked_at: %{type: :utc_datetime},
            amount: %{type: :decimal}
          },
          associations: %{}
        },
        schemas: %{},
        joins: %{}
      },
      nil
    )
  end

  defp visual(overrides) do
    Map.merge(
      %{
        type: "auto",
        x: nil,
        series: [],
        stack: "auto",
        measure_overrides: %{},
        options: %{}
      },
      overrides
    )
  end
end
