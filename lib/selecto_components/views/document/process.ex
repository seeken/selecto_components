defmodule SelectoComponents.Views.Document.Process do
  @moduledoc false

  alias SelectoComponents.SubselectBuilder
  alias SelectoComponents.Views.Document.Options
  alias SelectoComponents.Views.Document.Template

  def param_to_state(params, _view) do
    %{
      selected: SelectoComponents.Views.view_param_process(params, "document_selected", "field"),
      subtable_fields:
        SelectoComponents.Views.view_param_process(params, "document_subtable_fields", "field"),
      template: normalize_template(Map.get(params, "document_template")),
      per_page: Options.normalize_per_page_param(Map.get(params, "document_per_page")),
      max_rows: Options.normalize_max_rows_param(Map.get(params, "document_max_rows"))
    }
  end

  def initial_state(selecto, _view) do
    domain = Selecto.domain(selecto)

    %{
      selected:
        Map.get(domain, :default_document_selected, [])
        |> SelectoComponents.Helpers.build_initial_state(),
      subtable_fields:
        Map.get(domain, :default_document_subtable_fields, [])
        |> SelectoComponents.Helpers.build_initial_state(),
      template: Map.get(domain, :default_document_template, %{"blocks" => []}),
      per_page: Options.default_per_page(),
      max_rows: Options.default_max_rows()
    }
  end

  def view(_opt, params, columns, filtered, _selecto) do
    root_columns =
      params
      |> Map.get("document_selected", %{})
      |> ordered_items()

    subtable_columns =
      params
      |> Map.get("document_subtable_fields", %{})
      |> ordered_items()

    denorm_groups =
      subtable_columns
      |> Enum.map(&Map.get(&1, "field"))
      |> Enum.filter(&is_binary/1)
      |> Enum.reduce(%{}, fn field_name, acc ->
        case relationship_path(field_name) do
          nil -> acc
          relationship -> Map.update(acc, relationship, [field_name], &(&1 ++ [field_name]))
        end
      end)
      |> Enum.into(%{}, fn {relationship, fields} -> {relationship, Enum.uniq(fields)} end)

    subselect_configs =
      Enum.map(denorm_groups, fn {path, field_list} ->
        config = SubselectBuilder.generate_nested_config(path, field_list)

        Map.put(
          config,
          :columns,
          Enum.map(field_list, fn field ->
            {UUID.uuid4(), field, %{}}
          end)
        )
      end)

    per_page = Options.per_page_to_int(Map.get(params, "document_per_page"), 30)
    max_rows = Options.normalize_max_rows_param(Map.get(params, "document_max_rows"))

    view_set = %{
      columns: root_columns,
      selected: build_selected_fields(root_columns, columns),
      order_by: [],
      filtered: filtered,
      group_by: [],
      groups: [],
      subselects: subselect_configs,
      denorm_groups: denorm_groups,
      denormalizing_columns: subtable_columns
    }

    {view_set,
     %{
       page: parse_page_param(Map.get(params, "detail_page", "0")),
       per_page: per_page,
       max_rows: max_rows,
       template: normalize_template(Map.get(params, "document_template")),
       subselect_configs: subselect_configs
     }}
  end

  defp normalize_template(template), do: Template.normalize(template)

  defp ordered_items(items) when is_map(items) do
    items
    |> Map.values()
    |> Enum.filter(&is_map/1)
    |> Enum.sort(fn a, b ->
      item_index(a) <= item_index(b)
    end)
  end

  defp ordered_items(_items), do: []

  defp item_index(item) do
    case Integer.parse(to_string(Map.get(item, "index", "0"))) do
      {index, ""} -> index
      _ -> 0
    end
  end

  defp relationship_path(field_name) when is_binary(field_name) do
    cond do
      String.contains?(field_name, ".") ->
        field_name
        |> String.split(".")
        |> Enum.drop(-1)
        |> Enum.join(".")
        |> blank_to_nil()

      String.contains?(field_name, "[") ->
        case Regex.run(~r/^([^[]+)\[/, field_name, capture: :all_but_first) do
          [relationship] -> blank_to_nil(String.trim(relationship))
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp relationship_path(_field_name), do: nil

  defp build_selected_fields(root_columns, columns_map) do
    date_formats = SelectoComponents.Helpers.date_formats()

    root_columns
    |> Enum.map(fn item ->
      field_name = Map.get(item, "field")
      col = columns_map[field_name]

      alias_name =
        case Map.get(item, "alias") do
          nil -> field_name
          "" -> field_name
          custom_alias -> custom_alias
        end

      case col do
        %{type: type} = coldef when type in [:naive_datetime, :utc_datetime] ->
          format = Map.get(item, "format", "YYYY-MM-DD")
          {:field, {:to_char, {coldef.colid, date_formats[format]}}, alias_name}

        %{type: :custom_column} = coldef ->
          case Map.get(coldef, :requires_select) do
            requires when is_list(requires) -> {:row, requires, alias_name}
            requires when is_function(requires) -> {:row, requires.(item), alias_name}
            _ -> {:field, coldef.colid, alias_name}
          end

        %{colid: colid} ->
          {:field, colid, alias_name}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_page_param(value) when is_integer(value) and value >= 0, do: value

  defp parse_page_param(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> 0
    end
  end

  defp parse_page_param(_value), do: 0

  defp blank_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp blank_to_nil(_value), do: nil
end
