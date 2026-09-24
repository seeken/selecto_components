defmodule SelectoComponents.TemplateRootPageLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint __MODULE__.Endpoint

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :selecto_components

    @session_options [
      store: :cookie,
      key: "_selecto_root_page_test",
      signing_salt: "root-page-test"
    ]
    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]
    )
  end

  defmodule RootLive do
    use Phoenix.LiveView

    alias SelectoComponents.TemplateHost

    @manifest_path Path.expand(
                     "../../../selecto-protocol/spec/fixtures/templates/order-root-page.compile.json",
                     __DIR__
                   )
    @fixture_dir Path.expand("../../../selecto-protocol/spec/fixtures/templates", __DIR__)
    @secret String.duplicate("r", 32)
    @scope %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "orders-v1"
    }
    @impl true
    def mount(_params, session, socket) do
      named? = session["named_ordering"] == true

      manifest =
        if named? do
          {:ok, document} =
            SelectoTemplates.parse(
              File.read!(Path.join(@fixture_dir, "order-choice-paged.valid.selecto"))
            )

          catalog =
            @fixture_dir
            |> Path.join("domains-ordering.json")
            |> File.read!()
            |> Jason.decode!()

          capabilities =
            @fixture_dir
            |> Path.join("capabilities.json")
            |> File.read!()
            |> Jason.decode!()

          {:ok, compiled} =
            SelectoTemplates.compile(document,
              domains: catalog["domains"],
              capabilities: capabilities
            )

          compiled
        else
          @manifest_path
          |> File.read!()
          |> Jason.decode!()
          |> update_in(["sources", Access.at(0), "query"], &Map.delete(&1, "page"))
        end

      {:ok, socket} =
        TemplateHost.mount(socket, manifest,
          instance_id: "connected-root-page-test",
          release_id: "connected-root-page-v1",
          inputs: %{}
        )

      {:ok, socket} =
        TemplateHost.start_source_effects(socket, &authorize/2,
          root_cursor: :first,
          execute: if(named?, do: &execute_named/2, else: &execute_first/2),
          execute_options: [analyze_complexity: false]
        )

      {:ok,
       socket
       |> assign(:named_ordering?, named?)
       |> assign(:root_control, %{"has_more" => false, "token" => nil})}
    end

    @impl true
    def handle_event("sort_changed", %{"value" => value}, socket) do
      with {:ok, socket} <- TemplateHost.dispatch(socket, "sort_changed", %{"value" => value}),
           {:ok, socket} <-
             TemplateHost.start_source_effects(socket, &authorize/2,
               root_cursor: :first,
               execute: &execute_named/2,
               execute_options: [analyze_complexity: false]
             ) do
        {:noreply, assign(socket, :root_control, %{"has_more" => false, "token" => nil})}
      else
        {:error, _diagnostic, socket} -> {:noreply, socket}
      end
    end

    @impl true
    def handle_event("next_root", %{"token" => token}, socket) do
      case TemplateHost.start_root_page(
             socket,
             "orders",
             token,
             &authorize/2,
             @secret,
             now: 1_001,
             ttl_seconds: 60,
             execute: if(socket.assigns.named_ordering?, do: &execute_named/2, else: &execute/2),
             execute_options: [analyze_complexity: false]
           ) do
        {:ok, socket} -> {:noreply, socket}
        {:error, _diagnostic, socket} -> {:noreply, socket}
      end
    end

    @impl true
    def handle_async(name, result, socket) do
      {:noreply, socket} = TemplateHost.handle_async(name, result, socket)

      case TemplateHost.root_cursor(socket, "orders", @scope, @secret,
             now: 1_001,
             ttl_seconds: 60
           ) do
        {:ok, control} -> {:noreply, assign(socket, :root_control, control)}
        {:error, _diagnostic} -> {:noreply, socket}
      end
    end

    @impl true
    def render(assigns) do
      ~H"""
      <main id="connected-root-page" data-page={@template_runtime_snapshot["sources"]["orders"]["page"]}>
        <div :for={order <- get_in(@template_runtime_snapshot, ["sources", "orders", "result", "rows"]) || []}
             id={"root-order-#{order["id"]}"}>{order["order_number"]}</div>
        <button :if={@named_ordering?}
                id="sort-newest"
                type="button"
                phx-click="sort_changed"
                phx-value-value="newest">Newest</button>
        <button :if={@root_control["has_more"]}
                id="next-root"
                type="button"
                phx-click="next_root"
                phx-value-token={@root_control["token"]}>Next</button>
      </main>
      """
    end

    defp authorize(source, _effect) do
      domain = %{
        schema_version: 1,
        domain_version: "1.0.0",
        domain_fingerprint:
          "sha256:122be73ca0275549db0b0725c3c35e3142e5d49a233a1c5640add91277b2de79",
        name: "Root orders",
        source: %{
          source_table: "orders",
          primary_key: "id",
          tenant_field: "tenant_id",
          fields: ["id", "tenant_id", "order_number"],
          redact_fields: [],
          columns: %{
            "id" => %{type: :integer},
            "tenant_id" => %{type: :integer, internal: true},
            "order_number" => %{type: :string}
          },
          associations: %{}
        },
        schemas: %{},
        joins: %{},
        query_library: %{segments: %{}, projections: %{}, orderings: %{}, views: %{}}
      }

      named? = Map.has_key?(source["query"], "ordering_choice")

      domain =
        if named? do
          catalog =
            @fixture_dir
            |> Path.join("domains-ordering.json")
            |> File.read!()
            |> Jason.decode!()

          domain
          |> Map.put(:domain_fingerprint, catalog["domains"]["orders"]["domain_fingerprint"])
          |> put_in([:source, :fields], ["id", "tenant_id", "order_number", "status"])
          |> put_in([:source, :columns, "status"], %{type: :string})
          |> put_in([:query_library, :orderings], %{
            "oldest" => %{order_by: [{"id", :asc}]},
            "newest" => %{order_by: [{"id", :desc}]}
          })
        else
          domain
        end

      authorized =
        domain
        |> Selecto.configure(:compile_only,
          adapter: SelectoComponents.TestAdapter,
          validate: false
        )
        |> Selecto.with_tenant(%{tenant_id: 7, required: true})
        |> Selecto.apply_tenant_scope()

      authorized = if named?, do: Selecto.filter(authorized, {"status", "open"}), else: authorized

      {:ok, authorized, @scope}
    end

    defp execute_first(query, _opts) do
      if test_pid = Application.get_env(:selecto_components, :template_root_page_live_test_pid) do
        send(test_pid, {:root_first_query, query})
      end

      {:ok, {[[1, "PO-1"], [2, "PO-2"], [3, "PO-3"]], [], []}}
    end

    defp execute(query, _opts) do
      if test_pid = Application.get_env(:selecto_components, :template_root_page_live_test_pid) do
        send(test_pid, {:root_page_query, self(), query})
      end

      if Application.get_env(:selecto_components, :template_root_page_live_block, false) do
        receive do
          :continue_root_page_query -> :ok
        after
          5_000 -> raise "root page query was not released"
        end
      end

      {:ok, {[[3, "PO-3"], [4, "PO-4"]], [], []}}
    end

    defp execute_named(query, _opts) do
      {sql, params} = Selecto.to_sql(query)
      ordering = Selecto.QueryLibrary.applied(query).ordering
      continued? = sql =~ "selecto_root.id >" or sql =~ "selecto_root.id <"

      if test_pid = Application.get_env(:selecto_components, :template_root_page_live_test_pid) do
        send(test_pid, {:named_root_query, ordering, continued?, sql, params})
      end

      rows =
        case {ordering, continued?} do
          {"oldest", false} -> [[1, "PO-1", "open"], [4, "PO-4", "open"], [5, "PO-5", "open"]]
          {"oldest", true} -> [[5, "PO-5", "open"], [7, "PO-7", "open"]]
          {"newest", false} -> [[7, "PO-7", "open"], [5, "PO-5", "open"], [4, "PO-4", "open"]]
          {"newest", true} -> [[4, "PO-4", "open"], [1, "PO-1", "open"]]
        end

      {:ok, {rows, [], []}}
    end
  end

  setup_all do
    Application.put_env(:selecto_components, Endpoint,
      secret_key_base: String.duplicate("b", 64),
      live_view: [signing_salt: "template-root-page-live-test"],
      pubsub_server: __MODULE__.PubSub,
      server: false
    )

    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    start_supervised!(Endpoint)
    on_exit(fn -> Application.delete_env(:selecto_components, Endpoint) end)
    :ok
  end

  test "connected LiveView replaces root rows and retires the terminal cursor" do
    Application.put_env(:selecto_components, :template_root_page_live_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:selecto_components, :template_root_page_live_test_pid)
    end)

    {:ok, view, _html} = live_isolated(build_conn(), RootLive)
    render_async(view)
    assert_receive {:root_first_query, first_query}
    {first_sql, first_params} = Selecto.to_sql(first_query)
    assert first_query.set.limit == 3
    assert first_sql =~ "tenant_id"
    assert 7 in first_params
    assert has_element?(view, "#root-order-1")
    assert has_element?(view, "#root-order-2")
    assert has_element?(view, "#next-root")

    view |> element("#next-root") |> render_click()
    render_async(view)

    assert has_element?(view, "#root-order-3")
    assert has_element?(view, "#root-order-4")
    refute has_element?(view, "#root-order-1")
    refute has_element?(view, "#next-root")
    assert has_element?(view, "#connected-root-page[data-page=\"2\"]")
  end

  test "connected named ordering reloads the root page and rejects the old cursor before a query" do
    Application.put_env(:selecto_components, :template_root_page_live_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:selecto_components, :template_root_page_live_test_pid)
    end)

    {:ok, view, _html} =
      live_isolated(build_conn(), RootLive, session: %{"named_ordering" => true})

    render_async(view)
    assert_receive {:named_root_query, "oldest", false, first_sql, first_params}
    assert first_sql =~ ~r/order by/i
    assert first_sql =~ "tenant_id"
    assert first_sql =~ "status"
    assert 7 in first_params
    assert "open" in first_params
    assert has_element?(view, "#root-order-1")
    assert has_element?(view, "#root-order-4")

    old_token = root_token(view)

    view |> element("#sort-newest") |> render_click()
    render_async(view)
    assert_receive {:named_root_query, "newest", false, newest_sql, newest_params}
    assert newest_sql =~ ~r/order by/i
    assert newest_sql =~ ~r/desc/i
    assert 7 in newest_params
    assert "open" in newest_params
    assert has_element?(view, "#root-order-7")
    assert has_element?(view, "#root-order-5")
    refute has_element?(view, "#root-order-1")

    new_token = root_token(view)

    refute new_token == old_token
    render_click(view, "next_root", %{"token" => old_token})
    render_async(view)
    refute_receive {:named_root_query, _, _, _, _}, 100
    assert has_element?(view, "#root-order-7")

    view |> element("#next-root") |> render_click()
    render_async(view)
    assert_receive {:named_root_query, "newest", true, continuation_sql, continuation_params}
    assert continuation_sql =~ "selecto_root.id <"
    assert 5 in continuation_params
    assert has_element?(view, "#root-order-4")
    assert has_element?(view, "#root-order-1")
    refute has_element?(view, "#root-order-7")
    refute has_element?(view, "#next-root")
  end

  defp root_token(view) do
    [_, token] = Regex.run(~r/id="next-root"[^>]*phx-value-token="([^"]+)"/s, render(view))
    token
  end

  test "forged root token reaches no source query" do
    Application.put_env(:selecto_components, :template_root_page_live_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:selecto_components, :template_root_page_live_test_pid)
    end)

    {:ok, view, _html} = live_isolated(build_conn(), RootLive)
    render_async(view)
    render_click(view, "next_root", %{"token" => "forged"})
    refute_receive {:root_page_query, _, _}, 100
    assert has_element?(view, "#root-order-1")
    assert has_element?(view, "#connected-root-page[data-page=\"1\"]")
  end

  test "overlapping root reads commit once and ignore the stale result" do
    Application.put_env(:selecto_components, :template_root_page_live_test_pid, self())
    Application.put_env(:selecto_components, :template_root_page_live_block, true)

    on_exit(fn ->
      Application.delete_env(:selecto_components, :template_root_page_live_test_pid)
      Application.delete_env(:selecto_components, :template_root_page_live_block)
    end)

    {:ok, view, _html} = live_isolated(build_conn(), RootLive)
    render_async(view)
    view |> element("#next-root") |> render_click()
    view |> element("#next-root") |> render_click()

    assert_receive {:root_page_query, first_worker, first_query}
    assert_receive {:root_page_query, second_worker, second_query}
    {first_sql, first_params} = Selecto.to_sql(first_query)
    {second_sql, second_params} = Selecto.to_sql(second_query)
    assert first_sql =~ "selecto_root.id >"
    assert second_sql =~ "selecto_root.id >"
    assert 2 in first_params
    assert 2 in second_params
    assert 7 in first_params
    assert 7 in second_params

    send(first_worker, :continue_root_page_query)
    send(second_worker, :continue_root_page_query)
    render_async(view)

    assert has_element?(view, "#root-order-3")
    assert has_element?(view, "#connected-root-page[data-page=\"2\"]")
    refute has_element?(view, "#next-root")
  end
end
