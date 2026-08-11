defmodule SelectoComponents.Views.Graph.Encoding do
  @moduledoc """
  Maps an Aggregate query result shape onto Graph display semantics.

  Query construction belongs to `SelectoComponents.Views.Aggregate.Process`;
  this module only identifies the X/series roles, chooses an automatic mark,
  and applies per-measure visual overrides.
  """

  def apply(view_set, state, columns) when is_map(view_set) and is_map(state) do
    groups = Map.get(view_set, :groups, [])
    group_items = Map.get(state, :group_by, [])
    visual = Map.get(state, :visual, %{})
    group_pairs = Enum.zip(group_items, groups)
    x_id = map_get(visual, :x) || item_id(List.first(group_items))

    {x_pairs, remaining_pairs} =
      Enum.split_with(group_pairs, fn {item, _group} -> item_id(item) == x_id end)

    {x_pairs, remaining_pairs} =
      case x_pairs do
        [] -> {Enum.take(group_pairs, 1), Enum.drop(group_pairs, 1)}
        _ -> {x_pairs, remaining_pairs}
      end

    requested_series = MapSet.new(map_get(visual, :series, []))

    {series_pairs, color_pairs} =
      if MapSet.size(requested_series) == 0 do
        {remaining_pairs, []}
      else
        Enum.split_with(remaining_pairs, fn {item, _group} ->
          MapSet.member?(requested_series, item_id(item))
        end)
      end

    aggregates = Map.get(view_set, :aggregates, [])
    metric_defs = metric_defs(aggregates, Map.get(state, :aggregate, []), visual, columns)
    chart_type = resolve_chart_type(map_get(visual, :type, "auto"), x_pairs, aggregates)

    graph_options =
      visual
      |> map_get(:options, %{})
      |> stringify_keys()
      |> Map.put("stack", map_get(visual, :stack, "auto"))
      |> scatter_axis_defaults(chart_type, metric_defs)

    view_set
    |> Map.put(:x_axis_groups, Enum.map(x_pairs, &elem(&1, 1)))
    |> Map.put(:series_groups, Enum.map(series_pairs, &elem(&1, 1)))
    |> Map.put(:color_by_groups, Enum.map(color_pairs, &elem(&1, 1)))
    |> Map.put(:graph_series_defs, metric_defs)
    |> Map.put(:chart_type, chart_type)
    |> Map.put(:graph_options, graph_options)
    |> Map.put(:graph_encoding, visual)
  end

  defp metric_defs(aggregates, items, visual, columns) do
    overrides = map_get(visual, :measure_overrides, %{})
    default_axes = default_axes(items, columns)

    aggregates
    |> Enum.with_index()
    |> Enum.map(fn {aggregate, index} ->
      item = Enum.at(items, index)
      id = item_id(item)
      field = item_field(item)
      config = item_config(item)
      override = map_get(overrides, id, %{})
      default_axis = Enum.at(default_axes, index, "left")

      %{
        select_field: aggregate,
        alias: aggregate_alias(aggregate, field),
        field: field,
        function: aggregate_function(config),
        series_type:
          normalize_mark(map_get(override, :mark, map_get(config, :series_type, "auto"))),
        axis: resolve_axis(map_get(override, :axis), default_axis),
        color: blank_to_nil(map_get(override, :color, map_get(config, :color))),
        column_def: map_get(columns, field)
      }
    end)
  end

  defp default_axes(items, columns) do
    units =
      Enum.map(items, fn item ->
        item
        |> item_field()
        |> then(&map_get(columns, &1))
        |> Selecto.Presentation.canonical_unit()
      end)

    first_unit = Enum.find(units, &(&1 not in [nil, ""]))

    Enum.map(units, fn
      unit when unit in [nil, ""] -> "left"
      ^first_unit -> "left"
      _other -> "right"
    end)
  end

  defp aggregate_alias({:field, _selector, alias_name}, _field)
       when is_binary(alias_name) and alias_name != "",
       do: alias_name

  defp aggregate_alias(_aggregate, field), do: to_string(field || "Value")

  defp aggregate_function(config) do
    config
    |> map_get(:format, map_get(config, :function, "count"))
    |> SelectoComponents.SafeAtom.to_aggregate_function()
  end

  defp resolve_chart_type("auto", x_pairs, _aggregates) do
    case x_pairs do
      [{_item, {column, _selector}}] ->
        type = Selecto.Temporal.date_like_type(column) || map_get(column, :type)

        if type in [
             :date,
             :datetime,
             :timestamp,
             :naive_datetime,
             :utc_datetime,
             :naive_datetime_usec,
             :utc_datetime_usec
           ],
           do: "line",
           else: "bar"

      _ ->
        "bar"
    end
  end

  defp resolve_chart_type("scatter", _x_pairs, aggregates) when length(aggregates) < 2,
    do: "bar"

  defp resolve_chart_type(type, _x_pairs, _aggregates)
       when type in ["bar", "line", "pie", "scatter", "area"],
       do: type

  defp resolve_chart_type(_type, x_pairs, aggregates),
    do: resolve_chart_type("auto", x_pairs, aggregates)

  defp scatter_axis_defaults(options, "scatter", [x_metric, y_metric | _rest]) do
    options
    |> Map.put_new("x_axis_label", x_metric.alias)
    |> Map.put_new("y_axis_label", y_metric.alias)
  end

  defp scatter_axis_defaults(options, _chart_type, _metric_defs), do: options

  defp normalize_mark(mark) when mark in ["bar", "line"], do: mark
  defp normalize_mark(_mark), do: "auto"

  defp normalize_axis("right"), do: "right"
  defp normalize_axis(_axis), do: "left"

  defp resolve_axis(axis, default_axis) when axis in [nil, "", "auto"], do: default_axis
  defp resolve_axis(axis, _default_axis), do: normalize_axis(axis)

  defp item_id({id, _field, _config}), do: id
  defp item_id([id, _field, _config]), do: id
  defp item_id(_item), do: nil

  defp item_field({_id, field, _config}), do: field
  defp item_field([_id, field, _config]), do: field
  defp item_field(_item), do: nil

  defp item_config({_id, _field, config}) when is_map(config), do: config
  defp item_config([_id, _field, config]) when is_map(config), do: config
  defp item_config(_item), do: %{}

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_keys(_map), do: %{}

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp map_get(map, key, default \\ nil)
  defp map_get(_map, nil, default), do: default

  defp map_get(map, key, default) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_get(_map, _key, default), do: default
end
