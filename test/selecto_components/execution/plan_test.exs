defmodule SelectoComponents.Execution.PlanTest do
  use ExUnit.Case, async: true

  alias Phoenix.Component
  alias SelectoComponents.Execution.Executor
  alias SelectoComponents.Execution.Plan
  alias SelectoComponents.QueryContract

  test "build returns execution-ready plan with runtime presentation context" do
    socket =
      base_socket()
      |> Component.assign(:presentation_context, %{timezone: "America/New_York"})

    plan = Plan.build(%{"view_mode" => "detail", "selected" => %{}}, socket)

    assert plan.selected_view == :detail
    assert plan.params["_presentation_context"]["timezone"] == nil
    assert plan.params["_presentation_context"].timezone == "America/New_York"
    assert is_map(plan.columns_map)
    assert is_list(plan.columns_list)
    assert plan.view_tuple |> elem(0) == :detail
  end

  test "build applies requested sort to the planned selecto" do
    socket =
      base_socket()
      |> Component.assign(:sort_by, [{"id", :desc}])

    plan =
      Plan.build(
        %{
          "view_mode" => "detail",
          "selected" => %{"k0" => %{"field" => "id", "index" => "0", "uuid" => "d1"}}
        },
        socket
      )

    assert Map.get(plan.selecto.set, :order_by, []) == [{:desc, "id"}]
  end

  test "build keeps the configured source for joined selections" do
    socket =
      base_socket()
      |> Component.assign(:selecto, joined_selecto())

    plan =
      Plan.build(
        %{
          "view_mode" => "detail",
          "selected" => %{
            "k0" => %{"field" => "customer.name", "index" => "0", "uuid" => "d1"}
          }
        },
        socket
      )

    refute Selecto.Retarget.has_retarget?(plan.selecto)
    assert {:field, "customer.name", "customer.name"} in Map.get(plan.selecto.set, :selected, [])
  end

  test "build preserves server-attached tenant context and required scope" do
    selecto =
      tenant_selecto()
      |> Selecto.with_tenant(%{tenant_id: 42, required: true})
      |> Selecto.apply_tenant_scope()

    socket = Component.assign(base_socket(), :selecto, selecto)

    plan =
      Plan.build(
        %{
          "view_mode" => "detail",
          "selected" => %{
            "k0" => %{"field" => "id", "index" => "0", "uuid" => "d1"}
          }
        },
        socket
      )

    assert Selecto.tenant(plan.selecto).tenant_id == 42
    assert {"tenant_id", 42} in Selecto.required_filters(plan.selecto)

    {sql, params} = Selecto.to_sql(plan.selecto)
    assert sql =~ "tenant_id"
    assert 42 in params
  end

  test "build normalizes unknown view mode to safe default" do
    plan = Plan.build(%{"view_mode" => "missing_view"}, base_socket())

    assert plan.selected_view == :detail
    assert elem(plan.view_tuple, 0) == :detail
  end

  test "server query contract rejects a filter hidden by the UI policy" do
    socket = base_socket()

    assert {:ok, contract, _diagnostics} = QueryContract.json_document(socket.assigns.selecto)

    contract =
      update_in(contract["fields"], fn fields ->
        Enum.map(fields, fn
          %{"id" => "language"} = field ->
            field
            |> Map.put("filterable", false)
            |> Map.put("comparators", [])

          field ->
            field
        end)
      end)

    socket = Component.assign(socket, :query_contract, contract)
    plan = Plan.build(filter_params("language", "=", "English"), socket)

    assert Enum.any?(plan.validation_errors, &(&1.code == :field_not_filterable))

    result = Executor.run(plan, socket)
    refute result.executed
    assert result.execution_error
  end

  test "a filter build error blocks execution instead of widening the query" do
    socket = base_socket()
    plan = Plan.build(filter_params("missing_field", "=", "restricted"), socket)

    assert Enum.any?(plan.validation_errors, &(&1.code == :invalid_field))
    assert Enum.any?(plan.validation_errors, &(&1.code == :filter_build_failed))

    result = Executor.run(plan, socket)
    refute result.executed
    assert result.execution_error
  end

  test "build keeps query-library segments alongside visual filters" do
    socket =
      base_socket()
      |> Component.assign(:selecto, query_library_selecto())

    plan =
      Plan.build(
        filter_params("language", "=", "English")
        |> Map.put("query_library", %{
          "segments" => ["released_after"],
          "parameters" => %{"year" => "2000"}
        }),
        socket
      )

    assert {:release_year, {:gte, 2000}} in plan.selecto.set.filtered
    assert {"language", "English"} in plan.selecto.set.filtered
    assert Selecto.applied_query_library(plan.selecto).segments == ["released_after"]
  end

  defp base_socket do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selecto: selecto(),
        views: [
          {:detail, SelectoComponents.Views.Detail, "Detail", []},
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", []},
          {:graph, SelectoComponents.Views.Graph, "Graph", []}
        ],
        view_config: %{view_mode: "detail", filters: [], views: %{}},
        current_detail_page: 0,
        sort_by: nil,
        presentation_context: %{}
      }
    }
  end

  defp selecto do
    domain = %{
      name: "ExecutionPlanTest",
      source: %{
        source_table: "films",
        primary_key: :id,
        fields: [:id, :language],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          language: %{type: :string, name: "Language", colid: :language}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }

    Selecto.configure(domain, nil)
  end

  defp joined_selecto do
    domain = %{
      name: "ExecutionPlanJoinedTest",
      source: %{
        source_table: "orders",
        primary_key: :id,
        fields: [:id, :customer_id],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          customer_id: %{type: :integer, name: "Customer ID", colid: :customer_id}
        },
        associations: %{
          customer: %{
            queryable: :customers,
            field: :customer,
            owner_key: :customer_id,
            related_key: :id
          }
        }
      },
      schemas: %{
        customers: %{
          source_table: "customers",
          primary_key: :id,
          fields: [:id, :name],
          redact_fields: [],
          columns: %{
            id: %{type: :integer, name: "ID", colid: :id},
            name: %{type: :string, name: "Name", colid: :name}
          },
          associations: %{}
        }
      },
      joins: %{customer: %{type: :left}}
    }

    Selecto.configure(domain, nil)
  end

  defp tenant_selecto do
    domain = %{
      name: "ExecutionPlanTenantTest",
      tenant_required: true,
      source: %{
        source_table: "work_items",
        primary_key: :id,
        fields: [:id, :tenant_id],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          tenant_id: %{type: :integer, name: "Tenant ID", colid: :tenant_id}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }

    Selecto.configure(domain, nil)
  end

  defp query_library_selecto do
    domain = %{
      name: "ExecutionPlanQueryLibraryTest",
      source: %{
        source_table: "films",
        primary_key: :id,
        fields: [:id, :language, :release_year],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          language: %{type: :string, name: "Language", colid: :language},
          release_year: %{type: :integer, name: "Release year", colid: :release_year}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{},
      query_library: %{
        segments: %{
          released_after: %{
            filters: [{:gte, :release_year, {:param, :year}}],
            parameters: %{year: %{type: :integer, required: true}}
          }
        }
      }
    }

    Selecto.configure(domain, nil)
  end

  defp filter_params(field, comparator, value) do
    %{
      "view_mode" => "detail",
      "selected" => %{},
      "filters" => %{
        "k0" => %{
          "uuid" => "f0",
          "section" => "filters",
          "filter" => field,
          "comp" => comparator,
          "value" => value,
          "index" => "0"
        }
      }
    }
  end
end
