defmodule SelectoComponents.Form.HeaderTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Form.Header
  alias SelectoComponents.Theme

  test "renders the collapsed controller summary" do
    html = render_component(&Header.summary/1, base_assigns(%{show_view_configurator: false}))

    assert html =~ ~s(data-selecto-controller-summary)
    assert html =~ "View Controller"
    assert html =~ "Detail View"
    assert html =~ "Expand View Controller"
    assert html =~ "1 applied filter"
    assert html =~ "Status = open"
  end

  test "renders compact summary overflow text" do
    html =
      render_component(
        &Header.summary/1,
        base_assigns(%{
          applied_filters: [1, 2, 3, 4, 5],
          chip_filters: [
            %{uuid: "a", summary: "A"},
            %{uuid: "b", summary: "B"},
            %{uuid: "c", summary: "C"},
            %{uuid: "d", summary: "D"},
            %{uuid: "e", summary: "E"}
          ]
        })
      )

    assert html =~ "A"
    assert html =~ "D"
    assert html =~ "+1 more"
    assert html =~ ~s(data-filter-summary-remove)
  end

  test "renders promoted filter content through the slot" do
    html =
      render_component(
        fn assigns ->
          ~H"""
          <Header.summary
            id={@id}
            theme={@theme}
            controller_title={@controller_title}
            current_view_label={@current_view_label}
            applied_filters={@applied_filters}
            promoted_filters={@promoted_filters}
            chip_filters={@chip_filters}
            show_view_configurator={@show_view_configurator}
          >
            <:promoted_filter :let={filter}>
              <span data-promoted-filter={filter.uuid}>{filter.label}</span>
            </:promoted_filter>
          </Header.summary>
          """
        end,
        base_assigns(%{
          promoted_filters: [%{uuid: "f1", label: "Status", editable: true}],
          chip_filters: []
        })
      )

    assert html =~ ~s(data-promoted-filter="f1")
    assert html =~ "Status"
    assert html =~ ~s(phx-click="filter_remove")
    assert html =~ ~s(data-filter-summary-remove)
  end

  test "renders remove control on promoted filter cards" do
    html =
      render_component(
        &Header.summary/1,
        base_assigns(%{
          promoted_filters: [%{uuid: "f1", label: "Category", editable: true}],
          chip_filters: []
        })
      )

    assert html =~ ~s(data-promoted-filter-card="f1")
    assert html =~ ~s(phx-value-uuid="f1")
    assert html =~ "Remove Category filter"
  end

  defp base_assigns(overrides) do
    Map.merge(
      %{
        id: "header-test",
        theme: Theme.default_theme(:light),
        controller_title: "View Controller",
        current_view_label: "Detail View",
        applied_filters: ["status"],
        promoted_filters: [],
        chip_filters: [%{uuid: "status-filter", summary: "Status = open"}],
        show_view_configurator: true
      },
      overrides
    )
  end
end
