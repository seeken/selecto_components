defmodule SelectoComponents.Form.SubmitFooterTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Form.SubmitFooter
  alias SelectoComponents.Theme

  test "renders the submit button with dirty state metadata" do
    html =
      render_component(&SubmitFooter.footer/1, %{
        id: "submit-footer-test",
        theme: Theme.default_theme(:light),
        view_config_dirty?: true
      })

    assert html =~ ~s(id="selecto-submit-submit-footer-test")
    assert html =~ ~s(data-selecto-submit-button="true")
    assert html =~ ~s(data-dirty="true")
    assert html =~ "Unsaved"
  end

  test "renders a submit footer when promoted filters exist and the configurator is collapsed" do
    html =
      render_component(&SubmitFooter.footer/1, %{
        id: "submit-footer-test",
        theme: Theme.default_theme(:light),
        view_config_dirty?: false,
        show_view_configurator: false,
        promoted_filters?: true
      })

    assert html =~ ~s(data-selecto-submit-footer)
    assert html =~ ~s(data-dirty="false")
  end

  test "shows dirty submit styling when promoted filters changed while collapsed" do
    html =
      render_component(&SubmitFooter.footer/1, %{
        id: "submit-footer-test",
        theme: Theme.default_theme(:light),
        view_config_dirty?: true,
        show_view_configurator: false,
        promoted_filters?: true
      })

    assert html =~ ~s(data-dirty="true")
    assert html =~ "Unsaved"
  end
end
