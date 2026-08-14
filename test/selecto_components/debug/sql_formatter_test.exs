defmodule SelectoComponents.Debug.SqlFormatterTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Debug.SqlFormatter

  test "preserves adapter-rendered SQL instead of interpreting its dialect" do
    sql = "  select * from records where first_id = $1 and second_id = @p2 and third_id = ?  "

    assert SqlFormatter.format(sql) ==
             "select * from records where first_id = $1 and second_id = @p2 and third_id = ?"
  end

  test "normalizes non-binary debug values without adding SQL syntax" do
    assert SqlFormatter.format(:unavailable) == "unavailable"
  end
end
