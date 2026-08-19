defmodule SelectoComponents.QueryLibraryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Form.QueryLibraryPanel
  alias SelectoComponents.QueryLibrary
  alias SelectoComponents.Theme

  test "named views seed editable detail columns and ordering" do
    view_config = %{
      view_mode: "aggregate",
      views: %{detail: %{selected: [], order_by: []}},
      query_library: %{
        "view" => "active_summaries",
        "parameters" => %{"minimum" => "3"}
      }
    }

    updated = QueryLibrary.apply_preset(view_config, selecto())

    assert updated.view_mode == "detail"

    assert Enum.map(updated.views.detail.selected, fn {_id, field, _config} -> field end) ==
             ["id", "name", "status", "priority"]

    assert Enum.map(updated.views.detail.order_by, fn {_id, field, config} ->
             {field, config["dir"]}
           end) == [{"priority", "desc"}, {"id", "asc"}]

    assert updated.query_library.parameters == %{"minimum" => "3"}
  end

  test "selected view and additional segments apply governed predicates" do
    query =
      QueryLibrary.apply_segments(selecto(), %{
        view: "active_summaries",
        segments: ["named_project"],
        parameters: %{"minimum" => "3", "project_name" => "Apollo"}
      })

    filters = Selecto.Query.query_filters(query, validate_tenant: false)

    assert {:status, "active"} in filters
    assert {:priority, {:gte, 3}} in filters
    assert {:name, "Apollo"} in filters

    assert Selecto.applied_query_library(query).segments == [
             "active",
             "priority_at_least",
             "named_project"
           ]
  end

  test "a materialized view remains editable until another preset is selected" do
    previous = %{
      query_library: %{view: "active_summaries", segments: [], parameters: %{}},
      views: %{detail: %{selected: []}}
    }

    edited = put_in(previous, [:views, :detail, :selected], [{"manual", "name", %{}}])

    assert QueryLibrary.apply_preset_if_changed(edited, selecto(), previous) == edited

    changed = put_in(edited, [:query_library, :view], nil)
    assert QueryLibrary.apply_preset_if_changed(changed, selecto(), previous) == changed
  end

  test "unknown named views and parameters fail before query execution" do
    assert_raise ArgumentError, ~r/unknown query-library view/, fn ->
      QueryLibrary.apply_segments(selecto(), %{view: "missing", parameters: %{}})
    end

    assert_raise ArgumentError, ~r/unknown query-library parameters/, fn ->
      QueryLibrary.apply_segments(selecto(), %{
        segments: ["active"],
        parameters: %{"untrusted" => "value"}
      })
    end
  end

  test "query-library panel renders metadata, governed choices, and typed parameters" do
    html =
      render_component(&QueryLibraryPanel.panel/1, %{
        selecto: selecto(),
        view_config: %{
          query_library: %{
            view: "active_summaries",
            segments: [],
            parameters: %{"minimum" => "7"}
          }
        },
        theme: Theme.default_theme(:light)
      })

    assert html =~ "Active summaries"
    assert html =~ "Reusable active project summary"
    assert html =~ ~s(name="query_library[parameters][minimum]")
    assert html =~ ~s(type="number")
    assert html =~ ~s(value="7")
    assert html =~ "Capability metadata: projects.read"
  end

  defp selecto do
    domain = %{
      name: "QueryLibraryComponentTest",
      source: %{
        source_table: "projects",
        primary_key: :id,
        fields: [:id, :name, :status, :priority],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID"},
          name: %{type: :string, name: "Name"},
          status: %{type: :string, name: "Status"},
          priority: %{type: :integer, name: "Priority"}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{},
      query_library: %{
        segments: %{
          active: %{filters: [{:eq, :status, "active"}]},
          priority_at_least: %{
            filters: [{:gte, :priority, {:param, :minimum}}],
            parameters: %{minimum: %{type: :integer, required: true}}
          },
          named_project: %{
            capability: "projects.read",
            filters: [{:eq, :name, {:param, :project_name}}],
            parameters: %{project_name: %{type: :string, required: true}}
          }
        },
        projections: %{
          identity: %{fields: [:id, :name]},
          summary: %{projections: [:identity], fields: [:status, :priority]}
        },
        orderings: %{
          priority: %{order_by: [{:priority, :desc}, {:id, :asc}]}
        },
        views: %{
          active_summaries: %{
            label: "Active summaries",
            description: "Reusable active project summary",
            segments: [:active, :priority_at_least],
            projection: :summary,
            ordering: :priority
          }
        }
      }
    }

    Selecto.configure(domain, nil)
  end
end
