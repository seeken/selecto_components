defmodule SelectoComponents.Views.Document.Template do
  @moduledoc false

  alias SelectoComponents.Components.NestedTable

  def normalize(%{"blocks" => blocks}), do: %{"blocks" => normalize_blocks(blocks)}
  def normalize(%{blocks: blocks}), do: %{"blocks" => normalize_blocks(blocks)}
  def normalize(_), do: %{"blocks" => []}

  def blocks(template) do
    template
    |> normalize()
    |> Map.get("blocks", [])
    |> Enum.filter(&is_map/1)
  end

  def block_type(block), do: string_value(block, "type")

  def block_text(block) do
    block
    |> string_value("text")
    |> default_empty()
  end

  def block_title(block, fallback \\ "") do
    case string_value(block, "title") do
      nil -> fallback
      title when is_binary(title) -> title
    end
  end

  def block_fields(block) do
    case map_value(block, "fields") do
      fields when is_list(fields) -> Enum.filter(fields, &is_binary/1)
      fields when is_binary(fields) ->
        fields
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ -> []
    end
  end

  def block_table(block) do
    block
    |> string_value("table")
    |> default_empty()
  end

  def interpolate(text, row) when is_binary(text) and is_map(row) do
    Regex.replace(~r/{{\s*([^}]+?)\s*}}/, text, fn _match, field_name ->
      row
      |> row_value(field_name)
      |> printable_value()
    end)
  end

  def interpolate(text, _row) when is_binary(text), do: text
  def interpolate(_text, _row), do: ""

  def row_value(row, field_name) when is_map(row) and is_binary(field_name) do
    Map.get(row, field_name, Map.get(row, safe_existing_atom(field_name)))
  end

  def row_value(_row, _field_name), do: nil

  def subtable_rows(row, table_name, config \\ %{})

  def subtable_rows(row, table_name, config)
      when is_map(row) and is_binary(table_name) and is_map(config) do
    table_data = row_value(row, table_name)
    NestedTable.parse_subselect_data(table_data, config)
  end

  def subtable_rows(_row, _table_name, _config), do: []

  def printable_value(nil), do: ""
  def printable_value(value) when is_binary(value), do: value
  def printable_value(value) when is_number(value), do: to_string(value)
  def printable_value(value) when is_boolean(value), do: to_string(value)
  def printable_value(value), do: inspect(value)

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, safe_existing_atom(key)))
  end

  defp map_value(_map, _key), do: nil

  defp string_value(map, key) do
    case map_value(map, key) do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      _ -> nil
    end
  end

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp safe_existing_atom(_value), do: nil

  defp default_empty(nil), do: ""
  defp default_empty(value), do: value

  defp normalize_blocks(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&normalize_block/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_blocks(blocks) when is_map(blocks) do
    blocks
    |> Enum.sort_by(fn {k, _v} ->
      case Integer.parse(to_string(k)) do
        {index, ""} -> index
        _ -> 0
      end
    end)
    |> Enum.map(fn {_k, block} -> normalize_block(block) end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_blocks(_blocks), do: []

  defp normalize_block(block) when is_map(block) do
    block
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp normalize_block(_block), do: nil
end
