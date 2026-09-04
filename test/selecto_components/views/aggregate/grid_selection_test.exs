defmodule SelectoComponents.Views.Aggregate.GridSelectionTest do
  use ExUnit.Case, async: true
  alias SelectoComponents.Views.Aggregate.GridSelection

  @secret String.duplicate("test-only-grid-key-", 4)

  test "tokens bind governed axis values to one execution and axis" do
    row =
      GridSelection.token(@secret, "run-1", :row, %{
        "phx-value-field0" => "region",
        "phx-value-value0" => "north"
      })

    col =
      GridSelection.token(@secret, "run-1", :column, %{
        "phx-value-field1" => "state",
        "phx-value-value1" => "open"
      })

    assert {:ok, [params]} = GridSelection.verify(@secret, "run-1", [[row, col]])

    assert params == %{
             "field0" => "region",
             "value0" => "north",
             "field1" => "state",
             "value1" => "open"
           }

    assert {:ok, [_]} = GridSelection.verify(@secret, "run-1", [[row]])

    for alternatives <- [
          [[row, row]],
          [[row <> "tamper"]],
          List.duplicate([row], 51),
          [],
          [[row, col, row]]
        ] do
      assert {:error, _} = GridSelection.verify(@secret, "run-1", alternatives)
    end

    assert {:error, _} = GridSelection.verify(@secret, "run-2", [[row]])
  end

  test "paired selections become editable AND branches under OR without replacing prior filters" do
    domain = %{
      name: "Grid",
      source: %{
        source_table: "rows",
        primary_key: :id,
        fields: [:id, :region, :state, :tenant],
        associations: %{},
        columns: %{
          id: %{type: :integer},
          region: %{type: :string},
          state: %{type: :string},
          tenant: %{type: :string}
        }
      },
      schemas: %{},
      joins: %{}
    }

    selecto = Selecto.configure(domain, nil)
    prior = {"tenant", "filters", %{"filter" => "tenant", "comp" => "=", "value" => "a"}}
    socket = %{assigns: %{selecto: selecto, view_config: %{filters: [prior]}, used_params: %{}}}

    alternatives = [
      %{"field0" => "region", "value0" => "north", "field1" => "state", "value1" => "open"},
      %{"field0" => "region", "value0" => "south", "field1" => "state", "value1" => "closed"}
    ]

    [^prior, {union, "filters", "OR"} | rest] =
      GridSelection.build_filters([prior], alternatives, socket)

    assert Enum.count(rest, fn {_, section, value} -> section == union and value == "AND" end) ==
             2

    branches =
      Enum.filter(rest, fn {_, _, config} -> is_map(config) end) |> Enum.group_by(&elem(&1, 1))

    assert Enum.sort(
             Enum.map(branches, fn {_, children} ->
               Enum.sort(Enum.map(children, &elem(&1, 2)["value"]))
             end)
           ) == [["closed", "south"], ["north", "open"]]

    for literal <- ["[NULL]", "__NULL__"] do
      filters =
        GridSelection.build_filters(
          [],
          [
            %{
              "field0" => "region",
              "value0" => literal,
              "literal0" => "true"
            }
          ],
          socket
        )

      assert Enum.any?(filters, fn
               {_, _, %{"comp" => "=", "value" => ^literal}} -> true
               _ -> false
             end)
    end

    null_filters =
      GridSelection.build_filters(
        [],
        [
          %{
            "field0" => "region",
            "value0" => "__NULL__"
          }
        ],
        socket
      )

    assert Enum.any?(null_filters, fn
             {_, _, %{"comp" => "IS_EMPTY"}} -> true
             _ -> false
           end)
  end
end
