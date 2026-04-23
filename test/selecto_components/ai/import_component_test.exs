defmodule SelectoComponents.AI.ImportComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.AI.ImportComponent

  test "renders import textarea and buttons" do
    html = render_component(ImportComponent, %{id: "ai-import-test"})

    assert html =~ "Import AI Intent"
    assert html =~ "Intent JSON"
    assert html =~ "Preview Intent"
    assert html =~ "Apply Intent"
  end

  test "renders validation errors when import result is invalid" do
    html =
      render_component(ImportComponent, %{
        id: "ai-import-errors",
        import_result: %{
          ok: false,
          validation: %{
            ok: false,
            errors: [%{"path" => ["selected", 0, "field"], "message" => "Unknown field"}],
            warnings: []
          }
        }
      })

    assert html =~ "Validation Errors"
    assert html =~ "selected.0.field"
    assert html =~ "Unknown field"
  end

  test "renders preview summary when import result is valid" do
    html =
      render_component(ImportComponent, %{
        id: "ai-import-preview",
        import_result: %{
          ok: true,
          validation: %{ok: true, errors: [], warnings: []},
          preview: %{
            "preview" => %{
              "diff" => %{
                "view_mode" => %{"from" => "detail", "to" => "aggregate"},
                "changed_sections" => ["view_mode", "aggregate"]
              }
            }
          }
        }
      })

    assert html =~ "Preview Summary"
    assert html =~ "detail"
    assert html =~ "aggregate"
    assert html =~ "view_mode, aggregate"
  end
end
