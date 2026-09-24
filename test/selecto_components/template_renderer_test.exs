defmodule SelectoComponents.TemplateRendererTest do
  use ExUnit.Case, async: true

  use Phoenix.Component

  alias SelectoComponents.TemplateRenderer

  @fixtures Path.expand("../../../selecto-protocol/spec/fixtures/templates", __DIR__)

  test "text-declared link reaches the URL guard before its registered renderer" do
    source = @fixtures |> Path.join("render-safe-link.valid.selecto") |> File.read!()

    capabilities =
      put_in(fixture("capabilities.json"), ["renderer", "elements", "a"], %{
        "attributes" => %{"href" => "string"},
        "children" => true
      })

    assert {:ok, document} = SelectoTemplates.parse(source)

    assert {:ok, manifest} =
             SelectoTemplates.compile(document, domains: %{}, capabilities: capabilities)

    registry = %{
      elements: %{
        "a" => fn assigns ->
          send(self(), :safe_link_renderer_called)
          escaped = Phoenix.HTML.html_escape(assigns.attributes["href"])

          {:safe,
           [
             "<a href=\"",
             Phoenix.HTML.Safe.to_iodata(escaped),
             "\">",
             Phoenix.HTML.Safe.to_iodata(assigns.children),
             "</a>"
           ]}
        end
      }
    }

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "safe-link",
               release_id: "release-1",
               inputs: %{"target" => "/orders/42?tab=a&next=b"}
             )

    assert {:ok, safe} = TemplateRenderer.render(manifest, mounted["snapshot"], registry)
    assert Phoenix.HTML.safe_to_string(safe) =~ ~s(href="/orders/42?tab=a&amp;next=b")
    assert_received :safe_link_renderer_called

    assert {:ok, unsafe} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "unsafe-link",
               release_id: "release-1",
               inputs: %{"target" => "javascript:alert(1)"}
             )

    assert {:error, %{"code" => "invalid_url_attribute"}} =
             TemplateRenderer.render(manifest, unsafe["snapshot"], registry)

    refute_received :safe_link_renderer_called
  end

  test "host-declared component URL props are checked before native rendering" do
    source = @fixtures |> Path.join("render-link-component.valid.selecto") |> File.read!()

    capabilities =
      put_in(fixture("capabilities.json"), ["renderer", "components", "Link"], %{
        "props" => %{"destination" => "string"},
        "required_props" => ["destination"],
        "events" => %{},
        "children" => true
      })

    assert {:ok, document} = SelectoTemplates.parse(source)

    assert {:ok, manifest} =
             SelectoTemplates.compile(document, domains: %{}, capabilities: capabilities)

    registry = %{
      components: %{
        "Link" => fn assigns ->
          send(self(), :link_component_called)
          escaped = Phoenix.HTML.html_escape(assigns.props["destination"])

          {:safe,
           [
             "<a href=\"",
             Phoenix.HTML.Safe.to_iodata(escaped),
             "\">",
             Phoenix.HTML.Safe.to_iodata(assigns.children),
             "</a>"
           ]}
        end
      },
      url_props: %{"Link" => %{"destination" => "href"}}
    }

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "component-link",
               release_id: "release-1",
               inputs: %{"target" => "/orders/42?tab=a&next=b"}
             )

    assert {:ok, safe} = TemplateRenderer.render(manifest, mounted["snapshot"], registry)
    assert Phoenix.HTML.safe_to_string(safe) =~ ~s(href="/orders/42?tab=a&amp;next=b")
    assert_received :link_component_called

    assert {:ok, unsafe} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "unsafe-component-link",
               release_id: "release-1",
               inputs: %{"target" => "javascript:alert(1)"}
             )

    assert {:error, %{"code" => "invalid_url_attribute"}} =
             TemplateRenderer.render(manifest, unsafe["snapshot"], registry)

    refute_received :link_component_called
  end

  test "URL-bearing element attributes follow the shared safe URL cases" do
    %{"schema" => "selecto.template.render-url-cases.v1", "cases" => cases} =
      fixture("render-url.cases.json")

    for %{"name" => name, "attribute" => attribute, "value" => value, "valid" => valid?} =
          test_case <-
          cases do
      value =
        case test_case do
          %{"repeat" => repeat, "prefix" => prefix} -> prefix <> String.duplicate(value, repeat)
          _ -> value
        end

      manifest = %{
        "sources" => [],
        "view" => %{
          "schema" => "selecto.template.view.v1",
          "nodes" => [
            %{
              "kind" => "element",
              "node_id" => "root.children.0",
              "name" => "a",
              "attributes" => %{
                attribute => %{
                  "kind" => "binding",
                  "type" => "string",
                  "expression" => "state.url"
                }
              },
              "children" => []
            }
          ]
        }
      }

      snapshot = %{
        "instance_id" => "url-case",
        "inputs" => %{},
        "state" => %{"url" => value},
        "sources" => %{}
      }

      registry = %{
        elements: %{
          "a" => fn assigns ->
            send(self(), {:url_renderer_called, name})
            escaped = Phoenix.HTML.html_escape(assigns.attributes[attribute])
            {:safe, ["<a ", attribute, "=\"", Phoenix.HTML.Safe.to_iodata(escaped), "\"></a>"]}
          end
        }
      }

      if valid? do
        assert {:ok, safe} = TemplateRenderer.render(manifest, snapshot, registry), name
        assert Phoenix.HTML.safe_to_string(safe) =~ "<a ", name
        assert_received {:url_renderer_called, ^name}
      else
        assert {:error, %{"code" => "invalid_url_attribute"}} =
                 TemplateRenderer.render(manifest, snapshot, registry),
               name

        refute_received {:url_renderer_called, ^name}
      end
    end
  end

  test "a parent fill renders in its context and replaces the child slot safely" do
    parent = fixture("slot-page.compile.json")
    child = fixture("slot-card.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(parent,
               instance_id: "slot-parent",
               release_id: "slot-release",
               inputs: %{"title" => "<script>unsafe</script>"}
             )

    include = fn assigns ->
      child_snapshot = %{
        "instance_id" => assigns.dom_id,
        "inputs" => %{},
        "state" => %{},
        "sources" => %{}
      }

      {:ok, safe} = TemplateRenderer.render(child, child_snapshot, registry(), assigns.slots)
      safe
    end

    assert {:ok, safe} =
             TemplateRenderer.render(parent, mounted["snapshot"], %{registry() | include: include})

    html = Phoenix.HTML.safe_to_string(safe)
    assert html =~ "&lt;script&gt;unsafe&lt;/script&gt;"
    assert html =~ "Caller body"
    refute html =~ "Default heading"
    refute html =~ "Default body"
    refute html =~ "<script>"

    child_snapshot = %{
      "instance_id" => "slot-child",
      "inputs" => %{},
      "state" => %{},
      "sources" => %{}
    }

    assert {:ok, fallback} = TemplateRenderer.render(child, child_snapshot, registry())
    assert Phoenix.HTML.safe_to_string(fallback) =~ "Default heading"
    assert Phoenix.HTML.safe_to_string(fallback) =~ "Default body"

    assert {:error, %{"code" => "invalid_render_input"}} =
             TemplateRenderer.render(child, child_snapshot, registry(), %{"heading" => "raw html"})

    malformed = put_in(parent, ["view", "nodes", Access.at(0), "slots", "heading"], "raw html")

    assert {:error, %{"code" => "invalid_render_node"}} =
             TemplateRenderer.render(malformed, mounted["snapshot"], %{
               registry()
               | include: include
             })
  end

  test "a filled slot forwards through an included view" do
    capabilities = fixture("capabilities.json")
    card = fixture("slot-card.compile.json")

    middle_source = """
    <template name="slot_middle" version="1">
      <include template="slot_card">
        <fill name="heading"><slot name="heading"><h2>Middle heading</h2></slot></fill>
      </include>
    </template>
    """

    outer_source = """
    <template name="slot_outer" version="1">
      <include template="slot_middle">
        <fill name="heading"><h2>Caller heading</h2></fill>
      </include>
    </template>
    """

    {:ok, middle_document} = SelectoTemplates.parse(middle_source)
    {:ok, outer_document} = SelectoTemplates.parse(outer_source)

    {:ok, middle} =
      SelectoTemplates.compile(middle_document, domains: %{}, capabilities: capabilities)

    {:ok, outer} =
      SelectoTemplates.compile(outer_document, domains: %{}, capabilities: capabilities)

    card_include = fn assigns ->
      {:ok, safe} =
        TemplateRenderer.render(card, slot_snapshot(assigns.dom_id), registry(), assigns.slots)

      safe
    end

    middle_include = fn assigns ->
      {:ok, safe} =
        TemplateRenderer.render(
          middle,
          slot_snapshot(assigns.dom_id),
          %{registry() | include: card_include},
          assigns.slots
        )

      safe
    end

    assert {:ok, safe} =
             TemplateRenderer.render(outer, slot_snapshot("slot-outer"), %{
               registry()
               | include: middle_include
             })

    html = Phoenix.HTML.safe_to_string(safe)
    assert html =~ "Caller heading"
    assert html =~ "Default body"
    refute html =~ "Middle heading"
    refute html =~ "Default heading"
  end

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

  test "binds a declared source count to a component after load and rejects a missing ready total" do
    manifest = fixture("order-state-reset.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "count-view",
               release_id: "release-1",
               inputs: %{}
             )

    registry =
      put_in(registry(), [:components, "RootPager"], fn assigns ->
        "count=#{inspect(assigns.props["total"])} size=#{inspect(assigns.props["page_size"])}"
      end)

    assert {:ok, loading} = TemplateRenderer.render(manifest, mounted["snapshot"], registry)
    assert Phoenix.HTML.safe_to_string(loading) =~ "count=nil size=2"

    ready =
      mounted["snapshot"]
      |> put_in(["sources", "orders", "status"], "ready")
      |> put_in(["sources", "orders", "result"], %{
        "rows" => [],
        "totals" => %{"order_count" => 3}
      })

    assert {:ok, rendered} = TemplateRenderer.render(manifest, ready, registry)
    assert Phoenix.HTML.safe_to_string(rendered) =~ "count=3 size=2"

    invalid = put_in(ready, ["sources", "orders", "result", "totals"], %{})

    assert {:error, %{"code" => "unsupported_expression"}} =
             TemplateRenderer.render(manifest, invalid, registry)
  end

  test "source readiness selects a template branch only after successful completion" do
    manifest = fixture("source-ready.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "source-ready",
               release_id: "release-1",
               inputs: %{}
             )

    snapshot = mounted["snapshot"]
    assert {:ok, loading} = TemplateRenderer.render(manifest, snapshot, registry())
    assert Phoenix.HTML.safe_to_string(loading) =~ "Source is pending."

    failed =
      snapshot
      |> put_in(["sources", "orders", "status"], "error")
      |> put_in(["sources", "orders", "result"], %{"rows" => [%{"id" => 7}]})

    assert {:ok, error} = TemplateRenderer.render(manifest, failed, registry())
    assert Phoenix.HTML.safe_to_string(error) =~ "Source is pending."

    ready = put_in(failed, ["sources", "orders", "status"], "ready")
    assert {:ok, completed} = TemplateRenderer.render(manifest, ready, registry())
    assert Phoenix.HTML.safe_to_string(completed) =~ "Source is ready."
    refute Phoenix.HTML.safe_to_string(completed) =~ "Source is pending."
  end

  test "a source-bound include renders once per public row with optional relationships" do
    manifest = fixture("order-customer-region.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "region-orders",
               release_id: "region-v1",
               inputs: %{}
             )

    snapshot =
      put_in(mounted["snapshot"], ["sources", "orders", "result"], [
        %{"id" => 1, "customer" => %{"region" => %{"name" => "West & North"}}},
        %{"id" => 2, "customer" => nil},
        %{"id" => 3, "customer" => %{"region" => nil}}
      ])

    assert {:ok, safe} =
             TemplateRenderer.render(manifest, snapshot, %{
               components: %{},
               elements: %{},
               include: &source_include/1
             })

    html = Phoenix.HTML.safe_to_string(safe)
    assert length(Regex.scan(~r/data-region-card=/, html)) == 3
    assert html =~ "West &amp; North"
    assert html =~ ~s(data-customer-presence="absent")
    assert html =~ ~s(id="selecto-template-region-2Dorders-root-2Echildren-2E1-2Erow-2E0")
    refute html =~ "West & North"

    source =
      @fixtures
      |> Path.join("customer-region-card.valid.selecto")
      |> File.read!()

    assert {:ok, document} = SelectoTemplates.parse(source)

    assert {:ok, child_manifest} =
             SelectoTemplates.compile(document,
               domains: %{},
               capabilities: fixture("capabilities.json")
             )

    recursive_include = fn assigns ->
      child_snapshot = %{
        "instance_id" => assigns.dom_id,
        "inputs" => assigns.bindings,
        "state" => %{},
        "sources" => %{}
      }

      {:ok, safe} =
        TemplateRenderer.render(child_manifest, child_snapshot, %{include: &region_leaf/1})

      safe
    end

    assert {:ok, nested_safe} =
             TemplateRenderer.render(manifest, snapshot, %{include: recursive_include})

    nested_html = Phoenix.HTML.safe_to_string(nested_safe)
    assert length(Regex.scan(~r/data-region-leaf=/, nested_html)) == 3
    assert nested_html =~ "West &amp; North"

    invalid = put_in(snapshot, ["sources", "orders", "result", Access.at(0), "customer"], 7)

    assert {:error, %{"code" => "render_type_mismatch"}} =
             TemplateRenderer.render(manifest, invalid, %{include: &source_include/1})
  end

  test "a root-source include receives each public row without private query metadata" do
    {:ok, document} =
      @fixtures
      |> Path.join("order-totals-include.valid.selecto")
      |> File.read!()
      |> SelectoTemplates.parse()

    domains = @fixtures |> Path.join("domains.json") |> File.read!() |> :json.decode()
    capabilities = @fixtures |> Path.join("capabilities.json") |> File.read!() |> :json.decode()

    {:ok, manifest} =
      SelectoTemplates.compile(document,
        domains: domains["domains"],
        capabilities: capabilities
      )

    {:ok, mounted} =
      SelectoTemplates.mount_runtime(manifest,
        instance_id: "root-include",
        release_id: "release-1",
        inputs: %{}
      )

    snapshot =
      put_in(mounted["snapshot"], ["sources", "orders", "result"], [
        %{"id" => 1, "order_number" => "PO<&>"},
        %{"id" => 2, "order_number" => "PO-2"}
      ])

    assert {:ok, safe} =
             TemplateRenderer.render(manifest, snapshot, %{include: &root_include/1})

    html = Phoenix.HTML.safe_to_string(safe)
    assert length(Regex.scan(~r/data-root-order=/, html)) == 2
    assert html =~ "PO&lt;&amp;&gt;"
    refute html =~ "PO<&>"
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

  test "a page result renders only public rows" do
    manifest = fixture("order-browser.compile.json")

    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest,
               instance_id: "orders-page",
               release_id: "release-1",
               inputs: %{}
             )

    snapshot =
      put_in(mounted["snapshot"], ["sources", "orders", "result"], %{
        "rows" => [%{"id" => 1}],
        "pages" => [%{"private_position" => "must-not-render"}],
        "identities" => [%{"row_keys" => ["private-row-key"]}]
      })

    assert {:ok, safe} = TemplateRenderer.render(manifest, snapshot, registry())
    html = Phoenix.HTML.safe_to_string(safe)
    assert html =~ ~s(data-row-count="1")
    refute html =~ "must-not-render"
    refute html =~ "private-row-key"

    total_snapshot =
      put_in(snapshot, ["sources", "orders", "result"], %{
        "rows" => [%{"id" => 1}],
        "totals" => %{"order_count" => 2},
        "identities" => [%{"row_keys" => ["private-row-key"]}]
      })

    assert {:ok, total_safe} = TemplateRenderer.render(manifest, total_snapshot, registry())
    total_html = Phoenix.HTML.safe_to_string(total_safe)
    assert total_html =~ ~s(data-row-count="1")
    refute total_html =~ "private-row-key"
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

  def source_include(assigns) do
    assigns =
      assign(assigns,
        customer_presence:
          if(is_map(assigns.bindings["customer"]), do: "present", else: "absent"),
        region_name: get_in(assigns.bindings, ["customer", "region", "name"])
      )

    ~H"""
    <article id={@dom_id} data-region-card={@template} data-customer-presence={@customer_presence}>
      {@region_name}
    </article>
    """
  end

  def root_include(assigns) do
    assigns = assign(assigns, :order_number, assigns.bindings["orders"]["order_number"])

    ~H"""
    <article id={@dom_id} data-root-order={@template}>{@order_number}</article>
    """
  end

  def region_leaf(assigns) do
    assigns = assign(assigns, :name, get_in(assigns.bindings, ["region", "name"]))

    ~H"""
    <span id={@dom_id} data-region-leaf={@template}>{@name}</span>
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

  defp slot_snapshot(instance_id),
    do: %{"instance_id" => instance_id, "inputs" => %{}, "state" => %{}, "sources" => %{}}
end
