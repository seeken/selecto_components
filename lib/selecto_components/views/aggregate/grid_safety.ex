defmodule SelectoComponents.Views.Aggregate.GridSafety do
  @moduledoc "Bounds aggregate grid materialization independently of pagination."

  @default 10_000
  def limit(value) when is_integer(value) and value >= 100 and value <= 100_000, do: value
  def limit(_value), do: @default

  def configured_limit(value \\ nil),
    do: limit(value || Application.get_env(:selecto_components, :max_grid_result_cells, @default))

  def validate_rows(rows, maximum) when is_list(rows) do
    if length(rows) <= limit(maximum), do: :ok, else: {:error, :grid_limit_exceeded}
  end

  def validate_matrix(row_count, column_count, maximum)
      when is_integer(row_count) and row_count >= 0 and is_integer(column_count) and
             column_count >= 0 do
    if row_count * column_count <= limit(maximum),
      do: :ok,
      else: {:error, :grid_limit_exceeded}
  end
end
