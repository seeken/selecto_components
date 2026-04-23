defmodule SelectoComponents.AI.IntentApplier do
  @moduledoc """
  Converts normalized AI intent into Selecto-compatible params and view config.

  This first slice does not mutate the socket directly. It prepares the same
  params/state shapes the existing UI/runtime already understands.
  """

  alias SelectoComponents.AI.IntentNormalizer
  alias SelectoComponents.Session.Codec

  @spec apply(map(), Phoenix.LiveView.Socket.t()) :: map()
  def apply(intent, socket) when is_map(intent) do
    normalized_intent = IntentNormalizer.normalize(intent)
    params = to_params(normalized_intent)
    view_config = Codec.params_to_view_config(params, socket)

    %{
      mode: normalized_intent["mode"],
      intent: normalized_intent,
      params: params,
      view_config: view_config
    }
  end

  @spec to_params(map()) :: map()
  def to_params(intent) when is_map(intent) do
    intent = IntentNormalizer.normalize(intent)
    view_mode = Map.get(intent, "view_mode", "detail")

    %{
      "view_mode" => view_mode,
      "filters" => build_filters(Map.get(intent, "filters", [])),
      "selected" => build_field_items(Map.get(intent, "selected", [])),
      "order_by" => build_order_by_items(Map.get(intent, "order_by", [])),
      "group_by" => build_field_items(Map.get(intent, "group_by", [])),
      "aggregate" => build_aggregate_items(Map.get(intent, "aggregate", []))
    }
    |> merge_graph_params(Map.get(intent, "graph", %{}), view_mode)
    |> merge_option_params(Map.get(intent, "options", %{}), view_mode)
    |> reject_empty_sections()
  end

  def to_params(_intent), do: to_params(%{})

  defp build_filters(filters) do
    filters
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, index} ->
      id = generated_id("filter", index)

      {id,
       %{
         "uuid" => id,
         "filter" => Map.get(item, "field"),
         "comp" => denormalize_comparator(Map.get(item, "comp")),
         "value" => Map.get(item, "value"),
         "section" => "filters",
         "index" => Integer.to_string(index)
       }
       |> reject_nil_values(["value"])}
    end)
  end

  defp build_field_items(items) do
    items
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, index} ->
      id = generated_id("field", index)

      {id,
       %{
         "uuid" => id,
         "field" => Map.get(item, "field"),
         "alias" => Map.get(item, "alias"),
         "format" => Map.get(item, "format", "default"),
         "index" => Integer.to_string(index)
       }
       |> reject_nil_values(["alias"])}
    end)
  end

  defp build_aggregate_items(items) do
    items
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, index} ->
      id = generated_id("aggregate", index)

      {id,
       %{
         "uuid" => id,
         "field" => Map.get(item, "field"),
         "alias" => Map.get(item, "alias"),
         "format" => Map.get(item, "format", "count"),
         "index" => Integer.to_string(index)
       }
       |> reject_nil_values(["alias"])}
    end)
  end

  defp build_order_by_items(items) do
    items
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, index} ->
      id = generated_id("order", index)

      {id,
       %{
         "uuid" => id,
         "field" => Map.get(item, "field"),
         "dir" => Map.get(item, "dir", "asc"),
         "index" => Integer.to_string(index)
       }}
    end)
  end

  defp merge_graph_params(params, graph, "graph") when is_map(graph) do
    params
    |> Map.put("x_axis", build_field_items(Map.get(graph, "x_axis", [])))
    |> Map.put("y_axis", build_graph_metric_items(Map.get(graph, "y_axis", [])))
    |> Map.put("series", build_field_items(Map.get(graph, "series", [])))
    |> Map.put("chart_type", Map.get(graph, "chart_type", "bar"))
    |> maybe_put_map("options", Map.get(graph, "options", %{}))
  end

  defp merge_graph_params(params, _graph, _view_mode), do: params

  defp build_graph_metric_items(items) do
    items
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, index} ->
      id = generated_id("graph-metric", index)

      {id,
       %{
         "uuid" => id,
         "field" => Map.get(item, "field"),
         "alias" => Map.get(item, "alias"),
         "function" => Map.get(item, "function", "count"),
         "index" => Integer.to_string(index)
       }
       |> reject_nil_values(["alias"])}
    end)
  end

  defp merge_option_params(params, options, "aggregate") when is_map(options) do
    params
    |> maybe_put_scalar("aggregate_grid", boolean_string(Map.get(options, "aggregate_grid")))
    |> maybe_put_scalar(
      "aggregate_grid_colorize",
      boolean_string(Map.get(options, "aggregate_grid_colorize"))
    )
    |> maybe_put_scalar(
      "aggregate_grid_color_scale",
      Map.get(options, "aggregate_grid_color_scale")
    )
    |> maybe_put_scalar(
      "aggregate_per_page",
      normalize_scalar(Map.get(options, "aggregate_per_page"))
    )
  end

  defp merge_option_params(params, options, "detail") when is_map(options) do
    params
    |> maybe_put_scalar("per_page", normalize_scalar(Map.get(options, "detail_per_page")))
    |> maybe_put_scalar("max_rows", normalize_scalar(Map.get(options, "detail_max_rows")))
    |> maybe_put_scalar("count_mode", normalize_scalar(Map.get(options, "count_mode")))
    |> maybe_put_scalar(
      "row_click_action",
      normalize_scalar(Map.get(options, "row_click_action"))
    )
    |> maybe_put_scalar(
      "prevent_denormalization",
      boolean_string(Map.get(options, "prevent_denormalization"))
    )
  end

  defp merge_option_params(params, _options, _view_mode), do: params

  defp maybe_put_scalar(params, _key, nil), do: params
  defp maybe_put_scalar(params, key, value), do: Map.put(params, key, value)

  defp maybe_put_map(params, _key, value) when value in [%{}, nil], do: params

  defp maybe_put_map(params, key, value) when is_map(value),
    do: Map.put(params, key, stringify_keys(value))

  defp generated_id(prefix, index), do: "ai-#{prefix}-#{index}"

  defp normalize_scalar(nil), do: nil
  defp normalize_scalar(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_scalar(value) when is_binary(value), do: value
  defp normalize_scalar(value), do: to_string(value)

  defp boolean_string(nil), do: nil
  defp boolean_string(value) when value in [true, "true", "1", 1], do: "true"
  defp boolean_string(value) when value in [false, "false", "0", 0], do: "false"
  defp boolean_string(_), do: nil

  defp denormalize_comparator(nil), do: nil
  defp denormalize_comparator("eq"), do: "="
  defp denormalize_comparator("neq"), do: "!="
  defp denormalize_comparator("gt"), do: ">"
  defp denormalize_comparator("gte"), do: ">="
  defp denormalize_comparator("lt"), do: "<"
  defp denormalize_comparator("lte"), do: "<="
  defp denormalize_comparator("in"), do: "IN"
  defp denormalize_comparator("not_in"), do: "NOT IN"
  defp denormalize_comparator("between"), do: "BETWEEN"
  defp denormalize_comparator("shortcut"), do: "SHORTCUT"
  defp denormalize_comparator("is_empty"), do: "IS NULL"
  defp denormalize_comparator("not_empty"), do: "IS NOT NULL"
  defp denormalize_comparator("contains"), do: "CONTAINS"
  defp denormalize_comparator("starts_with"), do: "STARTS_WITH"
  defp denormalize_comparator("ends_with"), do: "ENDS_WITH"
  defp denormalize_comparator(value), do: String.upcase(to_string(value))

  defp stringify_keys(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify_keys(_), do: %{}

  defp reject_nil_values(map, optional_keys) do
    map
    |> Enum.reject(fn {key, value} -> key in optional_keys and is_nil(value) end)
    |> Map.new()
  end

  defp reject_empty_sections(params) do
    Enum.reduce(
      ["filters", "selected", "order_by", "group_by", "aggregate", "x_axis", "y_axis", "series"],
      params,
      fn key, acc ->
        case Map.get(acc, key) do
          section when is_map(section) and map_size(section) == 0 -> Map.delete(acc, key)
          _ -> acc
        end
      end
    )
  end
end
