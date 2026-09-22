defmodule SelectoComponents.TemplateRendererTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  alias SelectoComponents.TemplateRenderer

  @fixtures Path.expand("../../../selecto-protocol/spec/fixtures/templates", __DIR__)

  test "renders nested presentation data through trusted HEEx components with escaping" do
    manifest = fixture("customer-summary.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "customer:7",
               release_id: "release-1",
               inputs: %{
                 "customer" => %{
                   "company_name" => "<script>alert(1)</script>",
                   "address" => %{"city" => "Salt & Lake", "region" => "UT"}
                 }
               }
             )

    assert {:ok, safe} =
             TemplateRenderer.render(manifest, mounted["snapshot"], registry())

    html = Phoenix.HTML.safe_to_string(safe)

    assert html =~ ~s(id="selecto-template-customer-3A7-root-2Echildren-2E2")
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ "Salt &amp; Lake"
    refute html =~ "<script>"
    refute html =~ "No customer is assigned."
  end

  test "renders the else branch without treating falsey values as absent" do
    manifest = fixture("customer-summary.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "customer-empty",
               release_id: "release-1",
               inputs: %{"customer" => nil}
             )

    assert {:ok, safe} = TemplateRenderer.render(manifest, mounted["snapshot"], registry())
    assert Phoenix.HTML.safe_to_string(safe) =~ "No customer is assigned."
  end

  test "passes declared LiveView event names and resolved include bindings to the host registry" do
    manifest = fixture("order-browser.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "orders-1",
               release_id: "release-1",
               inputs: %{}
             )

    event = %{
      "schema" => "selecto.template.runtime-event.v1",
      "instance_id" => "orders-1",
      "release_id" => "release-1",
      "event_id" => "select-1",
      "name" => "order_selected",
      "expected_state_revision" => 0,
      "payload" => %{"value" => 17}
    }

    assert {:ok, dispatched} =
             SelectoTemplates.dispatch_runtime(manifest, mounted["snapshot"], event)

    assert {:ok, safe} =
             TemplateRenderer.render(manifest, dispatched["snapshot"], registry())

    html = Phoenix.HTML.safe_to_string(safe)
    assert html =~ ~s(phx-change="search_changed")
    assert html =~ ~s(data-select-event="order_selected")
    assert html =~ ~s(data-order-id="17")
  end

  test "registry callbacks receive normal Phoenix component assigns" do
    manifest = fixture("customer-summary.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "customer-assigns",
               release_id: "release-1",
               inputs: %{
                 "customer" => %{
                   "company_name" => "Acme",
                   "address" => %{"city" => "Denver", "region" => "CO"}
                 }
               }
             )

    registry = put_in(registry(), [:components, "Card"], &assigned_card/1)

    assert {:ok, safe} = TemplateRenderer.render(manifest, mounted["snapshot"], registry)
    assert Phoenix.HTML.safe_to_string(safe) =~ ~s(data-component-assign="selecto-template-card")
  end

  test "fails closed when the host has no registered component renderer" do
    manifest = fixture("customer-summary.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "customer-1",
               release_id: "release-1",
               inputs: %{"customer" => nil}
             )

    assert {:error, diagnostic} =
             TemplateRenderer.render(manifest, mounted["snapshot"], %{
               components: %{},
               elements: %{}
             })

    assert diagnostic["code"] == "unavailable_renderer"
    assert diagnostic["path"] == ["view", "root.children.2"]
  end

  def card(assigns) do
    ~H"""
    <section id={@dom_id} class={@props["class"]}>{@children}</section>
    """
  end

  def assigned_card(assigns) do
    assigns = assign(assigns, :assign_marker, "selecto-template-card")

    ~H"""
    <section id={@dom_id} data-component-assign={@assign_marker}>{@children}</section>
    """
  end

  def empty_state(assigns) do
    ~H"""
    <div id={@dom_id} class="selecto-template-empty">{@children}</div>
    """
  end

  def heading(assigns) do
    ~H"""
    <h2 id={@dom_id}>{@children}</h2>
    """
  end

  def paragraph(assigns) do
    ~H"""
    <p id={@dom_id}>{@children}</p>
    """
  end

  def search_input(assigns) do
    ~H"""
    <form id={@dom_id} phx-change={@events["change"]}>
      <input name="value" value={@props["value"]} />
    </form>
    """
  end

  def order_table(assigns) do
    ~H"""
    <div id={@dom_id} data-select-event={@events["select"]} data-row-count={length(@props["rows"] || [])}>
    </div>
    """
  end

  def include(assigns) do
    ~H"""
    <div id={@dom_id} data-template={@template} data-order-id={@bindings["order_id"]}></div>
    """
  end

  defp registry do
    %{
      components: %{
        "Card" => &card/1,
        "EmptyState" => &empty_state/1,
        "SearchInput" => &search_input/1,
        "OrderTable" => &order_table/1
      },
      elements: %{"h2" => &heading/1, "p" => &paragraph/1},
      include: &include/1
    }
  end

  defp fixture(name) do
    @fixtures
    |> Path.join(name)
    |> File.read!()
    |> :json.decode()
  end
end
