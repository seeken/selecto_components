defmodule SelectoComponents.Views.Document.FormTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Views.Document.Form

  test "renders document configuration controls" do
    html =
      render_component(Form,
        id: "document-form-test",
        view: {:document, SelectoComponents.Views.Document, "Document View", %{}},
        columns: [
          {"name", "Name", :string},
          {"email", "Email", :string},
          {"posts.title", "Post Title", :string}
        ],
        selecto: build_selecto(),
        view_config: %{
          view_mode: "document",
          views: %{
            document: %{
              selected: [],
              subtable_fields: [],
              template: %{"blocks" => []},
              per_page: "30",
              max_rows: "1000"
            }
          }
        }
      )

    assert html =~ "Document Fields"
    assert html =~ "Subtables"
    assert html =~ "document_template[blocks][0][text]"
    assert html =~ "document_per_page"
    assert html =~ "document_max_rows"
  end

  defp build_selecto do
    domain = %{
      name: "DocumentFormTest",
      source: %{
        source_table: "records",
        primary_key: :id,
        fields: [:id, :name, :email],
        redact_fields: [],
        columns: %{id: %{type: :integer}, name: %{type: :string}, email: %{type: :string}},
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }

    Selecto.configure(domain, nil)
  end
end
