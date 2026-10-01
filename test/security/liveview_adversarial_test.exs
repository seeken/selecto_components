defmodule SelectoComponents.Security.LiveViewAdversarialTest do
  @moduledoc """
  Adversarial LiveView scenarios from the Selecto adversarial test catalog
  (S4, S8, S16, DOS-01, LEAK-06 and filter-section recursion).

  Each test drives the real planning and execution path with a crafted params
  map or event payload and inspects the SQL that reaches the adapter.
  """

  use ExUnit.Case, async: false

  alias Phoenix.LiveView.Socket
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Components.TreeBuilder
  alias SelectoComponents.Execution.Plan
  alias SelectoComponents.DBSupport
  alias SelectoComponents.ErrorHandling.ErrorBuilder
  alias SelectoComponents.Form
  alias SelectoComponents.Form.ParamsState
  alias SelectoComponents.Helpers.Filters
  alias SelectoComponents.QueryContract
  alias SelectoComponents.Router
  alias SelectoComponents.State
  alias SelectoComponents.Views.Detail.Component, as: DetailComponent
  alias SelectoComponents.Views.Detail.Options, as: DetailOptions
  alias SelectoComponents.Execution.QueryHelpers
  alias SelectoComponents.Views.Aggregate.Options, as: AggregateOptions
  alias SelectoComponents.Views.Detail.Process, as: DetailProcess
  alias SelectoComponents.Views.Map.Process, as: MapProcess

  defmodule CaptureAdapter do
    @moduledoc false
    @behaviour Selecto.DB.Adapter

    @impl true
    def name, do: :capture

    @impl true
    def connect(parent) when is_pid(parent), do: {:ok, parent}

    @impl true
    def execute(parent, query, params, _opts) when is_pid(parent) do
      sql = IO.iodata_to_binary(query)
      send(parent, {:executed_sql, sql, params})

      if String.contains?(String.downcase(sql), "count(*) as total_rows") do
        {:ok, %{rows: [[1]], columns: ["total_rows"]}}
      else
        {:ok, %{rows: [], columns: []}}
      end
    end

    @impl true
    def placeholder(index), do: ["$", Integer.to_string(index)]

    @impl true
    def quote_identifier(identifier) do
      escaped = identifier |> to_string() |> String.replace("\"", "\"\"")
      "\"#{escaped}\""
    end

    @impl true
    def supports?(_feature), do: false
  end

  defp domain do
    %{
      name: "AdversarialLiveView",
      source: %{
        source_table: "films",
        primary_key: :id,
        fields: [:id, :language, :owner_id, :tags, :secret_score],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id, comparators: ["eq"]},
          language: %{type: :string, name: "Language", colid: :language},
          owner_id: %{type: :integer, name: "Owner", colid: :owner_id},
          tags: %{
            type: :string,
            name: "Tags",
            colid: :tags,
            sortable: false,
            comparators: ["eq"]
          },
          secret_score: %{
            type: :integer,
            name: "Secret score",
            colid: :secret_score,
            internal: true,
            filterable: false
          }
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }
  end

  defp host_selecto(opts \\ []) do
    Selecto.configure(domain(), self(), Keyword.merge([adapter: CaptureAdapter], opts))
  end

  defp socket(selecto) do
    %Socket{
      assigns: %{
        __changed__: %{},
        selecto: selecto,
        views: [
          {:detail, SelectoComponents.Views.Detail, "Detail", []},
          {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", []},
          {:graph, SelectoComponents.Views.Graph, "Graph", []}
        ],
        view_config: %{view_mode: "detail", filters: [], views: %{}},
        current_detail_page: 0,
        sort_by: nil,
        last_query_info: %{},
        presentation_context: %{}
      }
    }
  end

  defp detail_params(filters \\ %{}, extra \\ %{}) do
    Map.merge(
      %{
        "view_mode" => "detail",
        "selected" => %{
          "s0" => %{"field" => "id", "index" => "0", "uuid" => "s0"},
          "s1" => %{"field" => "language", "index" => "1", "uuid" => "s1"}
        },
        "filters" => filters
      },
      extra
    )
  end

  defp filter(attrs) do
    Map.merge(%{"uuid" => "f0", "section" => "filters", "index" => "0"}, attrs)
  end

  defp run(params, socket) do
    flush_sql()
    updated = ParamsState.view_from_params(params, socket)
    {updated, flush_sql()}
  end

  defp flush_sql(acc \\ []) do
    receive do
      {:executed_sql, sql, params} -> flush_sql(acc ++ [{sql, params}])
      {:query_executed, _info} -> flush_sql(acc)
    after
      0 -> acc
    end
  end

  defp all_params(executed), do: Enum.flat_map(executed, fn {_sql, params} -> params end)

  defp page_sql(executed) do
    executed
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&String.contains?(String.downcase(&1), "count(*) as total_rows"))
  end

  defp error_codes(%Plan{validation_errors: errors}), do: Enum.map(errors, & &1.code)

  defp bounded(fun) do
    task =
      Task.async(fn ->
        Process.flag(:max_heap_size, %{size: 20_000_000, kill: true, error_logger: false})
        fun.()
      end)

    Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill)
  end

  defp with_app_env(key, value, fun) do
    previous = Application.fetch_env(:selecto_components, key)

    if is_nil(value),
      do: Application.delete_env(:selecto_components, key),
      else: Application.put_env(:selecto_components, key, value)

    try do
      fun.()
    after
      case previous do
        {:ok, old} -> Application.put_env(:selecto_components, key, old)
        :error -> Application.delete_env(:selecto_components, key)
      end
    end
  end

  defp with_os_env(name, value, fun) do
    previous = System.get_env(name)
    if is_nil(value), do: System.delete_env(name), else: System.put_env(name, value)

    try do
      fun.()
    after
      if is_nil(previous), do: System.delete_env(name), else: System.put_env(name, previous)
    end
  end

  defp sqlite_rows(sql, params, rows) do
    inlined =
      Regex.replace(~r/\$(\d+)/, IO.iodata_to_binary(sql), fn _match, index ->
        params |> Enum.at(String.to_integer(index) - 1) |> sqlite_literal()
      end)

    inserts =
      Enum.map_join(rows, "\n", fn row ->
        "INSERT INTO films (language) VALUES (#{sqlite_literal(row)});"
      end)

    path =
      Path.join(System.tmp_dir!(), "selecto_literal_#{System.unique_integer([:positive])}.sql")

    File.write!(path, """
    CREATE TABLE films (id INTEGER PRIMARY KEY, language TEXT, owner_id INTEGER, tags TEXT, secret_score INTEGER);
    #{inserts}
    #{inlined};
    """)

    try do
      {output, 0} = System.cmd("sqlite3", ["-batch", ":memory:", ".read #{path}"], env: [])
      String.split(output, "\n", trim: true)
    after
      File.rm(path)
    end
  end

  defp sqlite_literal(value) when is_binary(value),
    do: "'" <> String.replace(value, "'", "''") <> "'"

  defp sqlite_literal(value) when is_integer(value), do: Integer.to_string(value)

  describe "S4: host scope survives every LiveView re-plan" do
    test "host Selecto.filter and required filters reach the SQL of the first and later runs" do
      host =
        host_selecto()
        |> Selecto.filter({"language", "host-scope-language"})
        |> Selecto.require_tenant_filter({"owner_id", 4242})

      {first, executed} =
        run(
          detail_params(%{"k0" => filter(%{"filter" => "id", "comp" => "=", "value" => "7"})}),
          socket(host)
        )

      assert first.assigns.executed, inspect(first.assigns.execution_error)
      assert executed != []
      assert "host-scope-language" in all_params(executed)
      assert 4242 in all_params(executed)
      assert 7 in all_params(executed)

      {second, executed} = run(detail_params(), first)

      assert second.assigns.executed
      assert "host-scope-language" in all_params(executed)
      assert 4242 in all_params(executed)
      refute 7 in all_params(executed), "a previous run's user filter must not persist"
    end

    test "strict governance mode survives the re-plan" do
      host = host_selecto(mode: :strict)
      assert host.policy.mode == :strict

      plan = Plan.build(detail_params(), socket(host))
      assert plan.selecto.policy.mode == :strict

      {after_run, _executed} = run(detail_params(), socket(host))
      assert after_run.assigns.executed, inspect(after_run.assigns.execution_error)

      replanned = Plan.build(detail_params(), after_run)
      assert replanned.selecto.policy.mode == :strict
    end

    test "a selecto the host assigns after a run becomes the new scope" do
      host_a = Selecto.filter(host_selecto(), {"language", "scope-a"})
      {after_a, _executed} = run(detail_params(), socket(host_a))

      host_b = Selecto.filter(host_selecto(), {"language", "scope-b"})
      rebound = Phoenix.Component.assign(after_a, :selecto, host_b)
      {_after_b, executed} = run(detail_params(), rebound)

      assert "scope-b" in all_params(executed)
      refute "scope-a" in all_params(executed)
    end

    test "scope the host adds to the planned selecto after a run is not dropped" do
      {after_run, _executed} = run(detail_params(), socket(host_selecto()))

      narrowed =
        Phoenix.Component.assign(
          after_run,
          :selecto,
          Selecto.require_tenant_filter(after_run.assigns.selecto, {"owner_id", 99})
        )

      {_updated, executed} = run(detail_params(), narrowed)

      assert 99 in all_params(executed)
    end
  end

  describe "S8: the validated filter key is the executed key" do
    test "a map naming a public field and a non-filterable filter is rejected" do
      params =
        detail_params(%{
          "k0" =>
            filter(%{
              "field" => "language",
              "filter" => "secret_score",
              "comp" => "=",
              "value" => "50"
            })
        })

      plan = Plan.build(params, socket(host_selecto()))
      assert error_codes(plan) != []

      {updated, executed} = run(params, socket(host_selecto()))

      refute updated.assigns.executed
      refute Enum.any?(executed, fn {sql, _params} -> sql =~ "secret_score" end)
    end

    test "an id alias cannot stand in for the executed filter key" do
      params =
        detail_params(%{
          "k0" =>
            filter(%{
              "id" => "language",
              "filter" => "secret_score",
              "comp" => "=",
              "value" => "50"
            })
        })

      {updated, executed} = run(params, socket(host_selecto()))

      refute updated.assigns.executed
      refute Enum.any?(executed, fn {sql, _params} -> sql =~ "secret_score" end)
    end

    test "comparator cannot validate one operator while comp executes another" do
      params =
        detail_params(%{
          "k0" => filter(%{"filter" => "id", "comparator" => "=", "comp" => ">", "value" => "5"})
        })

      {updated, executed} = run(params, socket(host_selecto()))

      refute updated.assigns.executed
      refute Enum.any?(executed, fn {sql, _params} -> sql =~ ~r/"id"\s*>/ end)
    end

    test "the intent validator rejects a filter that names several fields or comparators" do
      selecto = host_selecto()

      fields =
        QueryContract.validate_intent(selecto, %{
          "view_mode" => "detail",
          "filters" => [%{"field" => "language", "filter" => "secret_score", "comparator" => "="}]
        })

      assert :ambiguous_filter_field in Enum.map(fields.errors, & &1.code)

      comparators =
        QueryContract.validate_intent(selecto, %{
          "view_mode" => "detail",
          "filters" => [%{"field" => "id", "comparator" => "=", "comp" => ">"}]
        })

      assert :ambiguous_comparator in Enum.map(comparators.errors, & &1.code)

      agreeing =
        QueryContract.validate_intent(selecto, %{
          "view_mode" => "detail",
          "filters" => [%{"field" => "id", "filter" => "id", "comparator" => "eq", "comp" => "="}]
        })

      assert agreeing.valid?, inspect(agreeing.errors)
    end

    test "a plain filter on a filterable field with an allowed comparator still runs" do
      params =
        detail_params(%{"k0" => filter(%{"filter" => "id", "comp" => "=", "value" => "5"})})

      {updated, executed} = run(params, socket(host_selecto()))

      assert updated.assigns.executed, inspect(updated.assigns.execution_error)
      assert 5 in all_params(executed)
    end
  end

  describe "S16: sorting is limited to sortable contract fields" do
    test "the sort_column event cannot order by an internal column" do
      component_socket = %Socket{assigns: %{__changed__: %{}, sort_by: [], sort_mode: :single}}

      {:noreply, _socket} =
        DetailComponent.handle_event(
          "sort_column",
          %{"column" => "secret_score"},
          component_socket
        )

      assert_received {:rerun_query_with_sort, sort_by}
      assert sort_by == [{"secret_score", :asc}]

      host_socket = socket(host_selecto())
      flush_sql()

      {:noreply, updated} =
        ParamsState.view_from_params_with_sort(detail_params(), host_socket, sort_by)

      executed = flush_sql()

      refute updated.assigns.executed
      refute Enum.any?(page_sql(executed), &(&1 =~ "secret_score"))
    end

    test "a sortable column chosen through sort_column still orders the query" do
      host_socket =
        host_selecto()
        |> socket()
        |> Phoenix.Component.assign(:sort_by, [{"language", :desc}])

      {updated, executed} = run(detail_params(), host_socket)

      assert updated.assigns.executed, inspect(updated.assigns.execution_error)
      assert Enum.any?(page_sql(executed), &(&1 =~ ~r/ORDER BY.*language.*DESC/is))
    end

    test "the intent validator checks sort_by in every view mode" do
      for view_mode <- ["detail", "aggregate", "graph", "map"] do
        result =
          QueryContract.validate_intent(host_selecto(), %{
            "view_mode" => view_mode,
            "sort_by" => [%{"field" => "secret_score", "direction" => "asc"}]
          })

        assert :field_not_sortable in Enum.map(result.errors, & &1.code), view_mode
      end
    end

    test "column headers offer sorting only for contract-sortable fields" do
      selecto = %{
        host_selecto()
        | set: %{
            columns: [
              %{"field" => "id", "alias" => "id", "uuid" => "id-col"},
              %{"field" => "tags", "alias" => "tags", "uuid" => "tags-col"}
            ]
          }
      }

      html =
        render_component(DetailComponent, %{
          id: "adversarial-detail",
          executed: true,
          execution_error: nil,
          selecto: selecto,
          query_results: {[[1, "a"]], [:id, :tags], ["id", "tags"]},
          view_meta: %{page: 0, per_page: 30, total_rows: 1, subselect_configs: []}
        })

      assert html =~ ~r/phx-click="sort_column"[^>]*phx-value-column="id"/
      refute html =~ ~r/phx-click="sort_column"[^>]*phx-value-column="tags"/
      assert html =~ ~s(data-column-id="tags")
    end

    test "a detail order_by param on an internal column is rejected" do
      params =
        detail_params(%{}, %{
          "order_by" => %{
            "o0" => %{"field" => "secret_score", "dir" => "asc", "index" => "0", "uuid" => "o0"}
          }
        })

      {updated, executed} = run(params, socket(host_selecto()))

      refute updated.assigns.executed
      refute Enum.any?(page_sql(executed), &(&1 =~ "secret_score"))
    end
  end

  describe "DOS-01: detail page sizes are capped" do
    test "per_page is capped at the configured maximum" do
      selecto = host_selecto()
      columns = Selecto.columns(selecto)
      params = detail_params(%{}, %{"per_page" => "100000000"})

      {_set, meta} = DetailProcess.view(%{}, params, columns, [], selecto)
      assert meta.per_page == DetailOptions.max_per_page()
      assert DetailOptions.max_per_page() <= 1_000

      assert DetailProcess.param_to_state(params, %{}).per_page ==
               Integer.to_string(DetailOptions.max_per_page())

      with_app_env(:detail_max_per_page, 50, fn ->
        {_set, meta} = DetailProcess.view(%{}, params, columns, [], selecto)
        assert meta.per_page == 50
      end)
    end

    test "max_rows all resolves to a finite, configurable row cap" do
      limit = DetailOptions.normalize_max_rows_limit("all")
      assert is_integer(limit) and limit > 0
      assert limit == DetailOptions.max_rows_cap()

      with_app_env(:detail_max_rows_cap, 5_000, fn ->
        assert DetailOptions.normalize_max_rows_limit("all") == 5_000
        assert DetailOptions.normalize_max_rows_limit("10000") == 5_000
        assert DetailOptions.normalize_max_rows_limit("1000") == 1_000
      end)
    end

    test "a huge per_page with max_rows all never asks the database for unbounded rows" do
      params = detail_params(%{}, %{"per_page" => "100000000", "max_rows" => "all"})

      {updated, executed} = run(params, socket(host_selecto()))

      assert updated.assigns.executed, inspect(updated.assigns.execution_error)

      limits =
        executed
        |> page_sql()
        |> Enum.flat_map(&Regex.scan(~r/LIMIT\s+\$?(\d+)/i, &1))
        |> Enum.map(fn [_match, value] -> String.to_integer(value) end)

      bound_params =
        executed
        |> Enum.reject(fn {sql, _} -> String.contains?(String.downcase(sql), "total_rows") end)
        |> Enum.flat_map(fn {_sql, params} -> params end)
        |> Enum.filter(&is_integer/1)

      assert Enum.all?(limits ++ bound_params, &(&1 <= 3 * DetailOptions.max_per_page() + 1))
    end
  end

  describe "DOS-01: aggregate_per_page all is capped" do
    test "all fetches at most the configured aggregate row cap" do
      query = Selecto.select(host_selecto(), ["language"])

      flush_sql()

      {_result, _meta, _cache} =
        QueryHelpers.execute_query_with_pagination(
          query,
          %{"view_mode" => "aggregate"},
          %{per_page: "all"},
          %{assigns: %{}}
        )

      [{sql, params}] = flush_sql()
      assert sql =~ ~r/\blimit\b/i, "unbounded aggregate query: #{sql}"

      cap = AggregateOptions.max_rows_cap()
      assert cap > 0
      assert cap in params or sql =~ ~r/limit\s+#{cap}\b/i

      with_app_env(:aggregate_max_rows_cap, 250, fn ->
        flush_sql()

        QueryHelpers.execute_query_with_pagination(
          query,
          %{"view_mode" => "aggregate"},
          %{per_page: "all"},
          %{assigns: %{}}
        )

        [{sql, params}] = flush_sql()
        assert 250 in params or sql =~ ~r/limit\s+250\b/i
      end)
    end

    test "all page math never exceeds the cap" do
      with_app_env(:aggregate_max_rows_cap, 250, fn ->
        assert AggregateOptions.per_page_to_int("all", 1_000_000) == 250
        assert AggregateOptions.per_page_to_int("all", 10) == 10
      end)
    end
  end

  describe "map background URLs cannot leave the allowlist" do
    @bypass_urls [
      "/\\evil.example/{z}/{x}/{y}.png",
      "/%5Cevil.example/{z}/{x}/{y}.png",
      "/%5cevil.example/overlay.png",
      "/\t/evil.example/{z}/{x}/{y}.png",
      "/\r\n/evil.example/overlay.png",
      "/%09/evil.example/overlay.png",
      "/%0A/evil.example/overlay.png",
      "/%0d%0a/evil.example/overlay.png",
      "//evil.example/{z}/{x}/{y}.png",
      "\t//evil.example/overlay.png",
      "/tiles/\u0000/x.png",
      "https://{s}.tile.openstreetmap.org\\@evil.example/{z}.png",
      "https://{s}.tile.openstreetmap.org/%5C/{z}.png"
    ]

    test "backslash, control-character and protocol-relative variants are rejected" do
      for url <- @bypass_urls do
        assert MapProcess.normalize_config(%{"tile_url" => url, "image_overlay_url" => url}) ==
                 %{},
               "accepted #{inspect(url)}"

        assert MapProcess.param_to_state(%{"tile_url" => url}, %{}) == %{},
               "param_to_state accepted #{inspect(url)}"
      end
    end

    test "same-origin paths and allowlisted https hosts are still accepted" do
      for url <- [
            "/tiles/{z}/{x}/{y}.png",
            "/overlays/yard.png?v=2",
            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          ] do
        assert MapProcess.normalize_config(%{"tile_url" => url}).tile_url == url
      end
    end
  end

  describe "LEAK-06: error detail follows SelectoComponents.Env" do
    test "an unset MIX_ENV in a release-like runtime sanitizes errors" do
      with_app_env(:environment, nil, fn ->
        with_app_env(:env, :prod, fn ->
          with_os_env("MIX_ENV", nil, fn ->
            refute Form.dev_mode?()

            error =
              Form.build_selecto_error(:query_error, "column secret_score does not exist", %{
                sql: "SELECT secret_score FROM films"
              })

            sanitized = Form.sanitize_error_for_environment(error)
            assert sanitized.debug == %{}
            assert is_nil(sanitized.detail)
          end)
        end)
      end)
    end

    test "an unrecognized :environment value is treated as production" do
      with_app_env(:environment, :staging, fn ->
        refute Form.dev_mode?()
      end)
    end

    test "dev and test environments keep detailed errors" do
      with_app_env(:environment, nil, fn ->
        with_app_env(:env, :dev, fn -> assert Form.dev_mode?() end)
        with_app_env(:env, :test, fn -> assert Form.dev_mode?() end)
      end)

      with_app_env(:environment, :dev, fn -> assert Form.dev_mode?() end)
    end
  end

  describe "filter sections cannot recurse forever" do
    test "a section whose uuid names its own section is refused" do
      filters = %{
        "filters" => [
          %{
            "uuid" => "filters",
            "section" => "filters",
            "is_section" => "Y",
            "conjunction" => "AND"
          }
        ]
      }

      assert {:ok, {:error, _reason}} =
               bounded(fn ->
                 Filters.filter_recurse_strict(host_selecto(), filters, "filters")
               end)

      assert {:ok, []} =
               bounded(fn -> Filters.filter_recurse(host_selecto(), filters, "filters") end)
    end

    test "a two-section cycle is refused" do
      filters = %{
        "filters" => [
          %{"uuid" => "a", "section" => "filters", "is_section" => "Y", "conjunction" => "AND"}
        ],
        "a" => [%{"uuid" => "b", "section" => "a", "is_section" => "Y", "conjunction" => "OR"}],
        "b" => [%{"uuid" => "a", "section" => "b", "is_section" => "Y", "conjunction" => "AND"}]
      }

      assert {:ok, {:error, _reason}} =
               bounded(fn ->
                 Filters.filter_recurse_strict(host_selecto(), filters, "filters")
               end)
    end

    test "a cyclic section in LiveView params blocks execution instead of hanging" do
      params =
        detail_params(%{
          "k0" => %{
            "uuid" => "filters",
            "section" => "filters",
            "is_section" => "Y",
            "conjunction" => "AND",
            "index" => "0"
          }
        })

      assert {:ok, plan} = bounded(fn -> Plan.build(params, socket(host_selecto())) end)
      assert :filter_build_failed in error_codes(plan)
    end

    test "the filter tree builder draws a cyclic section once instead of recursing" do
      assigns = %{
        id: "adversarial-tree",
        available: [{"id", "ID", :integer}],
        filters: [
          {"filters", "filters", "AND"},
          {"a", "filters", "OR"},
          {"b", "a", "AND"},
          {"a", "b", "AND"},
          {"f1", "b", %{"filter" => "id", "comp" => "=", "value" => "1"}}
        ],
        filter_form: [%{inner_block: fn _, _ -> "" end}]
      }

      task =
        Task.async(fn ->
          Process.flag(:max_heap_size, %{size: 20_000_000, kill: true, error_logger: false})
          render_component(TreeBuilder, assigns)
        end)

      Process.unlink(task.pid)

      assert {:ok, html} = Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill)
      assert html =~ ~s(data-filter-row-uuid="f1")
    end

    test "nested sections still build" do
      filters = %{
        "filters" => [
          %{"uuid" => "a", "section" => "filters", "is_section" => "Y", "conjunction" => "OR"}
        ],
        "a" => [
          %{"uuid" => "f1", "section" => "a", "filter" => "id", "comp" => "=", "value" => "1"},
          %{"uuid" => "f2", "section" => "a", "filter" => "id", "comp" => "=", "value" => "2"}
        ]
      }

      assert {:ok, [{:or, [_, _]}]} =
               Filters.filter_recurse_strict(host_selecto(), filters, "filters")
    end
  end

  describe "literal text filters (contains, starts with, ends with)" do
    @literal_value "50%_[a-z]\\!x"
    @escaped_value "50!%!_![a-z]\\!!x"

    defp text_filter_sql(comp, value, extra \\ %{}) do
      selecto = host_selecto()

      filters = %{
        "filters" => [
          Map.merge(
            %{
              "uuid" => "f1",
              "section" => "filters",
              "filter" => "language",
              "comp" => comp,
              "value" => value
            },
            extra
          )
        ]
      }

      {:ok, built} = Filters.filter_recurse_strict(selecto, filters, "filters")

      selecto
      |> Selecto.select(["language"])
      |> then(&%{&1 | set: Map.put(&1.set, :filtered, built)})
      |> Selecto.to_sql()
    end

    test "LIKE metacharacters are escaped with ESCAPE '!' for every text comparator" do
      for {comp, pattern} <- [
            {"CONTAINS", "%" <> @escaped_value <> "%"},
            {"LIKE", "%" <> @escaped_value <> "%"},
            {"STARTS", @escaped_value <> "%"},
            {"ENDS", "%" <> @escaped_value},
            {"NOT LIKE", "%" <> @escaped_value <> "%"}
          ] do
        {sql, params} = text_filter_sql(comp, @literal_value)

        assert sql =~ "ESCAPE '!'", "#{comp}: #{sql}"
        assert pattern in params, "#{comp}: #{inspect(params)}"
      end

      {sql, _params} = text_filter_sql("NOT LIKE", @literal_value)
      assert sql =~ ~r/not\s*\(/i

      {sql, params} = text_filter_sql("CONTAINS", "ab%", %{"ignore_case" => "true"})
      assert sql =~ ~r/upper\(/i
      assert sql =~ "ESCAPE '!'"
      assert "%AB!%%" in params
    end

    @tag skip: is_nil(System.find_executable("sqlite3")) && "sqlite3 CLI not available"
    test "the generated predicates match %, _, [a-z] and \\ literally on SQLite" do
      rows = [
        @literal_value,
        "50XY[a-z]\\!x",
        "50%_a\\!x",
        "50%_[a-z]!x",
        "pre " <> @literal_value <> " post",
        @literal_value <> " tail",
        "head " <> @literal_value,
        "unrelated"
      ]

      checks = [
        {"CONTAINS", &String.contains?(&1, @literal_value)},
        {"STARTS", &String.starts_with?(&1, @literal_value)},
        {"ENDS", &String.ends_with?(&1, @literal_value)},
        {"NOT LIKE", &(not String.contains?(&1, @literal_value))}
      ]

      for {comp, expected?} <- checks do
        {sql, params} = text_filter_sql(comp, @literal_value)

        assert Enum.sort(sqlite_rows(sql, params, rows)) ==
                 rows |> Enum.filter(expected?) |> Enum.sort(),
               "#{comp} on SQLite: #{sql}"
      end
    end

    test "normalized prefix filters refuse LIKE metacharacters instead of guessing an escape" do
      for value <- ["50%", "a_b", "[a-z]", "back\\slash"] do
        assert {:error, _reason} =
                 Filters.filter_recurse_strict(
                   host_selecto(),
                   %{
                     "filters" => [
                       %{
                         "uuid" => "f1",
                         "section" => "filters",
                         "filter" => "language",
                         "comp" => "STARTS",
                         "value" => value,
                         "exclude_articles" => "true"
                       }
                     ]
                   },
                   "filters"
                 ),
               "accepted #{inspect(value)}"
      end
    end
  end

  describe "router URL comparators" do
    defp router_state(filters) do
      host_selecto()
      |> State.init_state([{:detail, SelectoComponents.Views.Detail, "Detail", []}])
      |> Map.put(:view_config, %{
        "selected" => %{"s0" => %{"field" => "language"}},
        view_mode: "detail",
        filters: filters,
        views: %{}
      })
    end

    test "raw LIKE patterns are not accepted from the URL filter surface" do
      for comp <- ["like", "case_insensitive_like"] do
        flush_sql()

        state = router_state([%{"field" => "language", "comp" => comp, "value" => "a%"}])

        assert {:error, error_state} = Router.handle_event("view-apply", %{}, state)
        assert error_state.execution_error
        refute Enum.any?(flush_sql(), fn {_sql, params} -> "a%" in params end)
      end
    end

    test "unknown comparators are rejected instead of becoming equality" do
      for comp <- ["eq", "regex", "~", "ILIKE", "between"] do
        flush_sql()

        state = router_state([%{"field" => "language", "comp" => comp, "value" => "abc"}])

        assert {:error, error_state} = Router.handle_event("view-apply", %{}, state), comp
        assert error_state.execution_error
        assert flush_sql() == [], comp
      end

      flush_sql()
      state = router_state([%{"field" => "language", "comp" => "=", "value" => "abc"}])
      assert {:ok, _state} = Router.handle_event("view-apply", %{}, state)
      assert [{_sql, ["abc"]}] = flush_sql()
    end

    test "contains, starts_with and ends_with match the value literally" do
      for {comp, pattern} <- [
            {"contains", "%a!%!_%"},
            {"starts_with", "a!%!_%"},
            {"ends_with", "%a!%!_"}
          ] do
        flush_sql()
        state = router_state([%{"field" => "language", "comp" => comp, "value" => "a%_"}])

        assert {:ok, _state} = Router.handle_event("view-apply", %{}, state)
        assert [{sql, params}] = flush_sql()
        assert sql =~ "ESCAPE '!'", "#{comp}: #{sql}"
        assert pattern in params, "#{comp}: #{inspect(params)}"
      end
    end
  end

  describe "database error messages" do
    @secrets ["users_email_key", "email", "a@b.example", "ssn", "SELECT"]

    defp leaky_error(category, type \\ :query_error) do
      %Selecto.Error{
        type: type,
        message:
          "duplicate key value violates unique constraint \"users_email_key\" " <>
            "Key (email)=(a@b.example) already exists. SELECT * FROM users",
        details: %{
          category: category,
          constraint: "users_email_key",
          column: if(category == :not_null_violation, do: "ssn", else: "email"),
          recoverable?: true
        }
      }
    end

    defp refute_secrets(text, context) do
      for secret <- @secrets do
        refute is_binary(text) and String.contains?(text, secret),
               "#{context} rendered #{inspect(secret)}: #{inspect(text)}"
      end
    end

    test "format_database_error never renders constraint, column or value text" do
      for category <- [
            :unique_violation,
            :foreign_key_violation,
            :not_null_violation,
            :check_violation,
            :database_error,
            nil
          ],
          type <- [:query_error, :constraint_error] do
        message = DBSupport.format_database_error(leaky_error(category, type))
        assert message != ""
        refute_secrets(message, "#{type}/#{category}")
      end
    end

    test "user-facing error maps for database failures carry no constraint or value text" do
      for raw <- [
            leaky_error(:unique_violation),
            {:error, leaky_error(:unique_violation)},
            leaky_error(:not_null_violation, :constraint_error)
          ] do
        built = ErrorBuilder.build(raw, stage: :db_execute, operation: "view-apply")
        refute_secrets(built.user_message, "user_message")
        refute_secrets(built.detail, "detail")
        refute_secrets(built.summary, "summary")
      end
    end

    defmodule LeakyRawAdapter do
      @moduledoc false
      @behaviour Selecto.DB.Adapter

      @impl true
      def name, do: :leaky

      @impl true
      def connect(conn), do: {:ok, conn}

      @impl true
      def execute(_conn, _query, _params, _opts), do: {:ok, %{rows: [], columns: []}}

      @impl true
      def execute_raw(%{mode: :error}, _query, _params),
        do:
          {:error,
           %{
             message: "duplicate key value violates unique constraint \"users_email_key\"",
             postgres: %{
               code: "23505",
               constraint: "users_email_key",
               detail: "Key (email)=(a@b.example) already exists."
             },
             query: "SELECT * FROM users"
           }}

      def execute_raw(%{mode: :raise}, _query, _params),
        do: raise("users_email_key Key (email)=(a@b.example)")

      @impl true
      def normalize_error(reason) do
        Selecto.Error.query_error(inspect(reason), nil, [], %{
          category: :unique_violation,
          constraint: "users_email_key",
          column: "email"
        })
      end

      @impl true
      def placeholder(index), do: ["$", Integer.to_string(index)]

      @impl true
      def quote_identifier(identifier), do: "\"#{identifier}\""

      @impl true
      def supports?(_feature), do: false
    end

    test "raw count queries return sanitized driver errors" do
      for mode <- [:error, :raise] do
        connection = %{mode: mode, password: "hunter2-secret"}

        selecto =
          Selecto.configure(domain(), connection, adapter: LeakyRawAdapter, validate: false)

        assert {:error, %Selecto.Error{} = error} =
                 DBSupport.execute_raw_query(selecto, "SELECT count(*) FROM films", [])

        rendered = inspect(error)
        refute_secrets(rendered, "raw #{mode} error")
        refute rendered =~ "hunter2-secret"
      end
    end
  end

  describe "core contract defaults" do
    test "an internal field without an explicit filterable flag cannot be filtered" do
      internal_domain =
        put_in(domain(), [:source, :columns, :secret_score], %{
          type: :integer,
          name: "Secret score",
          colid: :secret_score,
          internal: true
        })

      selecto = Selecto.configure(internal_domain, self(), adapter: CaptureAdapter)

      params =
        detail_params(%{
          "k0" => filter(%{"filter" => "secret_score", "comp" => ">", "value" => "50"})
        })

      {updated, executed} = run(params, socket(selecto))

      refute updated.assigns.executed
      refute Enum.any?(executed, fn {sql, _params} -> sql =~ "secret_score" end)
    end
  end

  describe "UI comparators map to contract comparators" do
    @ui_text_comparators [
      "STARTS",
      "ENDS",
      "CONTAINS",
      "LIKE",
      "NOT LIKE",
      "IS NULL",
      "IS_EMPTY",
      "NULL",
      "IS NOT NULL",
      "NOT_NULL",
      "IS_NOT_EMPTY"
    ]

    defp ui_filter_params(field, comp, extra \\ %{}) do
      detail_params(%{
        "k0" => filter(Map.merge(%{"filter" => field, "comp" => comp, "value" => "ab"}, extra))
      })
    end

    test "each UI text comparator executes on a field that allows it" do
      for comp <- @ui_text_comparators do
        {updated, executed} = run(ui_filter_params("language", comp), socket(host_selecto()))

        assert updated.assigns.executed, "#{comp}: #{inspect(updated.assigns.execution_error)}"
        assert Enum.any?(page_sql(executed), &(&1 =~ ~r/where.*language/is)), comp
      end

      plan =
        Plan.build(
          ui_filter_params("language", "TEXT_PREFIX", %{"prefix_length" => "2"}),
          socket(host_selecto())
        )

      refute :invalid_comparator in error_codes(plan)
    end

    test "BETWEEN executes on a field that allows between" do
      params =
        ui_filter_params("owner_id", "BETWEEN", %{"value_start" => "3", "value_end" => "9"})

      {updated, executed} = run(params, socket(host_selecto()))

      assert updated.assigns.executed, inspect(updated.assigns.execution_error)
      assert 3 in all_params(executed) and 9 in all_params(executed)
    end

    test "a field whose contract does not allow the mapped comparator still refuses it" do
      refusals =
        Enum.map(@ui_text_comparators ++ ["TEXT_PREFIX"], &{"tags", &1}) ++
          [{"id", "BETWEEN"}, {"id", "IS NULL"}, {"owner_id", "LIKE"}, {"owner_id", "STARTS"}]

      for {field, comp} <- refusals do
        params = ui_filter_params(field, comp, %{"value_start" => "1", "value_end" => "2"})

        assert :invalid_comparator in error_codes(Plan.build(params, socket(host_selecto()))),
               "#{field} #{comp}"

        {updated, _executed} = run(params, socket(host_selecto()))
        refute updated.assigns.executed, "#{field} #{comp}"
      end
    end

    test "an internal field is still refused for every text comparator" do
      for comp <- ["LIKE", "NOT LIKE", "STARTS", "CONTAINS", "IS NULL"] do
        {updated, executed} = run(ui_filter_params("secret_score", comp), socket(host_selecto()))

        refute updated.assigns.executed, comp
        refute Enum.any?(executed, fn {sql, _params} -> sql =~ "secret_score" end), comp
      end
    end

    test "NOT LIKE and contains agree for ambiguity but not with a different comparator" do
      agreeing =
        QueryContract.validate_intent(host_selecto(), %{
          "view_mode" => "detail",
          "filters" => [%{"field" => "language", "comparator" => "contains", "comp" => "LIKE"}]
        })

      assert agreeing.valid?, inspect(agreeing.errors)

      negated =
        QueryContract.validate_intent(host_selecto(), %{
          "view_mode" => "detail",
          "filters" => [
            %{"field" => "language", "comparator" => "contains", "comp" => "NOT LIKE"}
          ]
        })

      assert :ambiguous_comparator in Enum.map(negated.errors, & &1.code)
    end
  end
end
