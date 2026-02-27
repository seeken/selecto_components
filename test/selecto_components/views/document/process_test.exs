defmodule SelectoComponents.Views.Document.ProcessTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Views.Document.Options
  alias SelectoComponents.Views.Document.Process

  defp test_selecto do
    domain = %{
      source: %{
        source_table: "users",
        primary_key: :user_id,
        fields: [:user_id, :name],
        redact_fields: [],
        columns: %{
          user_id: %{type: :integer},
          name: %{type: :string}
        },
        associations: %{
          posts: %{
            queryable: :posts,
            field: :posts,
            owner_key: :user_id,
            related_key: :user_id
          }
        }
      },
      schemas: %{
        posts: %{
          source_table: "posts",
          primary_key: :post_id,
          fields: [:post_id, :user_id, :title],
          redact_fields: [],
          columns: %{
            post_id: %{type: :integer},
            user_id: %{type: :integer},
            title: %{type: :string}
          },
          associations: %{}
        }
      },
      name: "User",
      joins: %{
        posts: %{type: :left, name: "posts"}
      }
    }

    Selecto.configure(domain, [hostname: "localhost"], validate: false)
  end

  defp view_columns do
    %{
      "name" => %{type: :string, colid: "name"},
      "posts.title" => %{type: :string, colid: "posts.title"},
      "posts.user_id" => %{type: :integer, colid: "posts.user_id"}
    }
  end

  test "view/5 builds root fields and subtable denorm groups" do
    params = %{
      "document_selected" => %{
        "root-1" => %{"field" => "name", "index" => "0", "alias" => "Customer"}
      },
      "document_subtable_fields" => %{
        "sub-1" => %{"field" => "posts.title", "index" => "0"},
        "sub-2" => %{"field" => "posts.user_id", "index" => "1"}
      },
      "document_template" => %{"blocks" => [%{"type" => "title", "text" => "{{name}}"}]},
      "document_per_page" => "20",
      "document_max_rows" => "10000",
      "detail_page" => "2"
    }

    {view_set, view_meta} = Process.view(%{}, params, view_columns(), [], test_selecto())

    assert Enum.map(view_set.columns, &Map.get(&1, "field")) == ["name"]
    assert view_set.denorm_groups == %{"posts" => ["posts.title", "posts.user_id"]}
    assert [%{key: "posts"}] = view_meta.subselect_configs

    assert view_set.selected == [
             {:field, "name", "Customer"}
           ]

    assert view_meta.page == 2
    assert view_meta.per_page == 20
    assert view_meta.max_rows == "10000"
    assert get_in(view_meta, [:template, "blocks"]) == [%{"type" => "title", "text" => "{{name}}"}]
  end

  test "document view mode detection" do
    assert Options.document_view_mode?(%{"view_mode" => "document"})
    assert Options.document_view_mode?(%{view_mode: :document})
    refute Options.document_view_mode?(%{"view_mode" => "detail"})
  end
end
