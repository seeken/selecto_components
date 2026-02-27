defmodule SelectoComponents.Views.Document.Process do
  @moduledoc false

  def param_to_state(params, _view) do
    %{
      selected: SelectoComponents.Views.view_param_process(params, "document_selected", "field"),
      subtable_fields:
        SelectoComponents.Views.view_param_process(params, "document_subtable_fields", "field"),
      template: normalize_template(Map.get(params, "document_template")),
      per_page: normalize_per_page_param(Map.get(params, "document_per_page")),
      max_rows: normalize_max_rows_param(Map.get(params, "document_max_rows"))
    }
  end

  def initial_state(_selecto, _view) do
    %{
      selected: [],
      subtable_fields: [],
      template: %{blocks: []},
      per_page: "30",
      max_rows: "1000"
    }
  end

  def view(_opt, _params, _columns, filtered, _selecto) do
    view_set = %{
      columns: [],
      selected: [],
      order_by: [],
      filtered: filtered,
      group_by: [],
      groups: [],
      subselects: [],
      denorm_groups: %{}
    }

    {view_set, %{page: 0, per_page: 30, max_rows: "1000", total_rows: 0}}
  end

  defp normalize_template(%{"blocks" => blocks}) when is_list(blocks), do: %{"blocks" => blocks}
  defp normalize_template(%{blocks: blocks}) when is_list(blocks), do: %{blocks: blocks}
  defp normalize_template(_), do: %{"blocks" => []}

  defp normalize_per_page_param(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> Integer.to_string(parsed)
      _ -> "30"
    end
  end

  defp normalize_per_page_param(value) when is_integer(value) and value > 0,
    do: Integer.to_string(value)

  defp normalize_per_page_param(_), do: "30"

  defp normalize_max_rows_param(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      String.downcase(trimmed) == "all" -> "all"
      true ->
        case Integer.parse(trimmed) do
          {parsed, ""} when parsed > 0 -> Integer.to_string(parsed)
          _ -> "1000"
        end
    end
  end

  defp normalize_max_rows_param(value) when is_integer(value) and value > 0,
    do: Integer.to_string(value)

  defp normalize_max_rows_param(_), do: "1000"
end
