defmodule SelectoComponents.TemplateSourceExecutorTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateSourceExecutor

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/order-browser.compile.json",
             __DIR__
           )
  @nested_fixture Path.expand(
                    "../../../selecto-protocol/spec/fixtures/templates/order-lines-top-n.compile.json",
                    __DIR__
                  )
  @filtered_fixture Path.expand(
                      "../../../selecto-protocol/spec/fixtures/templates/order-filtered-total.compile.json",
                      __DIR__
                    )
  @page_filtered_fixture Path.expand(
                           "../../../selecto-protocol/spec/fixtures/templates/order-page-filtered-total.compile.json",
                           __DIR__
                         )
  @related_totals_fixture Path.expand(
                            "../../../selecto-protocol/spec/fixtures/templates/order-related-source-totals.compile.json",
                            __DIR__
                          )
  @root_page_fixture Path.expand(
                       "../../../selecto-protocol/spec/fixtures/templates/order-root-page.compile.json",
                       __DIR__
                     )

  defmodule Adapter do
    @behaviour Selecto.DB.Adapter

    @impl true
    def name, do: :template_source_executor_test

    @impl true
    def connect(pid), do: {:ok, pid}

    @impl true
    def execute(pid, sql, params, opts) do
      send(pid, {:template_query, sql, params, opts})

      {:ok,
       %{
         rows: [[1, "PO-100", "2026-09-21T12:00:00Z", "open", 44]],
         columns: ["id", "order_number", "ordered_at", "status", "customer_id"]
       }}
    end

    @impl true
    def placeholder(index), do: "$#{index}"

    @impl true
    def quote_identifier(identifier), do: ~s("#{identifier}")

    @impl true
    def supports?(_feature), do: false
  end

  test "resolves source intent server-side and obtains fresh scoped authority" do
    manifest = manifest()
    effect = effect(manifest, "PO-100")
    parent = self()

    authorize = fn source, received_effect ->
      send(parent, {:authorized, source["id"], received_effect["generation"]})

      selecto =
        domain()
        |> Selecto.configure(parent, adapter: Adapter, validate: false)
        |> Selecto.with_tenant(%{tenant_id: 7, required: true})
        |> Selecto.apply_tenant_scope()
        |> Selecto.filter({"status", "open"})

      {:ok, selecto}
    end

    assert {:ok, rows} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute_options: [analyze_complexity: false]
             )

    assert_receive {:authorized, "orders", 1}
    assert_receive {:template_query, sql, params, _adapter_opts}
    assert sql =~ "selecto_root.tenant_id"
    assert 7 in params
    assert "open" in params
    assert "PO-100" in params

    assert rows == [
             %{
               "id" => 1,
               "order_number" => "PO-100",
               "ordered_at" => "2026-09-21T12:00:00Z",
               "status" => "open",
               "customer" => %{"id" => 44}
             }
           ]
  end

  test "root continuation resolves only a scoped server-held token after fresh authorization" do
    manifest =
      @root_page_fixture
      |> File.read!()
      |> Jason.decode!()
      |> update_in(["sources", Access.at(0), "query"], &Map.delete(&1, "page"))

    source = hd(manifest["sources"])
    effect = effect(manifest, "")
    secret = String.duplicate("r", 32)

    scope = %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "orders-v1"
    }

    parent = self()

    authorize = fn _source, _effect ->
      send(parent, :root_authorized)
      {:ok, authorized_query() |> Selecto.filter({"status", "open"}), scope}
    end

    assert {:ok, %{"rows" => first_rows, "root_page" => first_page}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: :first,
               execute: fn query, _opts ->
                 send(parent, {:root_first_query, query})
                 {:ok, {[[1, "PO-100"], [2, "PO-200"], [3, "PO-300"]], [], []}}
               end
             )

    assert_receive :root_authorized
    assert_receive {:root_first_query, first_query}
    assert first_query.set.limit == 3
    assert Enum.map(first_rows, & &1["id"]) == [1, 2]
    assert first_page["has_more"] == true
    assert first_page["after_values"] == [2]

    snapshot = %{
      "instance_id" => "source-executor-instance",
      "release_id" => "source-executor-release",
      "template_fingerprint" => manifest["template"]["fingerprint"],
      "inputs" => effect["bindings"]["input"],
      "state" => effect["bindings"]["state"],
      "sources" => %{
        source["id"] => %{
          "status" => "ready",
          "generation" => effect["generation"],
          "result" => %{"rows" => first_rows, "root_page" => first_page}
        }
      }
    }

    assert {:ok, %{"token" => token}} =
             SelectoComponents.TemplateRootCursor.issue(
               snapshot,
               source["id"],
               source,
               scope,
               secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert {:ok, %{"rows" => next_rows, "root_page" => next_page}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: token,
               root_snapshot: snapshot,
               root_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn query, _opts ->
                 send(parent, {:root_next_query, query})
                 {:ok, {[[3, "PO-300"], [4, "PO-400"]], [], []}}
               end
             )

    assert_receive :root_authorized
    assert_receive {:root_next_query, next_query}
    assert next_query.set.limit == 3
    {sql, params} = Selecto.to_sql(next_query)
    assert sql =~ "selecto_root.id >"
    assert 2 in params
    assert "open" in params
    assert 7 in params
    assert Enum.map(next_rows, & &1["id"]) == [3, 4]
    assert next_page["has_more"] == false
    assert next_page["after_values"] == nil

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: token <> "forged",
               root_snapshot: snapshot,
               root_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn _query, _opts -> flunk("forged root token must not execute") end
             )

    assert_receive :root_authorized

    changed = put_in(snapshot, ["state", "search"], "changed")

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: token,
               root_snapshot: changed,
               root_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn _query, _opts -> flunk("changed state must not execute") end
             )

    assert_receive :root_authorized
  end

  test "root lookahead does not expose nested page positions from the hidden root" do
    manifest =
      nested_manifest()
      |> put_in(["sources", Access.at(0), "query", "limit"], 1)
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "page_size"], 1)
      |> put_in(
        ["sources", Access.at(0), "query", "collections", Access.at(0), "primary_key"],
        "id"
      )

    effect = effect(manifest, "")

    authorize = fn _source, _effect ->
      {:ok, nested_authorized_query() |> Selecto.filter({"status", "open"})}
    end

    lines = fn id ->
      Jason.encode!([
        %{"id" => id, "sku" => "A", "quantity" => 1, "allocations" => []},
        %{"id" => id + 1, "sku" => "B", "quantity" => 1, "allocations" => []}
      ])
    end

    assert {:ok, %{"rows" => [root], "pages" => pages, "identities" => identities}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: :first,
               execute: fn _query, _opts ->
                 {:ok, {[[1, "PO-1", lines.(11)], [2, "PO-2", lines.(21)]], [], []}}
               end
             )

    assert root["id"] == 1
    assert Enum.map(root["lines"], & &1["id"]) == [11]
    assert Enum.map(pages, & &1["parent_path"]) == [[1]]
    assert Enum.map(identities, & &1["parent_path"]) == [[1]]
  end

  test "root continuation calculates page-related totals on its seek window" do
    manifest =
      @related_totals_fixture
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["sources", Access.at(0), "query", "limit"], 1)

    source = hd(manifest["sources"])
    effect = effect(manifest, "PO")
    secret = String.duplicate("r", 32)

    scope = %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "orders-v1"
    }

    authorize = fn _source, _effect ->
      {:ok, nested_authorized_query() |> Selecto.filter({"status", "open"}), scope}
    end

    assert {:ok, %{"rows" => [%{"id" => 1} = first_row], "root_page" => first_page}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: :first,
               resource_budget: %{max_source_statements: 5},
               execute_snapshot: fn _page, _totals, _opts ->
                 {:ok,
                  {[[1, "PO-1", "[]"], [2, "PO-2", "[]"]],
                   %{
                     "page_quantity" => "2",
                     "filtered_quantity" => "9",
                     "page_line_count" => 1,
                     "filtered_line_count" => 4
                   }}}
               end
             )

    snapshot = %{
      "instance_id" => "source-executor-instance",
      "release_id" => "source-executor-release",
      "template_fingerprint" => manifest["template"]["fingerprint"],
      "inputs" => effect["bindings"]["input"],
      "state" => effect["bindings"]["state"],
      "sources" => %{
        source["id"] => %{
          "status" => "ready",
          "generation" => effect["generation"],
          "result" => %{"rows" => [first_row], "root_page" => first_page}
        }
      }
    }

    assert {:ok, %{"token" => token}} =
             SelectoComponents.TemplateRootCursor.issue(
               snapshot,
               source["id"],
               source,
               scope,
               secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert {:ok, %{"rows" => [%{"id" => 2}], "totals" => next_totals}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: token,
               root_snapshot: snapshot,
               root_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               resource_budget: %{max_source_statements: 5},
               execute_snapshot: fn _page, totals, _opts ->
                 for id <- ~w(page_quantity page_line_count) do
                   {sql, params} = Selecto.to_sql(totals[id].query)
                   assert sql =~ "selecto_root.id >"
                   assert 1 in params
                 end

                 for id <- ~w(filtered_quantity filtered_line_count) do
                   {sql, _params} = Selecto.to_sql(totals[id].query)
                   refute sql =~ "selecto_root.id >"
                 end

                 {:ok,
                  {[[2, "PO-2", "[]"]],
                   %{
                     "page_quantity" => "4",
                     "filtered_quantity" => "9",
                     "page_line_count" => 2,
                     "filtered_line_count" => 4
                   }}}
               end
             )

    assert next_totals == %{
             "page_quantity" => "4",
             "filtered_quantity" => "9",
             "page_line_count" => 2,
             "filtered_line_count" => 4
           }
  end

  test "root cursor counts only visible page rows while filtered total keeps full membership" do
    manifest =
      @page_filtered_fixture
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["sources", Access.at(0), "query", "limit"], 2)

    effect = effect(manifest, "PO")

    authorize = fn _source, _effect ->
      {:ok, nested_authorized_query() |> Selecto.filter({"status", "open"})}
    end

    assert {:ok,
            %{
              "rows" => [%{"id" => 1}, %{"id" => 2}],
              "totals" => %{"page_count" => 2, "order_count" => 3},
              "root_page" => %{"has_more" => true, "after_values" => [2]}
            }} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               root_cursor: :first,
               execute_snapshot: fn _page, %{"order_count" => _count}, _opts ->
                 {:ok, {[[1, "PO-1"], [2, "PO-2"], [3, "PO-3"]], %{"order_count" => 3}}}
               end
             )
  end

  test "declared source total requires one host snapshot and remains outside rows" do
    manifest = @filtered_fixture |> File.read!() |> :json.decode()
    effect = effect(manifest, "PO-100")

    authorize = fn _source, _effect ->
      {:ok,
       nested_authorized_query()
       |> Selecto.filter({"status", "open"})
       |> Selecto.limit(1)}
    end

    assert {:error, %{"code" => "source_snapshot_unavailable"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize)

    parent = self()

    snapshot = fn page_query, count_queries, opts ->
      send(parent, {:snapshot_queries, page_query, count_queries, opts[:statement_roles]})
      {:ok, {[[1, "PO-100"]], %{"order_count" => 2}}}
    end

    assert {:error, %{"code" => "source_budget_exceeded"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_source_statements: 1},
               execute_snapshot: fn _page, _counts, _opts ->
                 flunk("two-statement source must be rejected before execution")
               end
             )

    assert {:ok,
            %{
              "rows" => [%{"id" => 1, "order_number" => "PO-100"}],
              "totals" => %{"order_count" => 2}
            }} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute_snapshot: snapshot
             )

    assert_receive {:snapshot_queries, page_query, %{"order_count" => count_query},
                    ["page", "filtered_total:order_count"]}

    assert page_query.set.limit == 1
    refute Map.has_key?(count_query.set, :limit)
    assert Selecto.required_filters(count_query) == Selecto.required_filters(page_query)
    assert Selecto.query_filters(count_query) == Selecto.query_filters(page_query)
  end

  test "page count shares the page statement and combines with a filtered snapshot count" do
    manifest = @page_filtered_fixture |> File.read!() |> :json.decode()
    effect = effect(manifest, "PO-100")

    authorize = fn _source, _effect ->
      {:ok, nested_authorized_query() |> Selecto.filter({"status", "open"}) |> Selecto.limit(1)}
    end

    parent = self()

    assert {:ok, %{"rows" => [_], "totals" => %{"page_count" => 1, "order_count" => 3}}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute_snapshot: fn _page, counts, opts ->
                 send(parent, {:total_roles, Map.keys(counts), opts[:statement_roles]})
                 {:ok, {[[1, "PO-100"]], %{"order_count" => 3}}}
               end
             )

    assert_receive {:total_roles, ["order_count"], ["page", "filtered_total:order_count"]}

    page_only =
      update_in(manifest, ["sources", Access.at(0), "query", "source_totals"], fn totals ->
        Enum.filter(totals, &(&1["scope"] == "page"))
      end)

    assert {:ok, %{"rows" => [_], "totals" => %{"page_count" => 1}}} =
             TemplateSourceExecutor.execute(page_only, effect, authorize,
               resource_budget: %{max_source_statements: 1},
               execute: fn _query, _opts -> {:ok, {[[1, "PO-100"]], [], []}} end
             )
  end

  test "related source totals reserve one snapshot statement each" do
    manifest = @related_totals_fixture |> File.read!() |> :json.decode()
    effect = effect(manifest, "PO-100")

    authorize = fn _source, _effect ->
      {:ok, nested_authorized_query() |> Selecto.filter({"status", "open"}) |> Selecto.limit(1)}
    end

    assert {:error, %{"code" => "source_budget_exceeded"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_source_statements: 4},
               execute_snapshot: fn _page, _totals, _opts ->
                 flunk("budget must reject before read")
               end
             )

    parent = self()
    lines = Jason.encode!([%{"id" => 11, "sku" => "A", "quantity" => 2}])

    assert {:ok,
            %{
              "rows" => [%{"id" => 1, "lines" => [%{"id" => 11}]}],
              "totals" => %{
                "page_quantity" => "3",
                "filtered_quantity" => "7",
                "page_line_count" => 2,
                "filtered_line_count" => 3
              }
            }} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_source_statements: 5},
               execute_snapshot: fn page, totals, opts ->
                 send(parent, {:related_total_queries, page, totals, opts[:statement_roles]})

                 {:ok,
                  {[[1, "PO-100", lines]],
                   %{
                     "page_quantity" => "3",
                     "filtered_quantity" => "7",
                     "page_line_count" => 2,
                     "filtered_line_count" => 3
                   }}}
               end
             )

    assert_receive {:related_total_queries, page, totals,
                    [
                      "page",
                      "filtered_total:filtered_line_count",
                      "filtered_total:filtered_quantity",
                      "page_total:page_line_count",
                      "page_total:page_quantity"
                    ]}

    assert page.set.limit == 1

    assert Enum.sort(Map.keys(totals)) ==
             ["filtered_line_count", "filtered_quantity", "page_line_count", "page_quantity"]

    refute Map.has_key?(totals["filtered_quantity"].query.set, :limit)
    assert totals["page_quantity"].query.set.limit == 1
  end

  test "rejects unknown effects before asking the host for authority" do
    authorize = fn _source, _effect -> flunk("authorization must not run") end
    unknown = Map.put(effect(manifest(), ""), "source", "missing")

    assert {:error, error} = TemplateSourceExecutor.execute(manifest(), unknown, authorize)
    assert error["code"] == "unknown_source"
  end

  test "bounds authorization and execution failures" do
    manifest = manifest()
    effect = effect(manifest, "PO-100")

    assert {:error, authorization_error} =
             TemplateSourceExecutor.execute(manifest, effect, fn _source, _effect ->
               {:error, %{token: "must-not-escape"}}
             end)

    assert authorization_error["code"] == "source_authorization_failed"
    refute inspect(authorization_error) =~ "must-not-escape"

    authorize = fn _source, _effect -> {:ok, authorized_query()} end

    assert {:error, execution_error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute: fn _query, _opts -> {:error, %{password: "must-not-escape"}} end
             )

    assert execution_error["code"] == "source_execution_failed"
    refute inspect(execution_error) =~ "must-not-escape"
  end

  test "host row and result-node budgets reject a source before database execution" do
    manifest = manifest()
    effect = effect(manifest, "")
    authorize = fn _source, _effect -> {:ok, authorized_query()} end
    execute = fn _query, _opts -> flunk("over-budget query must not execute") end

    for budget <- [%{max_root_rows: 10}, %{max_result_nodes: 10}] do
      assert {:error, error} =
               TemplateSourceExecutor.execute(manifest, effect, authorize,
                 resource_budget: budget,
                 execute: execute
               )

      assert error["code"] == "source_budget_exceeded"
    end

    assert {:error, error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_root_rows: 0},
               execute: execute
             )

    assert error["code"] == "invalid_source_budget"
  end

  test "an oversized source effect is rejected before host authorization" do
    manifest = manifest()
    effect = effect(manifest, String.duplicate("x", 200))

    assert {:error, error} =
             TemplateSourceExecutor.execute(
               manifest,
               effect,
               fn _source, _effect -> flunk("oversized input must not reach authorization") end,
               resource_budget: %{max_input_bytes: 100}
             )

    assert error["code"] == "source_input_too_large"
  end

  test "the host's narrower root limit is used for budget admission" do
    manifest = manifest()
    effect = effect(manifest, "")

    authorize = fn _source, _effect ->
      {:ok, authorized_query() |> Selecto.limit(5)}
    end

    assert {:ok, []} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_root_rows: 5, max_result_nodes: 5},
               execute: fn query, _opts ->
                 assert query.set.limit == 5
                 {:ok, {[], [], []}}
               end
             )

    assert {:error, error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_root_rows: 10, max_result_nodes: 10},
               execute: fn _query, _opts ->
                 rows = for id <- 1..6, do: [id, "PO-#{id}", "2026-09-21", "open", 44]
                 {:ok, {rows, [], []}}
               end
             )

    assert error["code"] == "source_budget_exceeded"
  end

  test "a projected result exceeding the host byte budget is not returned" do
    manifest = manifest()
    effect = effect(manifest, "")
    authorize = fn _source, _effect -> {:ok, authorized_query()} end

    assert {:error, error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_result_bytes: 80},
               execute: fn _query, _opts ->
                 {:ok, {[[1, String.duplicate("x", 200), "2026-09-21", "open", 44]], [], []}}
               end
             )

    assert error["code"] == "source_result_too_large"
  end

  test "the two-level top-N fixture has a finite host-owned node and depth budget" do
    manifest = nested_manifest()

    effect =
      manifest
      |> effect("PO-100")
      |> put_in(["bindings", "state", "warehouse"], "A1")

    authorize = fn _source, _effect -> {:ok, nested_authorized_query()} end
    parent = self()

    execute = fn _query, _opts ->
      send(parent, :nested_query_executed)
      {:ok, {[], [], []}}
    end

    assert {:ok, []} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               resource_budget: %{max_result_nodes: 30, max_collection_depth: 2},
               execute: execute
             )

    assert_receive :nested_query_executed

    for budget <- [%{max_result_nodes: 29}, %{max_collection_depth: 1}] do
      assert {:error, error} =
               TemplateSourceExecutor.execute(manifest, effect, authorize,
                 resource_budget: budget,
                 execute: execute
               )

      assert error["code"] == "source_budget_exceeded"
      refute_receive :nested_query_executed
    end

    unbounded =
      update_in(manifest, ["sources", Access.at(0), "query", "collections"], fn
        [collection] -> [Map.delete(collection, "max_items")]
      end)

    assert {:error, error} =
             TemplateSourceExecutor.execute(unbounded, effect, authorize, execute: execute)

    assert error["code"] == "unbounded_collection"
    refute_receive :nested_query_executed

    excess_lines = [
      %{"id" => 11, "sku" => "A", "quantity" => 2, "allocations" => []},
      %{"id" => 12, "sku" => "B", "quantity" => 1, "allocations" => []}
    ]

    assert {:error, error} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute: fn _query, _opts ->
                 {:ok, {[[1, "PO-100", Jason.encode!(excess_lines)]], [], []}}
               end
             )

    assert error["code"] == "source_budget_exceeded"
  end

  test "candidate nested first pages carry internal positions within the result byte budget" do
    manifest =
      nested_manifest()
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "page_size"], 1)
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "max_items"], 2)
      |> put_in(
        ["sources", Access.at(0), "query", "collections", Access.at(0), "primary_key"],
        "id"
      )
      |> put_in(
        [
          "sources",
          Access.at(0),
          "query",
          "collections",
          Access.at(0),
          "collections",
          Access.at(0),
          "page_size"
        ],
        1
      )
      |> put_in(
        [
          "sources",
          Access.at(0),
          "query",
          "collections",
          Access.at(0),
          "collections",
          Access.at(0),
          "max_items"
        ],
        2
      )
      |> put_in(
        [
          "sources",
          Access.at(0),
          "query",
          "collections",
          Access.at(0),
          "collections",
          Access.at(0),
          "primary_key"
        ],
        "id"
      )

    effect =
      nested_manifest()
      |> effect("PO-100")
      |> put_in(["bindings", "state", "warehouse"], "A1")

    rows = [
      [
        1,
        "PO-100",
        [
          %{
            "id" => 11,
            "sku" => "A",
            "quantity" => 2,
            "allocations" => [
              %{"id" => 111, "warehouse" => "A1", "quantity" => 1},
              %{"id" => 110, "warehouse" => "A1", "quantity" => 1}
            ]
          },
          %{"id" => 12, "sku" => "B", "quantity" => 1, "allocations" => []}
        ]
      ]
    ]

    authorize = fn _source, _effect -> {:ok, nested_authorized_query()} end

    execute = fn _query, _opts -> {:ok, {rows, [], []}} end

    assert {:ok, %{"rows" => public_rows, "pages" => pages} = result} =
             TemplateSourceExecutor.execute(manifest, effect, authorize, execute: execute)

    assert public_rows == [
             %{
               "id" => 1,
               "order_number" => "PO-100",
               "lines" => [
                 %{
                   "id" => 11,
                   "sku" => "A",
                   "quantity" => 2,
                   "allocations" => [
                     %{"id" => 111, "warehouse" => "A1", "quantity" => 1}
                   ]
                 }
               ]
             }
           ]

    assert Enum.map(pages, &{&1["parent_path"], &1["has_more"]}) == [
             {[1], true},
             {[1, 11], true}
           ]

    assert Enum.map(result["identities"], &{&1["parent_path"], &1["row_keys"]}) == [
             {[1], [11]},
             {[1, 11], [111]}
           ]

    source = hd(manifest["sources"])

    scope = %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "open-orders-v1"
    }

    secret = String.duplicate("s", 32)

    snapshot = %{
      "instance_id" => "source-executor-instance",
      "release_id" => "source-executor-release",
      "template_fingerprint" => manifest["template"]["fingerprint"],
      "inputs" => effect["bindings"]["input"],
      "state" => effect["bindings"]["state"],
      "sources" => %{
        source["id"] => %{"status" => "ready", "generation" => 1, "result" => result}
      }
    }

    assert {:ok, issued} =
             SelectoComponents.TemplatePageCursor.issue(
               snapshot,
               source["id"],
               source,
               scope,
               secret,
               now: 1_000,
               ttl_seconds: 60
             )

    parent = self()
    scoped_authorize = fn _source, _effect -> {:ok, nested_authorized_query(), scope} end

    continued_execute = fn query, _opts ->
      send(parent, {:continued_query, query})

      continuation_rows =
        if get_in(query.set, [:subselected, Access.at(0), :after]) do
          [
            [
              1,
              "PO-100",
              [
                %{
                  "id" => 12,
                  "sku" => "B",
                  "quantity" => 1,
                  "allocations" => [
                    %{"id" => 122, "warehouse" => "A1", "quantity" => 1},
                    %{"id" => 121, "warehouse" => "A1", "quantity" => 1}
                  ]
                }
              ]
            ]
          ]
        else
          [
            [
              1,
              "PO-100",
              [
                %{
                  "id" => 11,
                  "sku" => "A",
                  "quantity" => 2,
                  "allocations" => [%{"id" => 110, "warehouse" => "A1", "quantity" => 1}]
                }
              ]
            ]
          ]
        end

      {:ok, {continuation_rows, [], []}}
    end

    assert {:ok, %{"rows" => [line_root], "pages" => line_pages} = line_result} =
             TemplateSourceExecutor.execute(manifest, effect, scoped_authorize,
               page_snapshot: snapshot,
               page_cursor: hd(issued)["token"],
               page_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: continued_execute
             )

    assert Enum.map(line_root["lines"], & &1["id"]) == [11, 12]
    assert Enum.find(line_pages, &(&1["parent_path"] == [1]))["has_more"] == false
    assert Enum.find(line_pages, &(&1["parent_path"] == [1, 11]))["has_more"] == true

    assert Enum.find(line_result["identities"], &(&1["parent_path"] == [1]))["row_keys"] == [
             11,
             12
           ]

    assert_receive {:continued_query, line_query}

    assert get_in(line_query.set, [:subselected, Access.at(0), :after]) == %{
             parent_key: 1,
             values: [11]
           }

    later_snapshot = put_in(snapshot, ["sources", source["id"], "result"], line_result)

    assert {:ok, later_cursors} =
             SelectoComponents.TemplatePageCursor.issue(
               later_snapshot,
               source["id"],
               source,
               scope,
               secret,
               now: 1_001,
               ttl_seconds: 60
             )

    later_token =
      later_cursors
      |> Enum.find(&(&1["parent_path"] == [1, 12]))
      |> Map.fetch!("token")

    assert {:ok, %{"rows" => [later_root]} = later_result} =
             TemplateSourceExecutor.execute(manifest, effect, scoped_authorize,
               page_snapshot: later_snapshot,
               page_cursor: later_token,
               page_secret: secret,
               now: 1_002,
               ttl_seconds: 60,
               execute: fn query, _opts ->
                 send(parent, {:later_nested_query, query})

                 {:ok,
                  {[
                     [
                       1,
                       "PO-100",
                       [
                         %{
                           "id" => 12,
                           "sku" => "B",
                           "quantity" => 1,
                           "allocations" => [
                             %{"id" => 121, "warehouse" => "A1", "quantity" => 1}
                           ]
                         }
                       ]
                     ]
                   ], [], []}}
               end
             )

    assert_receive {:later_nested_query, later_query}
    assert {"id", 12} in get_in(later_query.set, [:subselected, Access.at(0), :filters])
    assert Enum.map(later_root["lines"], & &1["id"]) == [11, 12]
    assert Enum.map(Enum.at(later_root["lines"], 1)["allocations"], & &1["id"]) == [122, 121]
    assert Enum.find(later_result["pages"], &(&1["parent_path"] == [1, 12]))["has_more"] == false

    assert {:ok, %{"rows" => [allocation_root], "pages" => allocation_pages} = allocation_result} =
             TemplateSourceExecutor.execute(manifest, effect, scoped_authorize,
               page_snapshot: snapshot,
               page_cursor: Enum.at(issued, 1)["token"],
               page_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: continued_execute
             )

    assert get_in(allocation_root, ["lines", Access.at(0), "allocations"]) == [
             %{"id" => 111, "warehouse" => "A1", "quantity" => 1},
             %{"id" => 110, "warehouse" => "A1", "quantity" => 1}
           ]

    assert Enum.find(allocation_pages, &(&1["parent_path"] == [1]))["has_more"] == true
    assert Enum.find(allocation_pages, &(&1["parent_path"] == [1, 11]))["has_more"] == false

    assert Enum.find(allocation_result["identities"], &(&1["parent_path"] == [1, 11]))[
             "row_keys"
           ] == [111, 110]

    assert_receive {:continued_query, allocation_query}
    assert get_in(allocation_query.set, [:subselected, Access.at(0), :after]) == nil

    assert get_in(allocation_query.set, [
             :subselected,
             Access.at(0),
             :nested,
             Access.at(0),
             :after
           ]) == %{parent_key: 11, values: [111]}

    assert {:error, %{"code" => "invalid_page_cursor"}} =
             TemplateSourceExecutor.execute(manifest, effect, scoped_authorize,
               page_snapshot: snapshot,
               page_cursor: hd(issued)["token"],
               page_secret: secret,
               now: 1_061,
               ttl_seconds: 60,
               execute: fn _query, _opts -> flunk("expired cursor must not execute") end
             )

    assert {:error, %{"code" => "invalid_page_cursor"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               page_snapshot: snapshot,
               page_cursor: hd(issued)["token"],
               page_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn _query, _opts -> flunk("unscoped cursor must not execute") end
             )

    changed_effect = put_in(effect, ["bindings", "state", "search"], "changed")

    assert {:error, %{"code" => "invalid_page_cursor"}} =
             TemplateSourceExecutor.execute(manifest, changed_effect, scoped_authorize,
               page_snapshot: snapshot,
               page_cursor: hd(issued)["token"],
               page_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn _query, _opts -> flunk("changed bindings must not execute") end
             )

    assert {:error, %{"code" => "source_result_too_large"}} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               execute: execute,
               resource_budget: %{max_result_bytes: byte_size(Jason.encode!(result["rows"])) + 1}
             )
  end

  test "continuation query narrows the final collection page to its remaining allowance" do
    manifest =
      nested_manifest()
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "page_size"], 2)
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "max_items"], 3)
      |> put_in(
        ["sources", Access.at(0), "query", "collections", Access.at(0), "primary_key"],
        "id"
      )

    effect =
      manifest
      |> effect("PO-100")
      |> put_in(["bindings", "state", "warehouse"], "A1")

    source = hd(manifest["sources"])

    current = %{
      "rows" => [
        %{
          "id" => 1,
          "order_number" => "PO-100",
          "lines" => [
            %{"id" => 11, "sku" => "A", "quantity" => 2, "allocations" => []},
            %{"id" => 12, "sku" => "B", "quantity" => 1, "allocations" => []}
          ]
        }
      ],
      "pages" => [
        %{
          "collection_path" => ["lines"],
          "parent_path" => [1],
          "has_more" => true,
          "after_values" => [12]
        }
      ],
      "identities" => [
        %{"collection_path" => ["lines"], "parent_path" => [1], "row_keys" => [11, 12]}
      ]
    }

    scope = %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "open-orders-v1"
    }

    snapshot = %{
      "instance_id" => "source-executor-instance",
      "release_id" => "source-executor-release",
      "template_fingerprint" => manifest["template"]["fingerprint"],
      "inputs" => effect["bindings"]["input"],
      "state" => effect["bindings"]["state"],
      "sources" => %{
        source["id"] => %{"status" => "ready", "generation" => 1, "result" => current}
      }
    }

    secret = String.duplicate("s", 32)

    assert {:ok, [%{"token" => token}]} =
             SelectoComponents.TemplatePageCursor.issue(
               snapshot,
               source["id"],
               source,
               scope,
               secret,
               now: 1_000,
               ttl_seconds: 60
             )

    authorize = fn _source, _effect -> {:ok, nested_authorized_query(), scope} end
    parent = self()

    assert {:ok, merged} =
             TemplateSourceExecutor.execute(manifest, effect, authorize,
               page_snapshot: snapshot,
               page_cursor: token,
               page_secret: secret,
               now: 1_001,
               ttl_seconds: 60,
               execute: fn query, _opts ->
                 send(parent, {:partial_page_query, query})

                 {:ok,
                  {[
                     [
                       1,
                       "PO-100",
                       [
                         %{"id" => 13, "sku" => "C", "quantity" => 1, "allocations" => []},
                         %{"id" => 14, "sku" => "D", "quantity" => 1, "allocations" => []}
                       ]
                     ]
                   ], [], []}}
               end
             )

    assert_receive {:partial_page_query, query}
    assert get_in(query.set, [:subselected, Access.at(0), :limit]) == 2
    assert Enum.map(hd(merged["rows"])["lines"], & &1["id"]) == [11, 12, 13]
    assert hd(merged["pages"])["has_more"] == false
    assert hd(merged["pages"])["after_values"] == nil
    assert hd(merged["identities"])["row_keys"] == [11, 12, 13]
  end

  defp manifest, do: @fixture |> File.read!() |> :json.decode()
  defp nested_manifest, do: @nested_fixture |> File.read!() |> :json.decode()

  defp effect(manifest, search) do
    {:ok, observation} =
      SelectoTemplates.mount_runtime(manifest,
        instance_id: "source-executor-instance",
        release_id: "source-executor-release",
        inputs: %{}
      )

    observation["effects"]
    |> hd()
    |> put_in(["bindings", "state", "search"], search)
  end

  defp authorized_query do
    domain()
    |> Selecto.configure(:compile_only, adapter: Adapter, validate: false)
    |> Selecto.with_tenant(%{tenant_id: 7, required: true})
    |> Selecto.apply_tenant_scope()
  end

  defp nested_authorized_query do
    nested_domain()
    |> Selecto.configure(:compile_only, adapter: Adapter, validate: false)
    |> Selecto.with_tenant(%{tenant_id: 7, required: true})
    |> Selecto.apply_tenant_scope()
    |> Selecto.limit(10)
  end

  defp nested_domain do
    fingerprint = nested_manifest()["sources"] |> hd() |> Map.fetch!("domain_fingerprint")

    %{
      schema_version: 1,
      domain_version: "1.0.0",
      domain_fingerprint: fingerprint,
      name: "Orders with lines",
      source: %{
        source_table: "orders",
        primary_key: "id",
        tenant_field: "tenant_id",
        fields: ["id", "tenant_id", "order_number", "status"],
        redact_fields: [],
        columns: %{
          "id" => %{type: :integer},
          "tenant_id" => %{type: :integer, internal: true},
          "order_number" => %{type: :string},
          "status" => %{type: :string}
        },
        associations: %{
          "lines" => %{
            field: "lines",
            queryable: "order_lines",
            owner_key: "id",
            related_key: "order_id",
            cardinality: :many,
            source_scope_key: "tenant_id",
            target_scope_key: "tenant_id"
          }
        }
      },
      schemas: %{
        "order_lines" => %{
          source_table: "order_lines",
          primary_key: "id",
          fields: ["id", "tenant_id", "order_id", "sku", "quantity"],
          redact_fields: [],
          columns: %{
            "id" => %{type: :integer},
            "tenant_id" => %{type: :integer, internal: true},
            "order_id" => %{type: :integer},
            "sku" => %{type: :string},
            "quantity" => %{type: :integer}
          },
          associations: %{
            "allocations" => %{
              field: "allocations",
              queryable: "line_allocations",
              owner_key: "id",
              related_key: "line_id",
              cardinality: :many,
              source_scope_key: "tenant_id",
              target_scope_key: "tenant_id"
            }
          }
        },
        "line_allocations" => %{
          source_table: "line_allocations",
          primary_key: "id",
          fields: ["id", "tenant_id", "line_id", "warehouse", "quantity"],
          redact_fields: [],
          columns: %{
            "id" => %{type: :integer},
            "tenant_id" => %{type: :integer, internal: true},
            "line_id" => %{type: :integer},
            "warehouse" => %{type: :string},
            "quantity" => %{type: :integer}
          },
          associations: %{}
        }
      },
      joins: %{"lines" => %{type: :left, joins: %{"allocations" => %{type: :left}}}},
      query_library: %{
        segments: %{
          "searchable_orders" => %{
            filters: [{:eq, "order_number", {:param, "value"}}],
            parameters: %{"value" => %{type: :string, required: true}}
          }
        },
        projections: %{},
        orderings: %{},
        views: %{}
      }
    }
  end

  defp domain do
    fingerprint = manifest()["sources"] |> hd() |> Map.fetch!("domain_fingerprint")

    %{
      schema_version: 1,
      domain_version: "1.0.0",
      domain_fingerprint: fingerprint,
      name: "Orders",
      source: %{
        source_table: "orders",
        primary_key: "id",
        tenant_field: "tenant_id",
        fields: ["id", "tenant_id", "order_number", "ordered_at", "status", "customer_id"],
        redact_fields: [],
        columns: %{
          "id" => %{type: :integer},
          "tenant_id" => %{type: :integer, internal: true},
          "order_number" => %{type: :string},
          "ordered_at" => %{type: :utc_datetime},
          "status" => %{type: :string},
          "customer_id" => %{type: :integer}
        },
        associations: %{
          "customer" => %{
            field: "customer",
            queryable: "customers",
            owner_key: "customer_id",
            related_key: "id",
            cardinality: :one,
            source_scope_key: "tenant_id",
            target_scope_key: "tenant_id"
          }
        }
      },
      schemas: %{
        "customers" => %{
          source_table: "customers",
          primary_key: "id",
          fields: ["id", "tenant_id", "company_name"],
          redact_fields: [],
          columns: %{
            "id" => %{type: :integer},
            "tenant_id" => %{type: :integer, internal: true},
            "company_name" => %{type: :string}
          },
          associations: %{}
        }
      },
      joins: %{"customer" => %{type: :left}},
      query_library: %{
        segments: %{
          "searchable_orders" => %{
            filters: [{:eq, "order_number", {:param, "value"}}],
            parameters: %{"value" => %{type: :string, required: true}}
          }
        },
        projections: %{},
        orderings: %{},
        views: %{}
      }
    }
  end
end
