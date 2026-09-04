defmodule SelectoComponents.Views.Aggregate.GridExecutionTest do
  use ExUnit.Case, async: true

  defmodule Adapter do
    def connect(pid), do: {:ok, pid}
    def placeholder(_), do: "?"
    def quote_identifier(name), do: ["\"", to_string(name), "\""]
    def supports?(_), do: false

    def execute(pid, sql, _params, _opts) do
      send(pid, {:grid_sql, sql})
      {:ok, %{rows: Enum.map(1..101, &[&1]), columns: ["id"]}}
    end
  end

  test "the database query is bounded and sentinel results never render as a complete grid" do
    domain = %{
      name: "Grid",
      source: %{
        source_table: "rows",
        primary_key: :id,
        fields: [:id],
        columns: %{id: %{type: :integer}},
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }

    query =
      domain
      |> Selecto.configure(self(), adapter: Adapter, validate: false)
      |> Selecto.select(["id"])

    {result, _, _} =
      SelectoComponents.Execution.QueryHelpers.execute_query_with_pagination(
        query,
        %{"view_mode" => "aggregate", "aggregate_grid" => "true"},
        %{per_page: "all", max_grid_result_cells: 100},
        %{assigns: %{}}
      )

    assert {:error, %Selecto.Error{}} = result
    assert_receive {:grid_sql, sql}
    assert IO.iodata_to_binary(sql) =~ ~r/limit\s+101/i
  end

  test "a validated grid is never silently truncated by the ordinary aggregate display cap" do
    rows = Enum.map(1..101, &[&1])

    {returned, meta} =
      SelectoComponents.Execution.QueryHelpers.maybe_cap_aggregate_rows(
        rows,
        %{aggregate_max_client_rows: 100},
        %{"view_mode" => "aggregate", "aggregate_grid" => "true"}
      )

    assert returned == rows
    refute meta.aggregate_rows_capped?
  end
end
