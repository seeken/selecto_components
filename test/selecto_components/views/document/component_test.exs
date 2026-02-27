defmodule SelectoComponents.Views.Document.ComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Views.Document.Component

  test "renders one document article per row" do
    html =
      render_component(Component,
        id: "document-test",
        executed: true,
        execution_error: nil,
        query_results:
          {[
             %{"name" => "Alice", "posts" => [%{"title" => "First Post"}]},
             %{"name" => "Bob", "posts" => []}
           ], ["name", "posts"], ["name", "posts"]},
        view_meta: %{
          template: %{
            "blocks" => [
              %{"type" => "title", "text" => "Customer {{name}}"},
              %{"type" => "fields", "title" => "Profile", "fields" => ["name"]},
              %{"type" => "table", "table" => "posts", "title" => "Posts"}
            ]
          },
          subselect_configs: [%{key: "posts", title: "Posts", columns: []}]
        }
      )

    assert length(Regex.scan(~r/<article\b/, html)) == 2
    assert html =~ "Customer Alice"
    assert html =~ "Customer Bob"
    assert html =~ "First Post"
    assert html =~ "No related data"
  end

  test "renders loading state when not executed" do
    html = render_component(Component, id: "document-loading", executed: false, query_results: nil)
    assert html =~ "Loading documents"
  end
end
