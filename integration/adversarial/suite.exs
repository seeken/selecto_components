defmodule SelectoComponents.NativeAdversarialLiveViewTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest, only: [build_conn: 0, get: 2]
  import Phoenix.LiveViewTest
  alias SelectoComponents.NativeAdversarialFixture, as: Fixture
  @endpoint __MODULE__.Endpoint

  defmodule Host do
    use Phoenix.LiveView
    use SelectoComponents.Form
    alias SelectoComponents.NativeAdversarialFixture, as: Fixture

    @impl true
    def mount(_params, session, socket) do
      connection = Application.fetch_env!(:selecto_components, :native_adversarial_connection)

      selecto =
        Fixture.source(
          connection,
          session["tenant"] || 7,
          session["host_filter"],
          session["hidden"] == true
        )

      views = [{:detail, SelectoComponents.Views.Detail, "Detail", []}]

      {:ok,
       socket
       |> assign(get_initial_state(views, selecto))
       |> assign(
         my_path: "/adversarial",
         current_detail_page: 0,
         sort_by: [],
         last_query_info: %{},
         presentation_context: %{},
         host_connection: connection
       )}
    end

    # A host-owned notification models an authorization/scope change. Browser
    # events cannot choose the trusted tenant or the host baseline filter.
    @impl true
    def handle_info({:host_scope_changed, tenant, name}, socket) do
      {:noreply,
       assign(socket, :selecto, Fixture.source(socket.assigns.host_connection, tenant, name))}
    end

    @impl true
    def render(assigns) do
      rows =
        case assigns.query_results do
          {rows, _columns, _aliases} when is_list(rows) -> rows
          _ -> []
        end

      assigns = assign(assigns, :observed_rows, rows)

      ~H"""
      <main>
        <section id="native-observation" data-executed={to_string(@executed)} data-total={Map.get(@view_meta, :total_rows, 0)} data-page={Map.get(@view_meta, :page, 0)}>
          <ul><li :for={row <- @observed_rows} data-native-id={List.first(row)}>{Jason.encode!(row)}</li></ul>
        </section>
        <.live_component module={SelectoComponents.Views.Detail.Component} id="native-detail"
          executed={@executed} execution_error={@execution_error} selecto={@selecto}
          query_results={@query_results} view_meta={@view_meta} />
      </main>
      """
    end
  end

  defmodule IsolatedSortHost do
    use Phoenix.LiveView
    alias SelectoComponents.Form.ParamsState
    alias SelectoComponents.NativeAdversarialFixture, as: Fixture

    @impl true
    def mount(_params, session, socket) do
      connection = Application.fetch_env!(:selecto_components, :native_adversarial_connection)
      selecto = Fixture.source(connection, 7)
      views = [{:detail, SelectoComponents.Views.Detail, "Detail", []}]

      socket =
        socket
        |> assign(Host.get_initial_state(views, selecto))
        |> assign(
          my_path: "/adversarial",
          current_detail_page: 0,
          sort_by: [],
          last_query_info: %{},
          presentation_context: %{}
        )

      {:ok, ParamsState.view_from_params(session["params"], socket)}
    end

    @impl true
    def handle_info({:rerun_query_with_sort, sort_by}, socket) do
      ParamsState.view_from_params_with_sort(socket.assigns.used_params, socket, sort_by)
    end

    def handle_info({:query_executed, _info}, socket), do: {:noreply, socket}

    @impl true
    def render(assigns), do: Host.render(assigns)
  end

  defmodule Router do
    use Phoenix.Router
    import Phoenix.LiveViewTest, only: []
    import Phoenix.LiveView.Router

    pipeline :browser do
      plug(:fetch_session)
      plug(:fetch_live_flash)
    end

    scope "/" do
      pipe_through(:browser)
      live("/adversarial", SelectoComponents.NativeAdversarialLiveViewTest.Host)
    end
  end

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :selecto_components
    @session [store: :cookie, key: "_native_adversarial", signing_salt: "native-adversarial"]
    socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])
    plug(Plug.Session, @session)
    plug(SelectoComponents.NativeAdversarialLiveViewTest.Router)
  end

  setup_all do
    Application.put_env(:selecto_components, Endpoint,
      secret_key_base: String.duplicate("n", 64),
      live_view: [signing_salt: "native-adversarial"],
      pubsub_server: __MODULE__.PubSub,
      server: false
    )

    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    start_supervised!(Endpoint)
    on_exit(fn -> Application.delete_env(:selecto_components, Endpoint) end)
    :ok
  end

  setup do
    url = System.fetch_env!("SELECTO_COMPONENTS_ADVERSARIAL_DATABASE_URL")
    options = SelectoDBPostgreSQL.Verification.ConnectionOptions.from_url!(url)

    unless options[:port] != 5432 and options[:hostname] in ["127.0.0.1", "localhost"] and
             String.starts_with?(options[:database], "selecto_adv_"),
           do:
             raise(
               "Native LiveView requires a task-owned loopback selecto_adv_* database off5432"
             )

    connection = start_supervised!({Postgrex, options})

    previous =
      Map.new(
        [:native_adversarial_connection, :env],
        &{&1, Application.fetch_env(:selecto_components, &1)}
      )

    Application.put_env(:selecto_components, :native_adversarial_connection, connection)
    Application.put_env(:selecto_components, :env, :prod)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:selecto_components, key, value)
        {key, :error} -> Application.delete_env(:selecto_components, key)
      end)

      {:ok, cleanup} = Postgrex.start_link(options)
      Fixture.cleanup(cleanup)
      GenServer.stop(cleanup)
    end)

    %{connection: connection, fixture: Fixture.load()}
  end

  defp params(overrides \\ %{}) do
    Map.merge(
      %{
        "view_mode" => "detail",
        "selected" => %{
          "0" => %{"field" => "id", "index" => "0", "uuid" => "id-selected"},
          "1" => %{"field" => "name", "index" => "1", "uuid" => "name-selected"}
        },
        "order_by" => %{
          "0" => %{"field" => "id", "dir" => "asc", "index" => "0", "uuid" => "id-order"}
        },
        "filters" => %{},
        "per_page" => "2",
        "count_mode" => "exact"
      },
      overrides
    )
  end

  defp path(params), do: "/adversarial?" <> Plug.Conn.Query.encode(params)

  defp connect(params, session \\ %{}),
    do: live(build_conn() |> Plug.Test.init_test_session(session), path(params))

  defp observation(view) do
    %{
      rows: view |> element("#native-observation") |> render(),
      error:
        if(has_element?(view, "[role='alert']"),
          do: view |> element("[role='alert']") |> render(),
          else: ""
        )
    }
  end

  defp filter(field, value, extra \\ %{}),
    do:
      Map.merge(
        %{
          "uuid" => "filter-0",
          "section" => "filters",
          "index" => "0",
          "filter" => field,
          "comp" => "=",
          "value" => value
        },
        extra
      )

  defp filtered(filters), do: params(%{"filters" => filters})

  defp sort(view, column),
    do:
      view
      |> with_target("[data-phx-component='1']")
      |> render_click("sort_column", %{"column" => column})

  defp assert_rows(view, ids, total, executed \\ true) do
    assert has_element?(
             view,
             "#native-observation[data-executed='#{executed}'][data-total='#{total}']"
           ),
           render(view)

    for {id, index} <- Enum.with_index(ids) do
      assert has_element?(view, "#native-observation li[data-native-id='#{id}']")

      cell =
        element(
          view,
          "[data-selecto-result-cell][data-result-row-index='#{index}'][data-result-column-index='1']"
        )
        |> render()

      assert cell =~ ~r/>\s*#{id}\s*</
    end

    assert length(Regex.scan(~r/data-native-id=/, observation(view).rows)) == length(ids)
    assert length(Regex.scan(~r/data-selecto-result-row=/, render(view))) == length(ids)
    clean(render(view))
  end

  defp clean(html) do
    for token <- ~w(selecto_cert_adv_people selecto_cert_adv_orders SELECT SQLSTATE stacktrace),
        do: refute(html =~ token, "Rendered public LiveView leaks #{token}")

    for variant <- Fixture.variants(Fixture.load()),
        row <- variant["dataset"]["people"]["rows"],
        do: refute(html =~ Enum.at(row, 4), "Rendered public LiveView leaks a secret value")
  end

  defp observe(ctx, fun) do
    responses =
      for variant <- Fixture.variants(ctx.fixture) do
        :ok = Fixture.reset(ctx.connection, variant["dataset"])
        before = Fixture.readback(ctx.connection)
        assert before == Fixture.expected_state(variant["dataset"])
        results = fun.(fn -> assert Fixture.readback(ctx.connection) == before end)
        assert Fixture.readback(ctx.connection) == before
        results
      end

    [baseline, foreign, secrets] = responses
    assert baseline == foreign, "Foreign changes affected public LiveView observations"
    assert baseline == secrets, "Secret changes affected public LiveView observations"
  end

  test "TR-02/17: connected native form execution and page changes retain tenant and host scope",
       ctx do
    observe(ctx, fn unchanged ->
      {:ok, view, _html} = connect(params())
      assert_rows(view, [1, 2], 4)
      unchanged.()
      first = observation(view)
      view |> element("[data-selecto-results-page='next']") |> render_click()
      assert_rows(view, [3, 4], 4)
      unchanged.()
      second = observation(view)
      render_submit(view, "view-apply", params())
      assert_rows(view, [1, 2], 4)
      unchanged.()
      third = observation(view)
      GenServer.stop(view.pid)

      {:ok, scoped, _html} = connect(params(), %{"host_filter" => "alpha"})
      assert_rows(scoped, [1], 1)
      unchanged.()
      render_submit(scoped, "view-apply", params())
      assert_rows(scoped, [1], 1)
      unchanged.()
      fourth = observation(scoped)
      GenServer.stop(scoped.pid)
      [first, second, third, fourth]
    end)
  end

  test "TR-01/02/03: real routed URL filters and nested OR cannot replace socket-owned tenant scope",
       ctx do
    observe(ctx, fn unchanged ->
      {:ok, view, _html} = connect(params(%{"tenant" => "8"}))
      assert_rows(view, [1, 2], 4)
      unchanged.()
      control = observation(view)

      probes = [
        {filtered(%{"0" => filter("tenant_id", "8")}), [], 0},
        {filtered(%{"0" => filter("tenant_id", "7", %{"comp" => "!="})}), [], 0},
        {filtered(%{
           "0" => %{
             "uuid" => "or-section",
             "section" => "filters",
             "index" => "0",
             "is_section" => "Y",
             "conjunction" => "OR"
           },
           "1" =>
             filter("tenant_id", "8", %{
               "uuid" => "foreign-leaf",
               "section" => "or-section",
               "index" => "1"
             }),
           "2" =>
             filter("id", "1", %{"uuid" => "own-leaf", "section" => "or-section", "index" => "2"})
         }), [1], 1}
      ]

      responses =
        for {probe, ids, total} <- probes do
          render_patch(view, path(probe))
          assert_rows(view, ids, total)
          unchanged.()
          observation(view)
        end

      GenServer.stop(view.pid)
      [control | responses]
    end)
  end

  test "FV-01/02/03 and SURF-02: native URL/form fields and forged component sorting reject private roles",
       ctx do
    observe(ctx, fn unchanged ->
      for hidden? <- [false, true] do
        {:ok, view, _html} = connect(params(), %{"hidden" => hidden?})
        assert_rows(view, [1, 2], 4)
        unchanged.()

        refused =
          for field <- ~w(secret_score ssn),
              probe <- [
                params(%{
                  "selected" => %{
                    "0" => %{"field" => field, "uuid" => "hidden-selected", "index" => "0"}
                  }
                }),
                filtered(%{"0" => filter(field, "100")}),
                params(%{
                  "order_by" => %{
                    "0" => %{
                      "field" => field,
                      "dir" => "asc",
                      "uuid" => "hidden-order",
                      "index" => "0"
                    }
                  }
                })
              ] do
            render_patch(view, path(probe))
            assert_rows(view, [], 0, false)
            assert has_element?(view, "[role='alert']")
            unchanged.()
            observation(view)
          end

        render_patch(view, path(params()))
        assert_rows(view, [1, 2], 4)
        sort(view, "secret_score")
        assert_rows(view, [], 0, false)
        assert has_element?(view, "[role='alert']")
        unchanged.()
        sorted = observation(view)
        GenServer.stop(view.pid)
        refused ++ [sorted]
      end
    end)
  end

  test "SURF-02: real form submissions reject field/filter and comparator/comp ambiguity", ctx do
    observe(ctx, fn unchanged ->
      {:ok, view, _html} = connect(params())

      responses =
        for probe <- [
              filtered(%{"0" => filter("secret_score", "100", %{"field" => "name"})}),
              filtered(%{"0" => filter("id", "1", %{"comparator" => "=", "comp" => ">"})}),
              filtered(%{"0" => filter("amount", "10")})
            ] do
          render_submit(view, "view-apply", probe)
          assert_rows(view, [], 0, false)
          assert has_element?(view, "[role='alert']")
          unchanged.()
          observation(view)
        end

      GenServer.stop(view.pid)
      responses
    end)
  end

  test "TR-17: actual sort reruns discard pages cached under a previous host scope", ctx do
    observe(ctx, fn unchanged ->
      {:ok, view, _html} = connect(params())
      assert_rows(view, [1, 2], 4)
      unchanged.()

      responses =
        for {name, ids, total} <- [{"beta", [2], 1}, {"alpha", [1], 1}, {nil, [1, 2], 4}] do
          send(view.pid, {:host_scope_changed, 7, name})
          sort(view, "id")
          assert_rows(view, ids, total)
          unchanged.()
          observation(view)
        end

      GenServer.stop(view.pid)
      responses
    end)
  end

  test "FV-03/SURF-02: live_isolated native component sorting observes public rows and refuses hidden fields",
       ctx do
    observe(ctx, fn unchanged ->
      {:ok, view, _html} =
        live_isolated(build_conn(), IsolatedSortHost, session: %{"params" => params()})

      assert_rows(view, [1, 2], 4)
      unchanged.()
      first = observation(view)
      sort(view, "id")
      assert_rows(view, [1, 2], 4)
      unchanged.()
      second = observation(view)
      sort(view, "id")
      assert_rows(view, [4, 3], 4)
      unchanged.()
      third = observation(view)
      sort(view, "ssn")
      assert_rows(view, [], 0, false)
      assert has_element?(view, "[role='alert']")
      unchanged.()
      fourth = observation(view)
      GenServer.stop(view.pid)
      [first, second, third, fourth]
    end)
  end
end
