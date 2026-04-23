defmodule SelectoComponents.AI.QueryContract do
  @moduledoc """
  Generates a machine-readable query contract for AI integrations.

  This is the first AI foundation slice: a deterministic contract describing the
  available views, fields, params, and high-level capabilities for a Selecto
  domain inside SelectoComponents.
  """

  alias SelectoComponents.Views.Aggregate.Options, as: AggregateOptions

  @query_contract_version 1
  @export_formats ~w(csv tsv json xlsx)
  @error_messages %{
    "unknown_field" => %{"message" => "The requested field does not exist in this domain."},
    "invalid_comparator" => %{
      "message" => "The comparator is not allowed for the selected field type."
    },
    "invalid_aggregate_grid_shape" => %{
      "message" => "Aggregate grid requires exactly 2 group-by fields and 1 aggregate."
    }
  }

  @spec generate(term(), list(), keyword()) :: map()
  def generate(selecto, views, opts \\ []) when is_list(views) do
    domain = Selecto.domain(selecto)
    columns = scoped_columns(Selecto.columns(selecto), opts)
    filters = Selecto.filters(selecto) || %{}
    field_filters = build_field_filter_map(selecto)
    view_modes = Enum.map(views, fn {id, _module, _name, _opts} -> Atom.to_string(id) end)
    default_view_mode = List.first(view_modes) || "detail"

    %{
      "query_contract_version" => @query_contract_version,
      "generated_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "domain" => domain_descriptor(domain, opts),
      "context" => context_descriptor(view_modes, default_view_mode, opts),
      "fields" => field_descriptors(columns, filters, field_filters, opts),
      "params_schema" => params_schema(view_modes),
      "capabilities" => capabilities(view_modes, opts),
      "examples" => examples(columns, view_modes, opts),
      "errors" => @error_messages
    }
  end

  defp domain_descriptor(domain, opts) do
    %{
      "id" => to_string(Map.get(domain, :name, "unknown_domain")),
      "name" => human_name(Map.get(domain, :name, "unknown_domain")),
      "description" => Map.get(domain, :description),
      "path" => Keyword.get(opts, :path)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp context_descriptor(view_modes, default_view_mode, opts) do
    %{
      "view_modes" => view_modes,
      "default_view_mode" => default_view_mode,
      "exports" => Keyword.get(opts, :exports, @export_formats),
      "saved_views_enabled" => truthy_option?(opts, :saved_views_enabled),
      "exported_views_enabled" => truthy_option?(opts, :exported_views_enabled),
      "ai_actions_enabled" => truthy_option?(opts, :ai_actions_enabled)
    }
  end

  defp field_descriptors(columns, filters, field_filters, opts) do
    columns
    |> Enum.map(fn {field_id, column} ->
      field_descriptor(field_id, column, filters, field_filters, opts)
    end)
    |> Enum.sort_by(& &1["label"])
  end

  defp field_descriptor(field_id, column, filters, field_filters, opts) do
    field_id = to_string(field_id)
    type = normalized_type(column)
    explicit_filter = Map.get(filters, field_id)
    filter_config = Map.get(field_filters, field_id)
    filterable = not is_nil(filter_config) or not is_nil(explicit_filter)
    groupable = groupable_type?(type)
    aggregatable = aggregatable_type?(type)

    descriptor = %{
      "id" => field_id,
      "label" => Map.get(column, :name, field_id),
      "type" => type,
      "description" => Map.get(column, :description),
      "filterable" => filterable,
      "sortable" => sortable_type?(type),
      "detail_selectable" => detail_selectable?(column),
      "groupable" => groupable,
      "aggregatable" => aggregatable,
      "graph" => %{
        "x_axis" => groupable,
        "y_axis" => aggregatable,
        "series" => groupable
      },
      "comparators" => comparators_for(type, explicit_filter),
      "formats" => formats_for(column),
      "aliases_allowed" => true,
      "visibility" => visibility_for(column, opts)
    }

    descriptor
    |> maybe_put("aggregate_functions", aggregate_functions_for(type, column))
    |> maybe_put("shortcut_values", shortcut_values_for(type))
    |> maybe_put("example_values", Map.get(column, :example_values))
    |> reject_nil_values()
  end

  defp params_schema(view_modes) do
    %{
      "top_level_keys" => %{
        "view_mode" => %{"type" => "string", "allowed" => view_modes},
        "filters" => %{"type" => "section", "item_shape" => "filter"},
        "selected" => %{"type" => "section", "item_shape" => "detail_field"},
        "order_by" => %{"type" => "section", "item_shape" => "order_by"},
        "group_by" => %{"type" => "section", "item_shape" => "group_field"},
        "aggregate" => %{"type" => "section", "item_shape" => "aggregate_field"},
        "aggregate_grid" => %{"type" => "boolean"}
      },
      "item_shapes" => %{
        "filter" => %{
          "required" => ["field", "comp"],
          "properties" => %{
            "uuid" => %{"type" => "string", "generated_by" => "selecto"},
            "field" => %{"type" => "field_id"},
            "comp" => %{"type" => "comparator_id"},
            "value" => %{"type" => "any"},
            "section" => %{"type" => "string", "default" => "filters"},
            "index" => %{"type" => "integer", "generated_by" => "selecto"}
          }
        },
        "detail_field" => %{
          "required" => ["field"],
          "properties" => %{
            "uuid" => %{"type" => "string", "generated_by" => "selecto"},
            "field" => %{"type" => "field_id"},
            "alias" => %{"type" => "string"},
            "format" => %{"type" => "string", "default" => "default"},
            "index" => %{"type" => "integer", "generated_by" => "selecto"}
          }
        },
        "group_field" => %{
          "required" => ["field"],
          "properties" => %{
            "uuid" => %{"type" => "string", "generated_by" => "selecto"},
            "field" => %{"type" => "field_id"},
            "alias" => %{"type" => "string"},
            "format" => %{"type" => "string", "default" => "default"},
            "index" => %{"type" => "integer", "generated_by" => "selecto"}
          }
        },
        "aggregate_field" => %{
          "required" => ["field", "format"],
          "properties" => %{
            "uuid" => %{"type" => "string", "generated_by" => "selecto"},
            "field" => %{"type" => "field_id"},
            "alias" => %{"type" => "string"},
            "format" => %{"type" => "aggregate_function"},
            "index" => %{"type" => "integer", "generated_by" => "selecto"}
          }
        },
        "order_by" => %{
          "required" => ["field", "dir"],
          "properties" => %{
            "uuid" => %{"type" => "string", "generated_by" => "selecto"},
            "field" => %{"type" => "field_id"},
            "dir" => %{"type" => "string", "allowed" => ["asc", "desc"]},
            "index" => %{"type" => "integer", "generated_by" => "selecto"}
          }
        }
      }
    }
  end

  defp capabilities(view_modes, opts) do
    %{
      "aggregate_grid" => %{
        "enabled" => true,
        "requires_group_by_count" => 2,
        "requires_aggregate_count" => 1,
        "supports_colorize" => true,
        "supports_color_scales" => AggregateOptions.grid_color_scale_modes()
      },
      "views" =>
        Map.new(view_modes, fn mode ->
          {mode, %{"enabled" => true}}
        end),
      "exports" => %{"formats" => Keyword.get(opts, :exports, @export_formats)},
      "limits" => %{
        "max_group_by_fields" => nil,
        "max_aggregate_fields" => nil,
        "max_selected_fields" => nil
      }
    }
  end

  defp build_field_filter_map(selecto) do
    selecto
    |> SelectoComponents.Form.FilterRendering.build_filter_list()
    |> Enum.reduce(%{}, fn {field_id, _label, meta}, acc ->
      Map.put(acc, to_string(field_id), meta)
    end)
  end

  defp normalized_type(column) do
    raw_type = Selecto.Temporal.date_like_type(column) || Map.get(column, :type)

    cond do
      raw_type in [:integer, "integer"] -> "integer"
      raw_type in [:float, "float"] -> "float"
      raw_type in [:decimal, :numeric, "decimal", "numeric"] -> "decimal"
      raw_type in [:boolean, "boolean"] -> "boolean"
      raw_type in [:date, "date"] -> "date"
      raw_type in [:naive_datetime, "naive_datetime"] -> "naive_datetime"
      raw_type in [:utc_datetime, :datetime, "utc_datetime", "datetime"] -> "utc_datetime"
      raw_type in [:time, "time"] -> "time"
      raw_type in [:uuid, "uuid"] -> "uuid"
      raw_type in [:json, :jsonb, "json", "jsonb"] -> "json"
      raw_type in [:text, "text", :tsvector, "tsvector"] -> "text"
      raw_type in [:string, "string"] -> "string"
      is_binary(raw_type) -> raw_type
      is_atom(raw_type) -> Atom.to_string(raw_type)
      true -> "string"
    end
  end

  defp comparators_for(type, explicit_filter) do
    explicit =
      case explicit_filter do
        filter when is_map(filter) ->
          filter
          |> Map.get(:comps, Map.get(filter, "comps"))
          |> normalize_explicit_comparators()

        _ ->
          []
      end

    if explicit != [] do
      explicit
    else
      default_comparators_for(type)
    end
  end

  defp default_comparators_for(type) when type in ["integer", "float", "decimal"] do
    ~w(eq neq gt gte lt lte between in not_in is_empty)
  end

  defp default_comparators_for(type)
       when type in ["date", "naive_datetime", "utc_datetime", "time"] do
    ~w(eq neq gt gte lt lte between shortcut is_empty)
  end

  defp default_comparators_for(type) when type in ["boolean"] do
    ~w(eq neq is_empty)
  end

  defp default_comparators_for(type) when type in ["text"] do
    ~w(eq neq contains starts_with ends_with in not_in is_empty)
  end

  defp default_comparators_for(_type) do
    ~w(eq neq contains starts_with ends_with in not_in is_empty)
  end

  defp aggregate_functions_for(type, _column) when type in ["integer", "float", "decimal"] do
    ["sum", "avg", "min", "max"]
  end

  defp aggregate_functions_for(_type, _column), do: nil

  defp shortcut_values_for(type) when type in ["date", "naive_datetime", "utc_datetime"] do
    ["today", "yesterday", "this_week", "last_month"]
  end

  defp shortcut_values_for(_type), do: nil

  defp formats_for(column) do
    case Map.get(column, :format) do
      nil -> ["default"]
      format when is_binary(format) -> [format]
      format when is_atom(format) -> [Atom.to_string(format)]
      _ -> ["default"]
    end
  end

  defp visibility_for(column, opts) do
    explicit_visibility =
      case Keyword.get(opts, :field_visibility) do
        visibility when is_map(visibility) ->
          Map.get(
            visibility,
            Map.get(column, :colid),
            Map.get(visibility, to_string(Map.get(column, :colid)))
          )

        visibility_fun when is_function(visibility_fun, 2) ->
          visibility_fun.(Map.get(column, :colid), column)

        _ ->
          nil
      end

    cond do
      explicit_visibility in ["hidden", "advanced", "normal"] -> explicit_visibility
      Map.get(column, :hidden) == true -> "hidden"
      Map.get(column, :advanced) == true -> "advanced"
      true -> "normal"
    end
  end

  defp examples(columns, view_modes, opts) do
    custom_examples = Keyword.get(opts, :examples)

    cond do
      is_list(custom_examples) and custom_examples != [] ->
        custom_examples

      true ->
        build_default_examples(columns, view_modes)
    end
  end

  defp build_default_examples(columns, view_modes) do
    column_list =
      Enum.map(columns, fn {field_id, column} ->
        {to_string(field_id), normalized_type(column), column}
      end)

    detail_field =
      Enum.find(column_list, fn {_id, _type, column} -> detail_selectable?(column) end)

    group_field = Enum.find(column_list, fn {_id, type, _column} -> groupable_type?(type) end)
    metric_field = Enum.find(column_list, fn {_id, type, _column} -> aggregatable_type?(type) end)

    time_field =
      Enum.find(column_list, fn {_id, type, _column} ->
        type in ["date", "naive_datetime", "utc_datetime"]
      end)

    []
    |> maybe_add_example(detail_example(detail_field, view_modes))
    |> maybe_add_example(aggregate_example(group_field, metric_field, view_modes))
    |> maybe_add_example(graph_example(time_field, metric_field, view_modes))
  end

  defp detail_example({field_id, _type, column}, view_modes) do
    if "detail" in view_modes do
      %{
        "id" => "detail_single_field",
        "prompt" => "Show #{Map.get(column, :name, field_id)} in detail view",
        "description" => "Simple detail selection example",
        "intent" => %{
          "view_mode" => "detail",
          "selected" => [
            %{
              "field" => field_id,
              "alias" => Map.get(column, :name, field_id),
              "format" => "default"
            }
          ]
        },
        "params" => %{},
        "notes" => ["Uses one detail field selection."]
      }
    end
  end

  defp detail_example(_, _), do: nil

  defp aggregate_example(
         {group_id, _group_type, group_col},
         {metric_id, _metric_type, metric_col},
         view_modes
       ) do
    if "aggregate" in view_modes do
      %{
        "id" => "aggregate_metric_by_dimension",
        "prompt" =>
          "Show #{Map.get(metric_col, :name, metric_id)} by #{Map.get(group_col, :name, group_id)}",
        "description" => "Basic aggregate example",
        "intent" => %{
          "view_mode" => "aggregate",
          "group_by" => [
            %{
              "field" => group_id,
              "alias" => Map.get(group_col, :name, group_id),
              "format" => "default"
            }
          ],
          "aggregate" => [
            %{
              "field" => metric_id,
              "alias" => Map.get(metric_col, :name, metric_id),
              "format" => "sum"
            }
          ]
        },
        "params" => %{},
        "notes" => ["Uses one group-by field and one aggregate metric."]
      }
    end
  end

  defp aggregate_example(_, _, _), do: nil

  defp graph_example(
         {time_id, _time_type, time_col},
         {metric_id, _metric_type, metric_col},
         view_modes
       ) do
    if "graph" in view_modes do
      %{
        "id" => "graph_metric_over_time",
        "prompt" => "Plot #{Map.get(metric_col, :name, metric_id)} over time",
        "description" => "Basic graph example",
        "intent" => %{
          "view_mode" => "graph",
          "graph" => %{
            "x_axis" => [
              %{
                "field" => time_id,
                "alias" => Map.get(time_col, :name, time_id),
                "format" => "default"
              }
            ],
            "y_axis" => [
              %{
                "field" => metric_id,
                "alias" => Map.get(metric_col, :name, metric_id),
                "format" => "sum"
              }
            ],
            "series" => [],
            "chart_type" => "bar"
          }
        },
        "params" => %{},
        "notes" => ["Uses one time dimension and one metric."]
      }
    end
  end

  defp graph_example(_, _, _), do: nil

  defp maybe_add_example(examples, nil), do: examples
  defp maybe_add_example(examples, example), do: examples ++ [example]

  defp scoped_columns(columns, opts) do
    case Keyword.get(opts, :allowed_fields) do
      nil ->
        columns

      allowed_fields ->
        allowed = MapSet.new(Enum.map(List.wrap(allowed_fields), &to_string/1))

        columns
        |> Enum.filter(fn {field_id, _column} -> MapSet.member?(allowed, to_string(field_id)) end)
        |> Map.new()
    end
  end

  defp detail_selectable?(column) do
    not Map.has_key?(column, :component)
  end

  defp sortable_type?(type), do: type not in ["json"]
  defp groupable_type?(type), do: type not in ["json"]
  defp aggregatable_type?(type), do: type in ["integer", "float", "decimal"]

  defp normalize_explicit_comparators(nil), do: []

  defp normalize_explicit_comparators(list) when is_list(list) do
    Enum.map(list, &normalize_comparator/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_explicit_comparators(_), do: []

  defp normalize_comparator(value) when is_atom(value),
    do: normalize_comparator(Atom.to_string(value))

  defp normalize_comparator(value) when is_binary(value) do
    case value |> String.trim() |> String.upcase() do
      "=" -> "eq"
      "!=" -> "neq"
      ">" -> "gt"
      ">=" -> "gte"
      "<" -> "lt"
      "<=" -> "lte"
      "IN" -> "in"
      "NOT IN" -> "not_in"
      "BETWEEN" -> "between"
      "DATE_BETWEEN" -> "between"
      "SHORTCUT" -> "shortcut"
      "IS NULL" -> "is_empty"
      "IS NOT NULL" -> "not_empty"
      "CONTAINS" -> "contains"
      "STARTS_WITH" -> "starts_with"
      "ENDS_WITH" -> "ends_with"
      "TEXT_SEARCH" -> "contains"
      other when other != "" -> String.downcase(other)
      _ -> nil
    end
  end

  defp normalize_comparator(_), do: nil

  defp truthy_option?(opts, key) do
    Keyword.get(opts, key, false) == true
  end

  defp human_name(value) when is_atom(value), do: value |> Atom.to_string() |> human_name()

  defp human_name(value) when is_binary(value) do
    value
    |> String.split([".", "_"], trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp human_name(value), do: to_string(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
