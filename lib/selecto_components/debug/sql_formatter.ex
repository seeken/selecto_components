defmodule SelectoComponents.Debug.SqlFormatter do
  @moduledoc """
  Adapter-neutral SQL preparation for debug displays.

  Selecto Components does not parse or rewrite generated SQL because placeholder,
  cast, operator, and function syntax belongs to the configured adapter. The
  formatter therefore preserves adapter output verbatim apart from trimming
  surrounding whitespace.
  """

  @spec format(String.t()) :: String.t()
  def format(sql) when is_binary(sql), do: String.trim(sql)
  def format(sql), do: sql |> to_string() |> String.trim()
end
