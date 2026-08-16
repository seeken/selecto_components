defmodule SelectoComponents.Form.QueryOperationsTest do
  use ExUnit.Case, async: true

  defmodule SavedViewStub do
    @behaviour SelectoComponents.SavedViews

    @impl true
    def get_view_names(_context), do: []

    @impl true
    def get_view("Films by Language", _context) do
      %{
        name: "Films by Language",
        params: %{
          "view_mode" => "aggregate",
          "filters" => [],
          "views" => %{
            "aggregate" => %{
              "group_by" => [["g1", "language", %{"alias" => "Language", "index" => "0"}]],
              "aggregate" => [
                ["a1", "id", %{"alias" => "Films", "function" => "count", "index" => "0"}]
              ],
              "per_page" => "100",
              "grid" => false,
              "grid_colorize" => false,
              "grid_color_scale" => "linear"
            }
          }
        }
      }
    end

    def get_view(_name, _context), do: nil

    @impl true
    def save_view(name, _context, params), do: %{name: name, params: params}

    @impl true
    def decode_view(view), do: view.params
  end

  defmodule TestLive do
    use Phoenix.LiveView
    use SelectoComponents.Form.EventHandlers.QueryOperations
  end

  test "query_executed updates parent selecto alongside query results" do
    stale_selecto = selecto()

    fresh_selecto = %{
      selecto()
      | set: %{selected: [{:field, "language", "Language"}], aggregates: []}
    }

    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, selecto: stale_selecto}}

    {:noreply, updated_socket} =
      TestLive.handle_info(
        {:query_executed,
         %{
           selecto: fresh_selecto,
           query_results: {[["English"]], [:language], ["Language"]},
           last_query_info: %{},
           view_meta: %{},
           applied_view: "aggregate",
           detail_page_cache: nil,
           aggregate_page_cache: nil
         }},
        socket
      )

    assert updated_socket.assigns.selecto == fresh_selecto
    assert updated_socket.assigns.applied_view == "aggregate"
  end

  test "saved view param is replaced with committed view params" do
    socket = base_socket(%{validation_locked_until_patch: true})

    {:noreply, updated_socket} =
      TestLive.handle_params(%{"saved_view" => "Films by Language"}, nil, socket)

    assert updated_socket.assigns.page_title == "View: Films by Language"
    assert updated_socket.assigns.view_config.view_mode == "aggregate"
    assert updated_socket.assigns.validation_locked_until_patch == false

    assert {:live, :patch, %{to: to, kind: :replace}} = updated_socket.redirected
    refute to =~ "saved_view="
    assert to =~ "view_mode=aggregate"
    assert to =~ "group_by"
    assert to =~ "aggregate"
  end

  test "domain-private mode ignores inbound query state and replaces it with a path-only URL" do
    socket =
      base_socket(%{
        selecto: private_selecto(),
        params: %{},
        view_config: %{view_mode: "detail", filters: [], views: %{}}
      })

    sensitive_params = %{
      "view_mode" => "aggregate",
      "filters" => %{
        "k0" => %{
          "uuid" => "secret-filter",
          "section" => "filters",
          "filter" => "language",
          "comp" => "=",
          "value" => "patient-123"
        }
      }
    }

    assert {:noreply, updated_socket} =
             TestLive.handle_params(sensitive_params, nil, socket)

    assert updated_socket.assigns.params == %{}
    assert updated_socket.assigns.view_config.view_mode == "detail"

    assert {:live, :patch, %{to: "/pagila_films", kind: :replace}} =
             updated_socket.redirected

    refute inspect(updated_socket.redirected) =~ "patient-123"
  end

  test "domain-private mode keeps generated state patches query-parameter free" do
    socket = base_socket(%{selecto: private_selecto()})

    updated_socket =
      SelectoComponents.Form.ParamsState.state_to_url(
        %{"filters" => %{"k0" => %{"value" => "patient-123"}}},
        socket
      )

    assert {:live, :patch, %{to: "/pagila_films"}} = updated_socket.redirected
    refute inspect(updated_socket.redirected) =~ "patient-123"
  end

  defp base_socket(overrides) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          my_path: "/pagila_films",
          params: %{"saved_view" => "Films by Language"},
          saved_view_module: SavedViewStub,
          saved_view_context: "/pagila_films",
          selecto: selecto(),
          views: [
            {:detail, SelectoComponents.Views.Detail, "Detail", []},
            {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", []},
            {:graph, SelectoComponents.Views.Graph, "Graph", []}
          ],
          view_config: %{view_mode: "detail", filters: [], views: %{}},
          last_query_info: %{},
          current_detail_page: 0,
          validation_locked_until_patch: false
        },
        overrides
      )

    %Phoenix.LiveView.Socket{
      assigns: assigns
    }
  end

  defp selecto do
    Selecto.configure(domain(), nil)
  end

  defp private_selecto do
    domain()
    |> Map.put(:components, %{query_params: false})
    |> Selecto.configure(nil)
  end

  defp domain do
    %{
      name: "QueryOperationsTest",
      source: %{
        source_table: "films",
        primary_key: :id,
        fields: [:id, :language],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          language: %{type: :string, name: "Language", colid: :language}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }
  end
end
