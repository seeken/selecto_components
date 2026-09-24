defmodule SelectoComponents.TemplateUrlLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint __MODULE__.Endpoint

  defmodule Endpoint do
    use Phoenix.Endpoint, otp_app: :selecto_components

    @session_options [
      store: :cookie,
      key: "_selecto_template_url_test",
      signing_salt: "template-url-test"
    ]

    socket("/live", Phoenix.LiveView.Socket,
      websocket: [connect_info: [session: @session_options]]
    )
  end

  defmodule HostLinks do
    use Phoenix.Component

    def element(assigns) do
      send(
        Application.fetch_env!(:selecto_components, :template_url_live_test_pid),
        {:url_callback_called, assigns.attributes["href"]}
      )

      assigns = assign(assigns, :href, assigns.attributes["href"])

      ~H"""
      <a href={@href}>{@children}</a>
      """
    end

    def component(assigns) do
      send(
        Application.fetch_env!(:selecto_components, :template_url_live_test_pid),
        {:url_callback_called, assigns.props["destination"]}
      )

      assigns = assign(assigns, :href, assigns.props["destination"])

      ~H"""
      <a href={@href}>{@children}</a>
      """
    end
  end

  defmodule UrlLive do
    use Phoenix.LiveView

    alias SelectoComponents.TemplateRenderer

    @fixture_dir Path.expand("../../../selecto-protocol/spec/fixtures/templates", __DIR__)

    @impl true
    def mount(_params, %{"kind" => kind, "target" => target}, socket) do
      source_name =
        case kind do
          "element" -> "render-safe-link.valid.selecto"
          "component" -> "render-link-component.valid.selecto"
        end

      {:ok, document} =
        @fixture_dir
        |> Path.join(source_name)
        |> File.read!()
        |> SelectoTemplates.parse()

      capabilities =
        @fixture_dir
        |> Path.join("capabilities.json")
        |> File.read!()
        |> Jason.decode!()

      {capabilities, registry} =
        case kind do
          "element" ->
            {put_in(capabilities, ["renderer", "elements", "a"], %{
               "attributes" => %{"href" => "string"},
               "children" => true
             }), %{elements: %{"a" => &HostLinks.element/1}}}

          "component" ->
            {put_in(capabilities, ["renderer", "components", "Link"], %{
               "props" => %{"destination" => "string"},
               "required_props" => ["destination"],
               "events" => %{},
               "children" => true
             }),
             %{
               components: %{"Link" => &HostLinks.component/1},
               url_props: %{"Link" => %{"destination" => "href"}}
             }}
        end

      {:ok, manifest} =
        SelectoTemplates.compile(document, domains: %{}, capabilities: capabilities)

      {:ok, mounted} =
        SelectoTemplates.mount_runtime(manifest,
          instance_id: "connected-url-#{kind}",
          release_id: "connected-url-v1",
          inputs: %{"target" => target}
        )

      {:ok,
       socket
       |> assign(:manifest, manifest)
       |> assign(:snapshot, mounted["snapshot"])
       |> assign(:registry, registry)}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <main id="connected-url-template">
        <TemplateRenderer.template
          manifest={@manifest}
          snapshot={@snapshot}
          registry={@registry}
        />
      </main>
      """
    end
  end

  setup_all do
    Application.put_env(:selecto_components, Endpoint,
      secret_key_base: String.duplicate("u", 64),
      live_view: [signing_salt: "template-url-live-test"],
      server: false
    )

    start_supervised!(Endpoint)
    on_exit(fn -> Application.delete_env(:selecto_components, Endpoint) end)
    :ok
  end

  test "connected native HEEx links validate element attributes and component props" do
    Application.put_env(:selecto_components, :template_url_live_test_pid, self())
    on_exit(fn -> Application.delete_env(:selecto_components, :template_url_live_test_pid) end)

    safe_target = "/orders/42?tab=a&next=b"
    unsafe_target = "javascript:alert(1)"

    for kind <- ["element", "component"] do
      {:ok, safe, _html} =
        live_isolated(build_conn(), UrlLive, session: %{"kind" => kind, "target" => safe_target})

      assert has_element?(safe, ~s(#connected-url-template a[href="#{safe_target}"]))
      assert render(safe) =~ ~s(href="/orders/42?tab=a&amp;next=b")
      assert_receive {:url_callback_called, ^safe_target}

      {:ok, unsafe, _html} =
        live_isolated(build_conn(), UrlLive,
          session: %{"kind" => kind, "target" => unsafe_target}
        )

      assert has_element?(unsafe, "[data-selecto-template-error=invalid_url_attribute]")
      refute has_element?(unsafe, "#connected-url-template a")
      refute_receive {:url_callback_called, ^unsafe_target}
    end
  end
end
