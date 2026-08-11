defmodule SelectoComponents.Views.Graph.EncodingTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Views.Graph.Encoding

  test "auto chooses line for a temporal X group and bar for a categorical X group" do
    aggregate = {:field, {:sum, "hours"}, "Hours"}
    metric = [{"a1", "hours", %{"format" => "sum"}}]

    temporal =
      Encoding.apply(
        %{
          groups: [{%{type: :utc_datetime}, {:field, "booked_at", "Booked"}}],
          aggregates: [aggregate]
        },
        state([{"g1", "booked_at", %{}}], metric),
        %{"hours" => %{type: :integer}}
      )

    categorical =
      Encoding.apply(
        %{
          groups: [{%{type: :string}, {:field, "category", "Category"}}],
          aggregates: [aggregate]
        },
        state([{"g1", "category", %{}}], metric),
        %{"hours" => %{type: :integer}}
      )

    assert temporal.chart_type == "line"
    assert categorical.chart_type == "bar"
  end

  test "different canonical units use separate axes unless explicitly overridden" do
    view_set = %{
      groups: [{%{type: :string}, {:field, "category", "Category"}}],
      aggregates: [
        {:field, {:sum, "hours"}, "Hours"},
        {:field, {:sum, "cost"}, "Cost"}
      ]
    }

    items = [
      {"a1", "hours", %{"format" => "sum"}},
      {"a2", "cost", %{"format" => "sum"}}
    ]

    columns = %{
      "hours" => %{presentation: %{canonical_unit: :hour}},
      "cost" => %{presentation: %{canonical_unit: :usd}}
    }

    encoded = Encoding.apply(view_set, state([{"g1", "category", %{}}], items), columns)
    assert Enum.map(encoded.graph_series_defs, & &1.axis) == ["left", "right"]

    overridden_state =
      state([{"g1", "category", %{}}], items, %{
        measure_overrides: %{"a2" => %{"axis" => "left"}}
      })

    overridden = Encoding.apply(view_set, overridden_state, columns)
    assert Enum.map(overridden.graph_series_defs, & &1.axis) == ["left", "left"]
  end

  test "scatter requires two aggregate measures" do
    encoded =
      Encoding.apply(
        %{
          groups: [{%{type: :string}, {:field, "category", "Category"}}],
          aggregates: [{:field, {:sum, "hours"}, "Hours"}]
        },
        state([{"g1", "category", %{}}], [{"a1", "hours", %{"format" => "sum"}}], %{
          type: "scatter"
        }),
        %{"hours" => %{type: :integer}}
      )

    assert encoded.chart_type == "bar"
  end

  defp state(groups, aggregates, visual_overrides \\ %{}) do
    %{
      group_by: groups,
      aggregate: aggregates,
      visual:
        Map.merge(
          %{
            type: "auto",
            x: nil,
            series: [],
            stack: "auto",
            measure_overrides: %{},
            options: %{}
          },
          visual_overrides
        )
    }
  end
end
