defmodule SelectoComponents.Views.Graph.Process do
  alias SelectoComponents.Helpers.BucketParser
  alias SelectoComponents.Param
  alias SelectoComponents.SafeAtom
  alias SelectoComponents.SqlSafety
  alias SelectoComponents.Views.Aggregate.Process, as: AggregateProcess
  alias SelectoComponents.Views.Analytic.Defaults
  alias SelectoComponents.Views.Graph.Encoding

  @doc """
  Converts form parameters to view state for form rendering
  """
  def param_to_state(params, _view) do
    group_by_params = analytical_group_params(params)
    aggregate_params = analytical_aggregate_params(params)

    %{
      group_by: SelectoComponents.Views.view_param_process(group_by_params, "group_by", "field"),
      aggregate:
        SelectoComponents.Views.view_param_process(aggregate_params, "aggregate", "field"),
      visual: visual_state(params, group_by_params, aggregate_params)
    }
  end

  @doc """
  Initial state when view is created without params
  """
  def initial_state(selecto, _view) do
    domain = Selecto.domain(selecto)

    if legacy_graph_defaults?(domain) do
      normalize_state(%{
        x_axis: build_initial(Map.get(domain, :default_graph_x_axis, [])),
        y_axis: build_initial(Map.get(domain, :default_graph_y_axis, [])),
        series: build_initial(Map.get(domain, :default_graph_series, [])),
        color_by: build_initial(Map.get(domain, :default_graph_color_by, [])),
        chart_type: Map.get(domain, :default_chart_type, "auto"),
        options: Map.get(domain, :default_chart_options, %{})
      })
    else
      %{
        group_by: Defaults.group_by(selecto) |> build_initial(),
        aggregate: Defaults.aggregate(selecto) |> build_initial(),
        visual: %{
          type: Map.get(domain, :default_chart_type, "auto"),
          x: nil,
          series: [],
          stack: "auto",
          measure_overrides: %{},
          options: Map.get(domain, :default_chart_options, %{})
        }
      }
    end
  end

  @doc """
  Normalizes saved graph state into the shared analytical query shape.

  Legacy X/Y/Series/Color state is accepted here so saved views continue to
  load, but callers always receive `group_by`, `aggregate`, and `visual`.
  """
  def normalize_state(state) when is_map(state) do
    if map_has_key?(state, :group_by) or map_has_key?(state, :aggregate) do
      %{
        group_by: map_get(state, :group_by, []),
        aggregate: map_get(state, :aggregate, []),
        visual: normalize_visual(map_get(state, :visual, %{}), state)
      }
    else
      x_axis = map_get(state, :x_axis, [])
      series = map_get(state, :series, [])
      color_by = map_get(state, :color_by, [])
      y_axis = map_get(state, :y_axis, [])
      group_by = dedupe_items(x_axis ++ series ++ color_by)

      %{
        group_by: group_by,
        aggregate: Enum.map(y_axis, &legacy_metric_to_aggregate/1),
        visual: %{
          type: map_get(state, :chart_type, "auto"),
          x: item_id(List.first(x_axis)),
          series:
            Enum.map(series ++ color_by, &item_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
          stack: "auto",
          measure_overrides: legacy_measure_overrides(y_axis),
          options: map_get(state, :options, %{})
        }
      }
    end
  end

  def normalize_state(_state),
    do: %{group_by: [], aggregate: [], visual: normalize_visual(%{}, %{})}

  def view(opt, params, columns, filtered, selecto) when not is_nil(selecto) do
    state = param_to_state(params, opt)
    {state, aggregate_params} = analytical_params(state, params)

    {view_set, view_meta} =
      AggregateProcess.view(opt, aggregate_params, columns, filtered, selecto)

    {Encoding.apply(view_set, state, columns), view_meta}
  end

  @doc """
  Converts parameters into Selecto query structure
  """
  def view(_opt, params, columns, filtered, nil) do
    x_axis_params = Map.get(params, "x_axis", %{})
    y_axis_params = Map.get(params, "y_axis", %{})
    series_params = Map.get(params, "series", %{})
    color_by_params = Map.get(params, "color_by", %{})
    chart_type = Map.get(params, "chart_type", "bar")
    presentation_context = runtime_presentation_context(params)

    # Process X-axis (grouping fields)
    x_axis_fields = x_axis_params |> group_by_fields(columns, presentation_context)

    # Process Y-axis (aggregate fields)
    y_axis_defs = y_axis_params |> aggregate_defs(columns)
    y_axis_fields = Enum.map(y_axis_defs, & &1.select_field)

    # Process Series (optional secondary grouping)
    series_fields = series_params |> group_by_fields(columns, presentation_context)

    # Process Color By (optional color grouping)
    color_by_fields = color_by_params |> group_by_fields(columns, presentation_context)

    base_group_by = x_axis_fields ++ series_fields
    color_by_query_fields = Enum.reject(color_by_fields, &group_field_present?(&1, base_group_by))

    # Combine all grouping fields (x_axis + series + non-duplicate color fields)
    all_group_by = base_group_by ++ color_by_query_fields
    resolved_color_by_fields = resolve_color_by_fields(color_by_fields, all_group_by)

    # Build selected fields for query
    selected_fields = Enum.map(all_group_by, fn {_col, sel} -> sel end) ++ y_axis_fields

    {%{
       groups: all_group_by,
       x_axis_groups: x_axis_fields,
       series_groups: series_fields,
       color_by_groups: resolved_color_by_fields,
       aggregates: y_axis_fields,
       graph_series_defs: y_axis_defs,
       selected: selected_fields,
       filtered: filtered,
       chart_type: chart_type,
       graph_options: Map.get(params, "options", %{}),
       group_by: Enum.map(all_group_by, fn {_col, sel} -> sel end),
       order_by:
         case all_group_by do
           [] ->
             []

           group_fields ->
             Enum.map(1..Enum.count(group_fields), fn g -> {:literal_position, g} end)
         end
     }, %{}}
  end

  defp analytical_group_params(params) do
    group_by =
      cond do
        is_map(Map.get(params, "graph_group_by")) -> Map.get(params, "graph_group_by")
        is_map(Map.get(params, "group_by")) -> Map.get(params, "group_by")
        true -> legacy_group_params(params)
      end

    %{"group_by" => group_by}
  end

  defp analytical_aggregate_params(params) do
    aggregate =
      cond do
        is_map(Map.get(params, "graph_aggregate")) -> Map.get(params, "graph_aggregate")
        is_map(Map.get(params, "aggregate")) -> Map.get(params, "aggregate")
        true -> legacy_aggregate_params(Map.get(params, "y_axis", %{}))
      end

    %{"aggregate" => aggregate}
  end

  defp legacy_group_params(params) do
    ["x_axis", "series", "color_by"]
    |> Enum.flat_map(fn key ->
      params
      |> Map.get(key, %{})
      |> Map.values()
      |> Enum.sort_by(&Param.integer(Map.get(&1, "index")))
    end)
    |> Enum.reduce([], fn config, acc ->
      key = {Map.get(config, "field"), Map.get(config, "format")}

      if Enum.any?(acc, fn existing ->
           {Map.get(existing, "field"), Map.get(existing, "format")} == key
         end) do
        acc
      else
        acc ++ [config]
      end
    end)
    |> indexed_param_map()
  end

  defp legacy_aggregate_params(params) when is_map(params) do
    params
    |> Map.values()
    |> Enum.sort_by(&Param.integer(Map.get(&1, "index")))
    |> Enum.map(fn config ->
      config
      |> Map.put("format", Map.get(config, "function", Map.get(config, "format", "count")))
      |> Map.delete("function")
    end)
    |> indexed_param_map()
  end

  defp legacy_aggregate_params(_params), do: %{}

  defp visual_state(params, group_params, aggregate_params) do
    nested_visual = Map.get(params, "graph_visual", %{})
    legacy_y_axis = Map.get(params, "y_axis", %{})

    %{
      type:
        Map.get(
          params,
          "graph_chart_type",
          map_get(nested_visual, :type, Map.get(params, "chart_type", "auto"))
        ),
      x:
        empty_to_nil(Map.get(params, "graph_x", map_get(nested_visual, :x, legacy_x_id(params)))),
      series:
        normalize_series(Map.get(params, "graph_series", map_get(nested_visual, :series, []))),
      stack: Map.get(params, "graph_stack", map_get(nested_visual, :stack, "auto")),
      measure_overrides:
        Map.get(
          params,
          "graph_measure_overrides",
          map_get(
            nested_visual,
            :measure_overrides,
            legacy_measure_overrides_from_params(legacy_y_axis)
          )
        ),
      options:
        Map.get(
          params,
          "graph_options",
          map_get(nested_visual, :options, Map.get(params, "options", %{}))
        )
    }
    |> ensure_visual_refs(group_params, aggregate_params)
  end

  defp ensure_visual_refs(visual, _group_params, _aggregate_params), do: visual

  defp analytical_params(state, params) do
    group_by = reorder_x_first(state.group_by, map_get(state.visual, :x))
    state = %{state | group_by: group_by}

    aggregate_params = %{
      "group_by" => items_to_params(group_by),
      "aggregate" => items_to_params(state.aggregate),
      "_presentation_context" => Map.get(params, "_presentation_context", %{})
    }

    {state, aggregate_params}
  end

  defp reorder_x_first(items, nil), do: items

  defp reorder_x_first(items, x_id) when is_list(items) do
    case Enum.split_with(items, &(item_id(&1) == x_id)) do
      {[], _rest} -> items
      {[x | _], rest} -> [x | rest]
    end
  end

  defp items_to_params(items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn
      {{uuid, field, config}, index}, acc ->
        Map.put(
          acc,
          "k#{index}",
          Map.merge(stringify_keys(config), %{
            "uuid" => uuid,
            "field" => field,
            "index" => to_string(index)
          })
        )

      {[uuid, field, config], index}, acc ->
        Map.put(
          acc,
          "k#{index}",
          Map.merge(stringify_keys(config), %{
            "uuid" => uuid,
            "field" => field,
            "index" => to_string(index)
          })
        )

      {_other, _index}, acc ->
        acc
    end)
  end

  defp items_to_params(_items), do: %{}

  defp indexed_param_map(items) do
    items
    |> Enum.with_index()
    |> Map.new(fn {item, index} ->
      {"k#{index}", Map.put(item, "index", to_string(index))}
    end)
  end

  defp normalize_visual(visual, fallback) do
    %{
      type: map_get(visual, :type, map_get(fallback, :chart_type, "auto")),
      x: empty_to_nil(map_get(visual, :x)),
      series: normalize_series(map_get(visual, :series, [])),
      stack: map_get(visual, :stack, "auto"),
      measure_overrides: map_get(visual, :measure_overrides, %{}),
      options: map_get(visual, :options, map_get(fallback, :options, %{}))
    }
  end

  defp normalize_series(values) when is_list(values),
    do: values |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

  defp normalize_series(value) when value in [nil, ""], do: []
  defp normalize_series(value), do: [value]

  defp legacy_x_id(params) do
    params
    |> Map.get("x_axis", %{})
    |> Map.values()
    |> Enum.sort_by(&Param.integer(Map.get(&1, "index")))
    |> List.first()
    |> case do
      %{} = config -> Map.get(config, "uuid")
      _ -> nil
    end
  end

  defp legacy_measure_overrides_from_params(params) when is_map(params) do
    params
    |> Map.values()
    |> Map.new(fn config ->
      id = Map.get(config, "uuid", Map.get(config, "field"))

      {id,
       %{
         "mark" => Map.get(config, "series_type", "auto"),
         "axis" => Map.get(config, "axis", "left"),
         "color" => Map.get(config, "color")
       }}
    end)
  end

  defp legacy_measure_overrides_from_params(_params), do: %{}

  defp legacy_measure_overrides(items) when is_list(items) do
    Map.new(items, fn item ->
      config = item_config(item)

      {item_id(item),
       %{
         "mark" => map_get(config, :series_type, "auto"),
         "axis" => map_get(config, :axis, "left"),
         "color" => map_get(config, :color)
       }}
    end)
  end

  defp legacy_measure_overrides(_items), do: %{}

  defp legacy_metric_to_aggregate({uuid, field, config}) when is_map(config),
    do: {uuid, field, legacy_metric_config(config)}

  defp legacy_metric_to_aggregate([uuid, field, config]) when is_map(config),
    do: {uuid, field, legacy_metric_config(config)}

  defp legacy_metric_to_aggregate(item), do: item

  defp legacy_metric_config(config) do
    config
    |> stringify_keys()
    |> Map.put("format", map_get(config, :function, map_get(config, :format, "count")))
    |> Map.drop(["function", "series_type", "axis", "color"])
  end

  defp dedupe_items(items) do
    Enum.reduce(items, [], fn item, acc ->
      key = {item_field(item), map_get(item_config(item), :format)}

      if Enum.any?(acc, fn existing ->
           {item_field(existing), map_get(item_config(existing), :format)} == key
         end),
         do: acc,
         else: acc ++ [item]
    end)
  end

  defp item_id({id, _field, _config}), do: id
  defp item_id([id, _field, _config]), do: id
  defp item_id(_item), do: nil

  defp item_field({_id, field, _config}), do: field
  defp item_field([_id, field, _config]), do: field
  defp item_field(_item), do: nil

  defp item_config({_id, _field, config}) when is_map(config), do: config
  defp item_config([_id, _field, config]) when is_map(config), do: config
  defp item_config(_item), do: %{}

  defp build_initial(defaults), do: SelectoComponents.Helpers.build_initial_state(defaults)

  defp legacy_graph_defaults?(domain) do
    Enum.any?(
      [
        :default_graph_x_axis,
        :default_graph_y_axis,
        :default_graph_series,
        :default_graph_color_by
      ],
      fn key -> Map.get(domain, key, []) != [] end
    )
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_keys(_map), do: %{}

  defp empty_to_nil(value) when value in [nil, ""], do: nil
  defp empty_to_nil(value), do: value

  defp map_has_key?(map, key) when is_map(map),
    do: Map.has_key?(map, key) or Map.has_key?(map, to_string(key))

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp map_get(_map, _key, default), do: default

  @doc """
  Process group by fields (for X-axis and Series)
  """
  def group_by_fields(field_params, columns, presentation_context \\ %{}) do
    field_params
    |> Map.values()
    |> Enum.sort_by(&Param.integer(Map.get(&1, "index")))
    |> Enum.map(fn field_config ->
      col = columns[field_config["field"]]

      # Skip if column not found
      if col == nil do
        nil
      else
        col =
          if is_map(col) do
            linked? = truthy_param?(Map.get(field_config, "linked_to_next"))

            col
            |> maybe_set_group_format(Map.get(field_config, "format"))
            |> Map.put(:linked_to_next, linked?)
            |> Map.put("linked_to_next", linked?)
          else
            col
          end

        # Generate alias
        alias_name =
          case field_config["alias"] do
            "" -> field_config["field"]
            nil -> field_config["field"]
            custom_alias -> custom_alias
          end

        # Build field selector based on column type
        field_selector =
          case Selecto.Temporal.date_like_type(col) || col.type do
            x
            when x in [
                   :datetime,
                   :timestamp,
                   :date,
                   :naive_datetime,
                   :utc_datetime,
                   :naive_datetime_usec,
                   :utc_datetime_usec
                 ] ->
              {:field, datetime_group_by_processor(col, field_config, presentation_context),
               alias_name}

            :custom_column ->
              case Map.get(col, :requires_select) do
                x when is_list(x) -> {:row, col.requires_select, alias_name}
                x when is_function(x) -> {:row, col.requires_select.(field_config), alias_name}
                nil -> {:field, col.colid, alias_name}
              end

            _ ->
              {:field, col.colid, alias_name}
          end

        {col, field_selector}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp truthy_param?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy_param?(_), do: false

  defp group_field_present?(group_field, existing_fields) do
    Enum.any?(existing_fields, &same_group_field?(&1, group_field))
  end

  defp resolve_color_by_fields(color_by_fields, all_group_by) do
    Enum.map(color_by_fields, fn color_field ->
      Enum.find(all_group_by, &same_group_field?(&1, color_field)) || color_field
    end)
  end

  defp same_group_field?({left_col, left_selector}, {right_col, right_selector}) do
    group_col_key(left_col) == group_col_key(right_col) ||
      group_selector_key(left_selector) == group_selector_key(right_selector)
  end

  defp group_col_key(col) when is_map(col) do
    Map.get(col, :colid) || Map.get(col, "colid") || Map.get(col, :field) || Map.get(col, "field")
  end

  defp group_col_key(value), do: value

  defp group_selector_key({:field, field, _alias}), do: field
  defp group_selector_key(value), do: value

  @doc """
  Process aggregate fields (for Y-axis)
  """
  def aggregate_fields(aggregate_params, columns) do
    aggregate_params
    |> aggregate_defs(columns)
    |> Enum.map(& &1.select_field)
  end

  def aggregate_defs(aggregate_params, columns) do
    aggregate_params
    |> Map.values()
    |> Enum.sort_by(&Param.integer(Map.get(&1, "index")))
    |> Enum.map(fn field_config ->
      column_def = Map.get(columns, field_config["field"])

      # Generate alias
      alias_name =
        case field_config["alias"] do
          "" -> field_config["field"]
          nil -> field_config["field"]
          custom_alias -> custom_alias
        end

      # Build aggregate function
      # Use SafeAtom to prevent atom table exhaustion from user input
      aggregate_function =
        SafeAtom.to_aggregate_function(
          case field_config["function"] do
            nil -> "count"
            "" -> "count"
            func -> func
          end
        )

      series_type =
        case field_config["series_type"] do
          "line" -> "line"
          "bar" -> "bar"
          _ -> "auto"
        end

      axis =
        case field_config["axis"] do
          "right" -> "right"
          _ -> "left"
        end

      color =
        case field_config["color"] do
          x when is_binary(x) and x != "" -> x
          _ -> nil
        end

      %{
        select_field: {:field, {aggregate_function, field_config["field"]}, alias_name},
        alias: alias_name,
        field: field_config["field"],
        function: aggregate_function,
        series_type: series_type,
        axis: axis,
        color: color,
        column_def: column_def
      }
    end)
  end

  defp maybe_set_group_format(col, format)
       when is_map(col) and is_binary(format) and format != "" do
    col
    |> Map.put(:group_format, format)
    |> Map.put("group_format", format)
  end

  defp maybe_set_group_format(col, _format), do: col

  # Process datetime fields for grouping (Year, Month, Day, etc.)
  defp datetime_group_by_processor(col, config, presentation_context) do
    format = config["format"]
    bucket_ranges = config["bucket_ranges"]

    case format do
      "age_buckets" when is_binary(bucket_ranges) and bucket_ranges != "" ->
        BucketParser.bucket_selector(
          col.colid,
          bucket_ranges,
          :elapsed_days,
          %{temporal_options: temporal_options(col, presentation_context)}
        )

      "custom_buckets" when is_binary(bucket_ranges) and bucket_ranges != "" ->
        BucketParser.bucket_selector(
          col.colid,
          bucket_ranges,
          :date,
          %{temporal_options: temporal_options(col, presentation_context)}
        )

      "year_buckets" when is_binary(bucket_ranges) and bucket_ranges != "" ->
        BucketParser.bucket_selector(
          col.colid,
          bucket_ranges,
          :year,
          %{temporal_options: temporal_options(col, presentation_context)}
        )

      format when is_binary(format) and format not in ["", "default"] ->
        maybe_timezone_aware_datetime_selector(
          col,
          SqlSafety.datetime_grouping_format(format),
          presentation_context
        )

      _ ->
        col.colid
    end
  end

  defp runtime_presentation_context(params) when is_map(params) do
    Map.get(params, "_presentation_context", %{})
  end

  defp maybe_timezone_aware_datetime_selector(col, format, presentation_context) do
    {:datetime_format, col.colid, format, temporal_options(col, presentation_context)}
  end

  defp timezone_grouping_applicable?(col, presentation_context) do
    Selecto.Presentation.temporal_kind(col) == :instant and
      is_binary(runtime_timezone(presentation_context)) and
      runtime_timezone(presentation_context) != ""
  end

  defp temporal_options(col, presentation_context) do
    options = %{epoch_storage: Selecto.Temporal.epoch_storage(col)}

    if timezone_grouping_applicable?(col, presentation_context) do
      Map.merge(options, %{
        timezone: runtime_timezone(presentation_context),
        storage_timezone: storage_timezone(col)
      })
    else
      options
    end
  end

  defp runtime_timezone(presentation_context) when is_map(presentation_context) do
    presentation_context
    |> Map.get(:timezone, Map.get(presentation_context, "timezone"))
    |> SqlSafety.timezone(nil)
  end

  defp runtime_timezone(_presentation_context), do: nil

  defp storage_timezone(col) do
    col
    |> Selecto.Presentation.presentation()
    |> Map.get(:storage_timezone, "Etc/UTC")
    |> SqlSafety.timezone()
  end
end
