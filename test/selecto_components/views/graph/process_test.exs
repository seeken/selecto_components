defmodule SelectoComponents.Views.Graph.ProcessTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Views.Graph.Process

  describe "param_to_state/2" do
    test "converts form parameters to view state" do
      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "category",
            "index" => "0",
            "alias" => "Category",
            "linked_to_next" => "true"
          },
          "2" => %{"field" => "release_year", "index" => "1", "alias" => ""}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Film Count"
          }
        },
        "series" => %{
          "1" => %{"field" => "rating", "index" => "0", "alias" => "Rating"}
        },
        "color_by" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category Color"}
        },
        "chart_type" => "bar",
        "options" => %{"title" => "Films by Category"}
      }

      state = Process.param_to_state(params, :graph)

      assert state.visual.type == "bar"
      assert state.visual.options == %{"title" => "Films by Category"}
      assert length(state.group_by) == 3
      assert length(state.aggregate) == 1

      [category, release_year, rating] = state.group_by
      assert elem(category, 1) == "category"
      assert elem(release_year, 1) == "release_year"
      assert elem(rating, 1) == "rating"
      assert get_in(elem(category, 2), ["linked_to_next"]) == "true"
      assert elem(hd(state.aggregate), 2)["format"] == "count"
    end

    test "handles empty parameters gracefully" do
      params = %{}
      state = Process.param_to_state(params, :graph)

      assert state.visual.type == "auto"
      assert state.visual.options == %{}
      assert state.group_by == []
      assert state.aggregate == []
    end

    test "defaults chart_type when not provided" do
      params = %{"x_axis" => %{}}
      state = Process.param_to_state(params, :graph)

      assert state.visual.type == "auto"
    end
  end

  describe "initial_state/2" do
    test "creates initial state from selecto domain" do
      # Mock selecto with domain configuration
      domain = %{
        default_graph_x_axis: ["category"],
        default_graph_y_axis: ["count"],
        default_chart_type: "line",
        default_chart_options: %{"title" => "Default Chart"}
      }

      selecto = %{domain: domain}

      state = Process.initial_state(selecto, :graph)

      assert state.visual.type == "line"
      assert state.visual.options == %{"title" => "Default Chart"}
      assert length(state.group_by) == 1
      assert length(state.aggregate) == 1
    end

    test "uses defaults when domain configuration is missing" do
      domain = %{}
      selecto = %{domain: domain}

      state = Process.initial_state(selecto, :graph)

      assert state.visual.type == "auto"
      assert state.visual.options == %{}
    end
  end

  describe "view/5" do
    setup do
      columns = %{
        "category" => %{colid: :category, type: :string},
        "rating" => %{colid: :rating, type: :string},
        "film_count" => %{colid: :film_id, type: :integer},
        "release_year" => %{colid: :release_year, type: :integer}
      }

      {:ok, columns: columns}
    end

    test "delegates the analytical query to Aggregate.Process and only adds encoding" do
      selecto = analytical_selecto()

      columns =
        selecto
        |> Selecto.columns()
        |> Map.new(fn {key, column} ->
          {key, column |> Map.put(:field, column.name) |> Map.put(:colid, key)}
        end)

      params = %{
        "graph_group_by" => %{
          "g1" => %{
            "uuid" => "g1",
            "field" => "booked_at",
            "index" => "0",
            "format" => "month"
          },
          "g2" => %{"uuid" => "g2", "field" => "category", "index" => "1"}
        },
        "graph_aggregate" => %{
          "a1" => %{
            "uuid" => "a1",
            "field" => "hours",
            "index" => "0",
            "format" => "sum"
          }
        },
        "graph_chart_type" => "auto"
      }

      {view_set, _meta} = Process.view(nil, params, columns, [], selecto)

      assert length(view_set.groups) == 2
      assert length(view_set.aggregates) == 1
      assert view_set.selected == Enum.map(view_set.groups, &elem(&1, 1)) ++ view_set.aggregates
      assert view_set.x_axis_groups == Enum.take(view_set.groups, 1)
      assert view_set.series_groups == Enum.drop(view_set.groups, 1)
      assert view_set.chart_type == "line"
      assert [%{field: "hours", function: :sum}] = view_set.graph_series_defs
    end

    test "generates view structure for bar chart with x-axis and y-axis", %{columns: columns} do
      params = %{
        "x_axis" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "chart_type" => "bar"
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      assert view_set.chart_type == "bar"
      assert length(view_set.x_axis_groups) == 1
      assert length(view_set.aggregates) == 1
      # x_axis + y_axis fields
      assert length(view_set.selected) == 2

      # Check grouping structure
      [{col, field_selector}] = view_set.x_axis_groups
      assert col.colid == :category
      assert elem(field_selector, 0) == :field
      assert elem(field_selector, 1) == :category
      assert elem(field_selector, 2) == "Category"

      # Check aggregate structure
      [aggregate] = view_set.aggregates
      assert elem(aggregate, 0) == :field
      assert elem(aggregate, 1) == {:count, "film_count"}
      assert elem(aggregate, 2) == "Count"
    end

    test "generates view structure with series grouping", %{columns: columns} do
      params = %{
        "x_axis" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "series" => %{
          "1" => %{"field" => "rating", "index" => "0", "alias" => "Rating"}
        },
        "chart_type" => "line"
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      assert view_set.chart_type == "line"
      assert length(view_set.x_axis_groups) == 1
      assert length(view_set.series_groups) == 1
      assert length(view_set.aggregates) == 1
      # x_axis + series
      assert length(view_set.groups) == 2
      # x_axis + series + y_axis fields
      assert length(view_set.selected) == 3

      # Check that groups include both x_axis and series
      group_fields = Enum.map(view_set.groups, fn {col, _} -> col.colid end)
      assert :category in group_fields
      assert :rating in group_fields
    end

    test "uses color_by as a grouping without duplicating existing x-axis fields", %{
      columns: columns
    } do
      params = %{
        "x_axis" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category"},
          "2" => %{"field" => "release_year", "index" => "1", "alias" => "Year"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "color_by" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category Color"}
        }
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      assert length(view_set.x_axis_groups) == 2
      assert length(view_set.color_by_groups) == 1
      assert length(view_set.groups) == 2
      assert length(view_set.selected) == 3

      [{color_col, _selector}] = view_set.color_by_groups
      assert color_col.colid == :category
    end

    test "preserves linked graph group metadata on x-axis and series fields", %{columns: columns} do
      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "category",
            "index" => "0",
            "alias" => "Category",
            "linked_to_next" => "true"
          },
          "2" => %{"field" => "release_year", "index" => "1", "alias" => "Year"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "series" => %{
          "1" => %{"field" => "rating", "index" => "0", "alias" => "Rating"}
        }
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      [{first_x_col, _}, {second_x_col, _}] = view_set.x_axis_groups
      [{series_col, _}] = view_set.series_groups

      assert first_x_col.linked_to_next == true
      assert second_x_col.linked_to_next == false
      assert series_col.linked_to_next == false
    end

    test "handles datetime fields with format options", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "created_at", %{colid: :created_at, type: :naive_datetime})

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "created_at",
            "index" => "0",
            "alias" => "Month",
            "format" => "YYYY-MM"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        }
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)

      [{col, field_selector}] = view_set.x_axis_groups
      assert col.colid == :created_at
      assert elem(field_selector, 0) == :field

      assert elem(field_selector, 1) ==
               {:datetime_format, :created_at, "YYYY-MM", %{epoch_storage: nil}}

      assert elem(field_selector, 2) == "Month"
    end

    test "supports aggregate datetime format tokens in graph grouping", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "created_at", %{colid: :created_at, type: :utc_datetime})

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "created_at",
            "index" => "0",
            "alias" => "Quarter",
            "format" => "YYYY-Q"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        }
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field, {:datetime_format, :created_at, "YYYY-Q", %{epoch_storage: nil}}, "Quarter"} =
               field_selector
    end

    test "supports postgres datetime atom format tokens in graph grouping", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "atnd_created", %{colid: :atnd_created, type: :datetime})

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "atnd_created",
            "index" => "0",
            "alias" => "Quarter",
            "format" => "YYYY-Q"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        }
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field, {:datetime_format, :atnd_created, "YYYY-Q", %{epoch_storage: nil}},
              "Quarter"} = field_selector
    end

    test "uses viewer timezone for instant datetime graph grouping", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "created_at", %{
          colid: :created_at,
          type: :utc_datetime,
          presentation: %{
            semantic_type: :temporal,
            temporal_kind: :instant,
            display_timezone: :viewer
          }
        })

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "created_at",
            "index" => "0",
            "alias" => "Month",
            "format" => "YYYY-MM"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "_presentation_context" => %{"timezone" => "America/New_York"}
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field,
              {:datetime_format, :created_at, "YYYY-MM",
               %{
                 epoch_storage: nil,
                 timezone: "America/New_York",
                 storage_timezone: "Etc/UTC"
               }}, "Month"} = field_selector
    end

    test "preserves composite datetime formats with viewer timezone in graph grouping", %{
      columns: columns
    } do
      datetime_columns =
        Map.put(columns, "published_at_usec", %{
          colid: :published_at_usec,
          type: :utc_datetime_usec,
          presentation: %{
            semantic_type: :temporal,
            temporal_kind: :instant,
            storage_timezone: "Etc/UTC",
            display_timezone: :viewer
          }
        })

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "published_at_usec",
            "index" => "0",
            "alias" => "Hour",
            "format" => "YYYY-MM-DD HH24"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "_presentation_context" => %{"timezone" => "Europe/Berlin"}
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field,
              {:datetime_format, :published_at_usec, "YYYY-MM-DD HH24",
               %{
                 epoch_storage: nil,
                 timezone: "Europe/Berlin",
                 storage_timezone: "Etc/UTC"
               }}, "Hour"} = field_selector
    end

    test "supports year buckets in graph grouping", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "created_at", %{colid: :created_at, type: :utc_datetime})

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "created_at",
            "index" => "0",
            "alias" => "Year Buckets",
            "format" => "year_buckets",
            "bucket_ranges" => "*/5"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        }
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field,
              {:bucket, :created_at,
               %{
                 kind: :year_increment,
                 increment: 5,
                 temporal_options: %{epoch_storage: nil}
               }}, "Year Buckets"} = field_selector
    end

    test "uses viewer timezone for instant year buckets in graph grouping", %{columns: columns} do
      datetime_columns =
        Map.put(columns, "occurred_at_epoch", %{
          colid: :occurred_at_epoch,
          type: :integer,
          presentation_type: :utc_datetime,
          datetime_storage: :unix_seconds,
          presentation: %{
            semantic_type: :temporal,
            temporal_kind: :instant,
            display_timezone: :viewer
          }
        })

      params = %{
        "x_axis" => %{
          "1" => %{
            "field" => "occurred_at_epoch",
            "index" => "0",
            "alias" => "Year Buckets",
            "format" => "year_buckets",
            "bucket_ranges" => "*/5"
          }
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          }
        },
        "_presentation_context" => %{"timezone" => "America/New_York"}
      }

      {view_set, _} = Process.view(nil, params, datetime_columns, [], nil)
      [{_col, field_selector}] = view_set.x_axis_groups

      assert {:field,
              {:bucket, :occurred_at_epoch,
               %{
                 kind: :year_increment,
                 increment: 5,
                 temporal_options: %{
                   epoch_storage: :unix_seconds,
                   timezone: "America/New_York",
                   storage_timezone: "Etc/UTC"
                 }
               }}, "Year Buckets"} = field_selector
    end

    test "generates proper order_by and group_by clauses", %{columns: columns} do
      params = %{
        "x_axis" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "sum",
            "alias" => "Total"
          }
        },
        "series" => %{
          "1" => %{"field" => "rating", "index" => "0", "alias" => "Rating"}
        }
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      assert view_set.group_by == [
               {:field, :category, "Category"},
               {:field, :rating, "Rating"}
             ]

      assert view_set.order_by == [{:literal_position, 1}, {:literal_position, 2}]
    end

    test "handles multiple aggregate functions", %{columns: columns} do
      params = %{
        "x_axis" => %{
          "1" => %{"field" => "category", "index" => "0", "alias" => "Category"}
        },
        "y_axis" => %{
          "1" => %{
            "field" => "film_count",
            "index" => "0",
            "function" => "count",
            "alias" => "Count"
          },
          "2" => %{
            "field" => "film_count",
            "index" => "1",
            "function" => "avg",
            "alias" => "Average"
          }
        }
      }

      {view_set, _} = Process.view(nil, params, columns, [], nil)

      assert length(view_set.aggregates) == 2

      [first_agg, second_agg] = view_set.aggregates
      assert elem(first_agg, 1) == {:count, "film_count"}
      assert elem(second_agg, 1) == {:avg, "film_count"}
    end
  end

  defp analytical_selecto do
    Selecto.configure(
      %{
        name: "AnalyticalGraph",
        source: %{
          source_table: "bookings",
          primary_key: :id,
          fields: [:id, :booked_at, :category, :hours],
          redact_fields: [],
          columns: %{
            id: %{type: :integer},
            booked_at: %{type: :utc_datetime},
            category: %{type: :string},
            hours: %{type: :integer}
          },
          associations: %{}
        },
        schemas: %{},
        joins: %{}
      },
      nil
    )
  end

  describe "group_by_fields/3" do
    setup do
      columns = %{
        "category" => %{colid: :category, type: :string},
        "created_at" => %{colid: :created_at, type: :naive_datetime},
        "custom_field" => %{
          colid: :custom,
          type: :custom_column,
          requires_select: [:field1, :field2]
        }
      }

      {:ok, columns: columns}
    end

    test "processes regular fields", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "category", "index" => "0", "alias" => "Category Name"}
      }

      result = Process.group_by_fields(field_params, columns)

      assert length(result) == 1
      [{col, field_selector}] = result
      assert col.colid == :category
      assert field_selector == {:field, :category, "Category Name"}
    end

    test "processes datetime fields with formatting", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "created_at", "index" => "0", "alias" => "Year", "format" => "YYYY"}
      }

      result = Process.group_by_fields(field_params, columns)

      [{col, field_selector}] = result
      assert col.colid == :created_at

      assert field_selector ==
               {:field, {:datetime_format, :created_at, "YYYY", %{epoch_storage: nil}}, "Year"}
    end

    test "keeps naive datetime grouping unchanged when timezone is present", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "created_at", "index" => "0", "alias" => "Year", "format" => "YYYY"}
      }

      result = Process.group_by_fields(field_params, columns, %{timezone: "America/New_York"})

      [{col, field_selector}] = result
      assert col.colid == :created_at

      assert field_selector ==
               {:field, {:datetime_format, :created_at, "YYYY", %{epoch_storage: nil}}, "Year"}
    end

    test "processes custom columns with requires_select", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "custom_field", "index" => "0", "alias" => "Custom"}
      }

      result = Process.group_by_fields(field_params, columns)

      [{col, field_selector}] = result
      assert col.colid == :custom
      assert field_selector == {:row, [:field1, :field2], "Custom"}
    end

    test "sorts fields by index", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "category", "index" => "1", "alias" => "Second"},
        "2" => %{"field" => "created_at", "index" => "0", "alias" => "First"}
      }

      result = Process.group_by_fields(field_params, columns)

      assert length(result) == 2
      [{first_col, _}, {second_col, _}] = result
      # index 0
      assert first_col.colid == :created_at
      # index 1
      assert second_col.colid == :category
    end

    test "uses field name as default alias", %{columns: columns} do
      field_params = %{
        "1" => %{"field" => "category", "index" => "0", "alias" => ""},
        # no alias key
        "2" => %{"field" => "created_at", "index" => "1"}
      }

      result = Process.group_by_fields(field_params, columns)

      [{_, first_selector}, {_, second_selector}] = result
      assert elem(first_selector, 2) == "category"
      assert elem(second_selector, 2) == "created_at"
    end
  end

  describe "aggregate_fields/2" do
    test "processes aggregate fields with functions" do
      aggregate_params = %{
        "1" => %{
          "field" => "film_count",
          "index" => "0",
          "function" => "count",
          "alias" => "Total Films"
        },
        "2" => %{
          "field" => "revenue",
          "index" => "1",
          "function" => "sum",
          "alias" => "Total Revenue"
        }
      }

      result = Process.aggregate_fields(aggregate_params, %{})

      assert length(result) == 2

      [first_agg, second_agg] = result
      assert first_agg == {:field, {:count, "film_count"}, "Total Films"}
      assert second_agg == {:field, {:sum, "revenue"}, "Total Revenue"}
    end

    test "defaults to count function when not specified" do
      aggregate_params = %{
        "1" => %{"field" => "film_count", "index" => "0", "alias" => "Count"},
        "2" => %{"field" => "revenue", "index" => "1", "function" => "", "alias" => "Revenue"}
      }

      result = Process.aggregate_fields(aggregate_params, %{})

      [first_agg, second_agg] = result
      assert elem(elem(first_agg, 1), 0) == :count
      assert elem(elem(second_agg, 1), 0) == :count
    end

    test "uses field name as default alias" do
      aggregate_params = %{
        "1" => %{"field" => "film_count", "index" => "0", "function" => "count", "alias" => ""},
        # no alias
        "2" => %{"field" => "revenue", "index" => "1", "function" => "sum"}
      }

      result = Process.aggregate_fields(aggregate_params, %{})

      [first_agg, second_agg] = result
      assert elem(first_agg, 2) == "film_count"
      assert elem(second_agg, 2) == "revenue"
    end

    test "sorts aggregates by index" do
      aggregate_params = %{
        "1" => %{"field" => "second", "index" => "1", "function" => "sum", "alias" => "Second"},
        "2" => %{"field" => "first", "index" => "0", "function" => "count", "alias" => "First"}
      }

      result = Process.aggregate_fields(aggregate_params, %{})

      [first_agg, second_agg] = result
      # index 0
      assert elem(first_agg, 2) == "First"
      # index 1
      assert elem(second_agg, 2) == "Second"
    end
  end
end
