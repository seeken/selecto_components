defmodule SelectoComponents.Views.Aggregate.GridSafetyTest do
  use ExUnit.Case, async: true
  alias SelectoComponents.Views.Aggregate.GridSafety

  test "grid limits are finite even when pagination allows all rows" do
    assert GridSafety.limit(:infinity) == 10_000
    assert GridSafety.limit(100_001) == 10_000
    assert GridSafety.limit(100) == 100
    assert GridSafety.validate_rows(Enum.to_list(1..100), 100) == :ok
    assert GridSafety.validate_rows(Enum.to_list(1..101), 100) == {:error, :grid_limit_exceeded}
  end

  test "sparse input cannot expand into an unbounded dense matrix" do
    assert GridSafety.validate_matrix(10, 10, 100) == :ok
    assert GridSafety.validate_matrix(11, 10, 100) == {:error, :grid_limit_exceeded}
    assert GridSafety.validate_matrix(0, 1000, 100) == :ok
  end
end
