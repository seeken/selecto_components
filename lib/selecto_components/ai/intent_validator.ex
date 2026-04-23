defmodule SelectoComponents.AI.IntentValidator do
  @moduledoc """
  Validates AI intent payloads against a generated query contract.

  This first slice focuses on deterministic contract-aware validation and
  path-based error output. It does not normalize or apply intent yet.
  """

  @supported_intent_versions [1]
  @supported_modes ["replace", "draft"]
  @supported_chart_types ["bar", "line", "pie", "scatter", "area", "doughnut"]
  @allowed_option_keys ~w(
    aggregate_grid aggregate_grid_colorize aggregate_grid_color_scale aggregate_per_page
    detail_per_page detail_max_rows count_mode row_click_action prevent_denormalization
  )

  @spec validate(map(), map()) :: map()
  def validate(intent, contract) when is_map(intent) and is_map(contract) do
    errors =
      []
      |> validate_intent_version(intent)
      |> validate_mode(intent)
      |> validate_view_mode(intent, contract)
      |> validate_domain_id(intent, contract)
      |> validate_top_level_shapes(intent)
      |> validate_filters(intent, contract)
      |> validate_selected(intent, contract)
      |> validate_order_by(intent, contract)
      |> validate_group_by(intent, contract)
      |> validate_aggregate(intent, contract)
      |> validate_graph(intent, contract)
      |> validate_options(intent, contract)

    %{
      ok: errors == [],
      errors: errors,
      warnings: []
    }
  end

  def validate(_intent, _contract) do
    %{
      ok: false,
      errors: [error("invalid_intent", [], "Intent must be a map payload.")],
      warnings: []
    }
  end

  defp validate_intent_version(errors, intent) do
    version = Map.get(intent, "intent_version", Map.get(intent, :intent_version))

    if version in @supported_intent_versions do
      errors
    else
      errors ++
        [
          error(
            "unsupported_intent_version",
            ["intent_version"],
            "Intent version is not supported."
          )
        ]
    end
  end

  defp validate_mode(errors, intent) do
    mode = to_string_or_nil(Map.get(intent, "mode", Map.get(intent, :mode)))

    cond do
      mode in @supported_modes ->
        errors

      true ->
        errors ++ [error("unsupported_mode", ["mode"], "Mode must be one of replace or draft.")]
    end
  end

  defp validate_view_mode(errors, intent, contract) do
    view_mode = to_string_or_nil(Map.get(intent, "view_mode", Map.get(intent, :view_mode)))
    allowed = get_in(contract, ["context", "view_modes"]) || []

    if view_mode in allowed do
      errors
    else
      errors ++
        [
          error(
            "unsupported_view_mode",
            ["view_mode"],
            "View mode is not allowed by the query contract."
          )
        ]
    end
  end

  defp validate_domain_id(errors, intent, contract) do
    intent_domain = to_string_or_nil(Map.get(intent, "domain_id", Map.get(intent, :domain_id)))
    contract_domain = get_in(contract, ["domain", "id"])

    cond do
      intent_domain in [nil, ""] ->
        errors

      intent_domain == contract_domain ->
        errors

      true ->
        errors ++
          [
            error(
              "domain_mismatch",
              ["domain_id"],
              "Intent domain does not match the query contract."
            )
          ]
    end
  end

  defp validate_top_level_shapes(errors, intent) do
    errors
    |> validate_list_shape(intent, "filters")
    |> validate_list_shape(intent, "selected")
    |> validate_list_shape(intent, "order_by")
    |> validate_list_shape(intent, "group_by")
    |> validate_list_shape(intent, "aggregate")
    |> validate_map_shape(intent, "graph")
    |> validate_map_shape(intent, "options")
  end

  defp validate_filters(errors, intent, contract) do
    intent
    |> get_list("filters")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {filter, index}, acc ->
      acc
      |> validate_item_map(filter, ["filters", index])
      |> validate_field_reference(filter, contract, ["filters", index, "field"])
      |> validate_filter_comparator(filter, contract, index)
    end)
  end

  defp validate_selected(errors, intent, contract) do
    intent
    |> get_list("selected")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      acc
      |> validate_item_map(item, ["selected", index])
      |> validate_field_reference(item, contract, ["selected", index, "field"])
    end)
  end

  defp validate_order_by(errors, intent, contract) do
    intent
    |> get_list("order_by")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      dir = to_string_or_nil(Map.get(item || %{}, "dir", Map.get(item || %{}, :dir)))

      acc
      |> validate_item_map(item, ["order_by", index])
      |> validate_field_reference(item, contract, ["order_by", index, "field"])
      |> then(fn errs ->
        if dir in ["asc", "desc"] do
          errs
        else
          errs ++
            [
              error(
                "invalid_sort_direction",
                ["order_by", index, "dir"],
                "Sort direction must be asc or desc."
              )
            ]
        end
      end)
    end)
  end

  defp validate_group_by(errors, intent, contract) do
    intent
    |> get_list("group_by")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      acc
      |> validate_item_map(item, ["group_by", index])
      |> validate_field_reference(item, contract, ["group_by", index, "field"])
      |> validate_graph_or_groupable(item, contract, index, "group_by", "groupable")
    end)
  end

  defp validate_aggregate(errors, intent, contract) do
    intent
    |> get_list("aggregate")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      function = to_string_or_nil(Map.get(item || %{}, "format", Map.get(item || %{}, :format)))

      acc
      |> validate_item_map(item, ["aggregate", index])
      |> validate_field_reference(item, contract, ["aggregate", index, "field"])
      |> then(fn errs -> validate_aggregate_function(errs, item, contract, function, index) end)
    end)
  end

  defp validate_graph(errors, intent, contract) do
    graph = Map.get(intent, "graph", Map.get(intent, :graph, %{}))

    if is_map(graph) and map_size(graph) > 0 do
      errors
      |> validate_graph_chart_type(graph)
      |> validate_graph_axis(graph, contract, "x_axis", "x_axis")
      |> validate_graph_axis(graph, contract, "series", "series")
      |> validate_graph_metrics(graph, contract)
    else
      errors
    end
  end

  defp validate_options(errors, intent, contract) do
    options = Map.get(intent, "options", Map.get(intent, :options, %{}))
    view_mode = to_string_or_nil(Map.get(intent, "view_mode", Map.get(intent, :view_mode)))

    errors =
      if is_map(options) do
        Enum.reduce(options, errors, fn {key, _value}, acc ->
          key = to_string(key)

          if key in @allowed_option_keys do
            acc
          else
            acc ++
              [
                error(
                  "unsupported_option",
                  ["options", key],
                  "Option is not supported in AI intent validation."
                )
              ]
          end
        end)
      else
        errors
      end

    if truthy?(Map.get(options, "aggregate_grid", Map.get(options, :aggregate_grid))) do
      if view_mode != "aggregate" do
        errors ++
          [
            error(
              "invalid_aggregate_grid_shape",
              ["options", "aggregate_grid"],
              "Aggregate grid is only valid in aggregate view mode."
            )
          ]
      else
        validate_aggregate_grid_shape(errors, intent, contract)
      end
    else
      errors
    end
  end

  defp validate_aggregate_grid_shape(errors, intent, contract) do
    grid_capability = get_in(contract, ["capabilities", "aggregate_grid"]) || %{}
    required_group_by = Map.get(grid_capability, "requires_group_by_count", 2)
    required_aggregate = Map.get(grid_capability, "requires_aggregate_count", 1)

    group_count = intent |> get_list("group_by") |> length()
    aggregate_count = intent |> get_list("aggregate") |> length()

    if group_count == required_group_by and aggregate_count == required_aggregate do
      errors
    else
      errors ++
        [
          error(
            "invalid_aggregate_grid_shape",
            ["options", "aggregate_grid"],
            "Aggregate grid requires exactly #{required_group_by} group-by fields and #{required_aggregate} aggregate field."
          )
        ]
    end
  end

  defp validate_graph_chart_type(errors, graph) do
    chart_type = to_string_or_nil(Map.get(graph, "chart_type", Map.get(graph, :chart_type)))

    if chart_type in @supported_chart_types do
      errors
    else
      errors ++
        [error("invalid_chart_type", ["graph", "chart_type"], "Chart type is not supported.")]
    end
  end

  defp validate_graph_axis(errors, graph, contract, key, capability_key) do
    graph
    |> get_list(key)
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      acc
      |> validate_item_map(item, ["graph", key, index])
      |> validate_field_reference(item, contract, ["graph", key, index, "field"])
      |> validate_graph_or_groupable(item, contract, index, key, capability_key)
    end)
  end

  defp validate_graph_metrics(errors, graph, contract) do
    graph
    |> get_list("y_axis")
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {item, index}, acc ->
      function =
        to_string_or_nil(
          Map.get(
            item || %{},
            "function",
            Map.get(
              item || %{},
              :function,
              Map.get(item || %{}, "format", Map.get(item || %{}, :format))
            )
          )
        )

      acc
      |> validate_item_map(item, ["graph", "y_axis", index])
      |> validate_field_reference(item, contract, ["graph", "y_axis", index, "field"])
      |> validate_graph_or_groupable(item, contract, index, "y_axis", "y_axis")
      |> then(fn errs ->
        validate_aggregate_function(errs, item, contract, function, index, [
          "graph",
          "y_axis",
          index,
          "function"
        ])
      end)
    end)
  end

  defp validate_item_map(errors, item, _path) when is_map(item), do: errors

  defp validate_item_map(errors, _item, path) do
    errors ++ [error("invalid_item_shape", path, "Item must be an object.")]
  end

  defp validate_field_reference(errors, item, contract, path) do
    field_id = to_string_or_nil(Map.get(item || %{}, "field", Map.get(item || %{}, :field)))

    if field_exists?(contract, field_id) do
      errors
    else
      errors ++
        [error("unknown_field", path, "Field '#{field_id}' is not available in this domain.")]
    end
  end

  defp validate_filter_comparator(errors, item, contract, index) do
    field_id = to_string_or_nil(Map.get(item || %{}, "field", Map.get(item || %{}, :field)))
    comparator = to_string_or_nil(Map.get(item || %{}, "comp", Map.get(item || %{}, :comp)))
    allowed = field_comparators(contract, field_id)

    if comparator in allowed do
      errors
    else
      errors ++
        [
          error(
            "invalid_comparator",
            ["filters", index, "comp"],
            "Comparator '#{comparator}' is not allowed for field '#{field_id}'."
          )
        ]
    end
  end

  defp validate_aggregate_function(errors, item, contract, function, index, path \\ nil) do
    field_id = to_string_or_nil(Map.get(item || %{}, "field", Map.get(item || %{}, :field)))
    allowed = field_aggregate_functions(contract, field_id)
    error_path = path || ["aggregate", index, "format"]

    cond do
      function in allowed ->
        errors

      true ->
        errors ++
          [
            error(
              "invalid_aggregate_function",
              error_path,
              "Aggregate function '#{function}' is not allowed for field '#{field_id}'."
            )
          ]
    end
  end

  defp validate_graph_or_groupable(errors, item, contract, index, section_key, capability_key) do
    field_id = to_string_or_nil(Map.get(item || %{}, "field", Map.get(item || %{}, :field)))

    if field_capability?(contract, field_id, section_key, capability_key) do
      errors
    else
      errors ++
        [
          error(
            "invalid_field_capability",
            [section_path_root(section_key), section_key, index, "field"],
            "Field '#{field_id}' is not allowed in #{section_key}."
          )
        ]
    end
  end

  defp section_path_root(section_key) when section_key in ["x_axis", "y_axis", "series"],
    do: "graph"

  defp section_path_root(_section_key), do: nil

  defp field_exists?(contract, field_id) when is_binary(field_id) do
    Enum.any?(Map.get(contract, "fields", []), &(&1["id"] == field_id))
  end

  defp field_exists?(_contract, _field_id), do: false

  defp field_comparators(contract, field_id) do
    contract
    |> find_field(field_id)
    |> Map.get("comparators", [])
  end

  defp field_aggregate_functions(contract, field_id) do
    contract
    |> find_field(field_id)
    |> Map.get("aggregate_functions", [])
  end

  defp field_capability?(contract, field_id, "group_by", _capability_key) do
    contract
    |> find_field(field_id)
    |> Map.get("groupable", false)
  end

  defp field_capability?(contract, field_id, section_key, capability_key)
       when section_key in ["x_axis", "y_axis", "series"] do
    contract
    |> find_field(field_id)
    |> Map.get("graph", %{})
    |> Map.get(capability_key, false)
  end

  defp field_capability?(_contract, _field_id, _section_key, _capability_key), do: true

  defp find_field(contract, field_id) do
    Enum.find(Map.get(contract, "fields", []), %{}, &(&1["id"] == field_id))
  end

  defp validate_list_shape(errors, intent, key) do
    value = Map.get(intent, key, Map.get(intent, String.to_atom(key)))

    cond do
      is_nil(value) or is_list(value) -> errors
      true -> errors ++ [error("invalid_shape", [key], "#{key} must be an array.")]
    end
  end

  defp validate_map_shape(errors, intent, key) do
    value = Map.get(intent, key, Map.get(intent, String.to_atom(key)))

    cond do
      is_nil(value) or is_map(value) -> errors
      true -> errors ++ [error("invalid_shape", [key], "#{key} must be an object.")]
    end
  end

  defp get_list(map, key) when is_map(map) do
    case Map.get(map, key, Map.get(map, String.to_atom(key), [])) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_list(_map, _key), do: []

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_or_nil(value) when is_binary(value), do: value
  defp to_string_or_nil(value), do: to_string(value)

  defp truthy?(value) when value in [true, "true", "1", 1], do: true
  defp truthy?(_), do: false

  defp error(code, path, message) do
    %{
      "code" => code,
      "path" => path,
      "message" => message,
      "severity" => "error"
    }
  end
end
