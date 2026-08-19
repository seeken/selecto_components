defmodule SelectoComponents.Form.TabsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Form.Tabs
  alias SelectoComponents.Theme

  test "renders the core form tabs" do
    html =
      render_component(&Tabs.nav/1, %{
        active_tab: nil,
        theme: Theme.default_theme(:light),
        use_saved_views: false,
        use_query_library: false
      })

    assert html =~ ~s(id="main-tab-view")
    assert html =~ ~s(id="main-tab-filter")
    assert html =~ ~s(id="main-tab-export")
    assert html =~ "View"
    assert html =~ "Filters"
    assert html =~ "Export"
    refute html =~ "Save View"
  end

  test "renders the query-library tab when named definitions are available" do
    html =
      render_component(&Tabs.nav/1, %{
        active_tab: "library",
        theme: Theme.default_theme(:light),
        use_saved_views: false,
        use_query_library: true
      })

    assert html =~ ~s(id="main-tab-library")
    assert html =~ "Query Library"
  end

  test "renders the save tab when saved views are enabled" do
    html =
      render_component(&Tabs.nav/1, %{
        active_tab: "save",
        theme: Theme.default_theme(:light),
        use_saved_views: true
      })

    assert html =~ ~s(id="main-tab-save")
    assert html =~ ~s(aria-selected)
    assert html =~ ~s(sc-tab-active)
    assert html =~ "Save View"
  end
end
