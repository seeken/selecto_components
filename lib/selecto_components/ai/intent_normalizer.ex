defmodule SelectoComponents.AI.IntentNormalizer do
  @moduledoc """
  Normalizes AI intent payloads into a stable internal shape.

  This first slice focuses on inserting defaults and normalizing a few common
  shape differences without assigning UUIDs or converting to Selecto params yet.
  """

  @default_intent_version 1
  @default_mode "replace"
  @default_view_mode "detail"
  @default_chart_type "bar"

  @spec normalize(map()) :: map()
  def normalize(intent) when is_map(intent) do
    intent
    |> normalize_top_level()
    |> normalize_filters()
    |> normalize_selected()
    |> normalize_order_by()
    |> normalize_group_by()
    |> normalize_aggregate()
    |> normalize_graph()
    |> normalize_options()
  end

  def normalize(_intent), do: normalize(%{})

  defp normalize_top_level(intent) do
    %{
      "intent_version" =>
        Map.get(
          intent,
          "intent_version",
          Map.get(intent, :intent_version, @default_intent_version)
        ),
      "domain_id" => Map.get(intent, "domain_id", Map.get(intent, :domain_id)),
      "mode" =>
        to_string_or_default(Map.get(intent, "mode", Map.get(intent, :mode)), @default_mode),
      "view_mode" =>
        to_string_or_default(
          Map.get(intent, "view_mode", Map.get(intent, :view_mode)),
          @default_view_mode
        ),
      "filters" => get_list(intent, "filters"),
      "selected" => get_list(intent, "selected"),
      "order_by" => get_list(intent, "order_by"),
      "group_by" => get_list(intent, "group_by"),
      "aggregate" => get_list(intent, "aggregate"),
      "graph" => get_map(intent, "graph"),
      "options" => get_map(intent, "options"),
      "exports" => get_map(intent, "exports"),
      "explanation" => Map.get(intent, "explanation", Map.get(intent, :explanation)),
      "warnings" => get_list(intent, "warnings")
    }
    |> reject_nil_values(["domain_id", "explanation"])
  end

  defp normalize_filters(intent) do
    Map.update!(intent, "filters", fn filters ->
      Enum.map(filters, fn item ->
        item = stringify_keys(item)

        %{
          "field" => Map.get(item, "field"),
          "comp" => normalize_comparator(Map.get(item, "comp")),
          "value" => Map.get(item, "value"),
          "label" => Map.get(item, "label"),
          "format" => Map.get(item, "format"),
          "notes" => Map.get(item, "notes")
        }
        |> reject_nil_values(["label", "format", "notes", "value"])
      end)
    end)
  end

  defp normalize_selected(intent) do
    Map.update!(intent, "selected", fn items ->
      Enum.map(items, &normalize_field_item/1)
    end)
  end

  defp normalize_group_by(intent) do
    Map.update!(intent, "group_by", fn items ->
      Enum.map(items, &normalize_field_item/1)
    end)
  end

  defp normalize_aggregate(intent) do
    Map.update!(intent, "aggregate", fn items ->
      Enum.map(items, fn item ->
        item = stringify_keys(item)

        %{
          "field" => Map.get(item, "field"),
          "alias" => Map.get(item, "alias"),
          "format" => to_string_or_default(Map.get(item, "format"), "count")
        }
        |> reject_nil_values(["alias"])
      end)
    end)
  end

  defp normalize_order_by(intent) do
    Map.update!(intent, "order_by", fn items ->
      Enum.map(items, fn item ->
        item = stringify_keys(item)

        %{
          "field" => Map.get(item, "field"),
          "dir" => to_string_or_default(Map.get(item, "dir"), "asc")
        }
      end)
    end)
  end

  defp normalize_graph(intent) do
    graph = Map.get(intent, "graph", %{}) |> stringify_keys()

    normalized = %{
      "chart_type" => to_string_or_default(Map.get(graph, "chart_type"), @default_chart_type),
      "x_axis" => Enum.map(get_list(graph, "x_axis"), &normalize_field_item/1),
      "y_axis" => Enum.map(get_list(graph, "y_axis"), &normalize_graph_metric_item/1),
      "series" => Enum.map(get_list(graph, "series"), &normalize_field_item/1),
      "options" => get_map(graph, "options")
    }

    Map.put(intent, "graph", normalized)
  end

  defp normalize_options(intent) do
    Map.update!(intent, "options", &stringify_keys/1)
  end

  defp normalize_field_item(item) do
    item = stringify_keys(item)

    %{
      "field" => Map.get(item, "field"),
      "alias" => Map.get(item, "alias"),
      "format" => to_string_or_default(Map.get(item, "format"), "default")
    }
    |> reject_nil_values(["alias"])
  end

  defp normalize_graph_metric_item(item) do
    item = stringify_keys(item)

    %{
      "field" => Map.get(item, "field"),
      "alias" => Map.get(item, "alias"),
      "function" =>
        to_string_or_default(
          Map.get(item, "function", Map.get(item, "format")),
          "count"
        )
    }
    |> reject_nil_values(["alias"])
  end

  defp normalize_comparator(nil), do: nil
  defp normalize_comparator(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_comparator(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_comparator(value), do: to_string(value)

  defp get_list(map, key) when is_map(map) do
    case Map.get(map, key, Map.get(map, String.to_atom(key), [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_list(_map, _key), do: []

  defp get_map(map, key) when is_map(map) do
    case Map.get(map, key, Map.get(map, String.to_atom(key), %{})) do
      value when is_map(value) -> stringify_keys(value)
      _ -> %{}
    end
  end

  defp get_map(_map, _key), do: %{}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_keys(_), do: %{}

  defp to_string_or_default(nil, default), do: default
  defp to_string_or_default(value, _default) when is_binary(value), do: value
  defp to_string_or_default(value, _default) when is_atom(value), do: Atom.to_string(value)
  defp to_string_or_default(value, _default), do: to_string(value)

  defp reject_nil_values(map, optional_keys) do
    map
    |> Enum.reject(fn {key, value} -> key in optional_keys and is_nil(value) end)
    |> Map.new()
  end
end
