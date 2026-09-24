defmodule SelectoComponents.TemplatePageLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint __MODULE__.Endpoint

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :selecto_components

    @session_options [
      store: :cookie,
      key: "_selecto_template_page_test",
      signing_salt: "template-page-test"
    ]
    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]
    )
  end

  defmodule PageLive do
    use Phoenix.LiveView

    alias SelectoComponents.TemplateHost

    @manifest_path Path.expand(
                     "../../../selecto-protocol/spec/fixtures/templates/order-lines-paged.compile.json",
                     __DIR__
                   )
    @secret String.duplicate("s", 32)
    @scope %{
      "tenant_id" => "7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-1",
      "membership_revision" => "orders-1"
    }

    @impl true
    def mount(_params, _session, socket) do
      manifest =
        @manifest_path
        |> File.read!()
        |> Jason.decode!()
        |> update_in(["sources", Access.at(0), "query", "collections", Access.at(0)], fn lines ->
          %{lines | "collections" => []}
        end)

      {:ok, socket} =
        TemplateHost.mount(socket, manifest,
          instance_id: "connected-page-test",
          release_id: "connected-page-v1",
          inputs: %{}
        )

      completion = %{
        "schema" => "selecto.template.runtime-completion.v1",
        "instance_id" => "connected-page-test",
        "release_id" => "connected-page-v1",
        "effect_id" => "connected-page-test:source:orders:1",
        "source" => "orders",
        "generation" => 1,
        "outcome" => "ok",
        "result" => %{
          "rows" => [
            %{
              "id" => 1,
              "order_number" => "PO-1",
              "lines" => [%{"id" => 11, "sku" => "A", "quantity" => 1}]
            },
            %{
              "id" => 3,
              "order_number" => "PO-3",
              "lines" => [%{"id" => 31, "sku" => "C", "quantity" => 1}]
            }
          ],
          "pages" => [
            %{
              "collection_path" => ["lines"],
              "parent_path" => [1],
              "has_more" => true,
              "after_values" => [11]
            },
            %{
              "collection_path" => ["lines"],
              "parent_path" => [3],
              "has_more" => true,
              "after_values" => [31]
            }
          ],
          "identities" => [
            %{"collection_path" => ["lines"], "parent_path" => [1], "row_keys" => [11]},
            %{"collection_path" => ["lines"], "parent_path" => [3], "row_keys" => [31]}
          ]
        }
      }

      {:ok, socket} = TemplateHost.complete(socket, completion)

      {:ok, controls} =
        TemplateHost.page_cursors(socket, "orders", @scope, @secret,
          now: 1_000,
          ttl_seconds: 60
        )

      {:ok, assign(socket, :page_controls, controls)}
    end

    @impl true
    def handle_event("page", %{"token" => token}, socket) do
      case TemplateHost.start_page(
             socket,
             "orders",
             token,
             &authorize/2,
             @secret,
             now: 1_001,
             ttl_seconds: 60,
             execute_options: [analyze_complexity: false],
             execute: &execute/2
           ) do
        {:ok, socket} -> {:noreply, socket}
        {:error, _diagnostic, socket} -> {:noreply, socket}
      end
    end

    @impl true
    def handle_async(name, result, socket) do
      {:noreply, socket} = TemplateHost.handle_async(name, result, socket)

      {:ok, controls} =
        TemplateHost.page_cursors(socket, "orders", @scope, @secret,
          now: 1_001,
          ttl_seconds: 60
        )

      {:noreply, assign(socket, :page_controls, controls)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <main id="connected-template-page">
        <div :for={order <- @template_runtime_snapshot["sources"]["orders"]["result"]["rows"]}
             id={"order-#{order["id"]}"}>
          <span :for={line <- order["lines"]} id={"line-#{line["id"]}"}>{line["sku"]}</span>
        </div>
        <button :for={page <- @page_controls}
                :if={page["has_more"]}
                id={"page-order-#{hd(page["parent_path"])}"}
                type="button"
                phx-click="page"
                phx-value-token={page["token"]}>Load more</button>
      </main>
      """
    end

    defp authorize(_source, _effect) do
      selecto =
        domain()
        |> Selecto.configure(:compile_only,
          adapter: SelectoComponents.TestAdapter,
          validate: false
        )
        |> Selecto.with_tenant(%{tenant_id: 7, required: true})
        |> Selecto.apply_tenant_scope()

      {:ok, selecto, @scope}
    end

    defp execute(query, _opts) do
      parent = get_in(query.set, [:subselected, Access.at(0), :after, :parent_key])

      if test_pid = Application.get_env(:selecto_components, :template_page_live_test_pid) do
        send(test_pid, {:page_query_started, self(), parent})

        receive do
          :continue_page_query -> :ok
        after
          5_000 -> raise "page query was not released"
        end
      end

      {order_id, line_id, sku} = if parent == 1, do: {1, 12, "B"}, else: {3, 32, "D"}

      {:ok,
       {[[order_id, "PO-#{order_id}", [%{"id" => line_id, "sku" => sku, "quantity" => 1}]]], [],
        []}}
    end

    defp domain do
      %{
        schema_version: 1,
        domain_version: "1.0.0",
        domain_fingerprint:
          "sha256:71369d2845c76377dbed29616f6ac3ea4b91cd70015710d537483c341be5f545",
        name: "Paged orders",
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
            associations: %{}
          }
        },
        joins: %{"lines" => %{type: :left}},
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

  setup_all do
    Application.put_env(:selecto_components, Endpoint,
      secret_key_base: String.duplicate("b", 64),
      live_view: [signing_salt: "template-page-live-test"],
      pubsub_server: __MODULE__.PubSub,
      server: false
    )

    start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})
    start_supervised!(Endpoint)
    on_exit(fn -> Application.delete_env(:selecto_components, Endpoint) end)
    :ok
  end

  test "connected LiveView advances two parent cursors without losing either page" do
    {:ok, view, _html} = live_isolated(build_conn(), PageLive)

    assert has_element?(view, "#line-11")
    assert has_element?(view, "#line-31")
    assert has_element?(view, "#page-order-1")
    assert has_element?(view, "#page-order-3")

    view |> element("#page-order-1") |> render_click()
    render_async(view)
    assert has_element?(view, "#line-12")
    assert has_element?(view, "#line-31")
    refute has_element?(view, "#page-order-1")
    assert has_element?(view, "#page-order-3")

    view |> element("#page-order-3") |> render_click()
    render_async(view)
    assert has_element?(view, "#line-12")
    assert has_element?(view, "#line-32")
    refute has_element?(view, "#page-order-3")
  end

  test "simultaneous parent page reads reject a stale commit and permit retry" do
    Application.put_env(:selecto_components, :template_page_live_test_pid, self())
    on_exit(fn -> Application.delete_env(:selecto_components, :template_page_live_test_pid) end)

    {:ok, view, _html} = live_isolated(build_conn(), PageLive)
    view |> element("#page-order-1") |> render_click()
    view |> element("#page-order-3") |> render_click()

    assert_receive {:page_query_started, first_worker, first_parent}
    assert_receive {:page_query_started, second_worker, second_parent}
    assert Enum.sort([first_parent, second_parent]) == [1, 3]

    send(first_worker, :continue_page_query)
    send(second_worker, :continue_page_query)
    render_async(view)

    loaded = Enum.filter([12, 32], &has_element?(view, "#line-#{&1}"))
    assert length(loaded) == 1
    assert has_element?(view, "#line-11")
    assert has_element?(view, "#line-31")

    remaining_parent = if loaded == [12], do: 3, else: 1
    assert has_element?(view, "#page-order-#{remaining_parent}")

    Application.delete_env(:selecto_components, :template_page_live_test_pid)
    view |> element("#page-order-#{remaining_parent}") |> render_click()
    render_async(view)

    assert has_element?(view, "#line-12")
    assert has_element?(view, "#line-32")
    refute has_element?(view, "#page-order-1")
    refute has_element?(view, "#page-order-3")
  end
end
