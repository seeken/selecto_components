defmodule SelectoComponents.AI.ImportComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.AI.ImportComponent
  alias SelectoComponents.Views

  test "renders import textarea and buttons" do
    html = render_component(ImportComponent, %{id: "ai-import-test"})

    assert html =~ "Import AI Intent"
    assert html =~ "Intent JSON"
    assert html =~ "Preview Intent"
    assert html =~ "Apply Intent"
    assert html =~ "Copy Contract JSON"
    assert html =~ "Copy Prompt Stub"
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

  test "preview_import stores a valid import_result" do
    socket =
      socket(%{
        import_json:
          ~s({"intent_version":1,"mode":"draft","view_mode":"detail","selected":[{"field":"status"}]})
      })

    assert {:noreply, updated_socket} =
             ImportComponent.handle_event("preview_import", %{}, socket)

    assert updated_socket.assigns.import_result.ok == true
    assert is_map(updated_socket.assigns.import_result.preview)
  end

  test "apply_import sends parent message when preview is valid" do
    socket =
      socket(%{
        import_result: %{
          ok: true,
          preview: %{
            "preview" => %{
              "next_params" => %{"view_mode" => "detail"},
              "next_view_config" => %{view_mode: "detail", filters: [], views: %{}}
            }
          }
        }
      })

    assert {:noreply, _updated_socket} = ImportComponent.handle_event("apply_import", %{}, socket)
    assert_received {:apply_ai_intent_preview, %{"preview" => _preview}}
  end

  test "copy_contract_json stores encoded contract" do
    socket = socket(%{})

    assert {:noreply, updated_socket} =
             ImportComponent.handle_event("copy_contract_json", %{}, socket)

    assert is_binary(updated_socket.assigns.contract_json)
    assert updated_socket.assigns.contract_json =~ "query_contract_version"
  end

  test "copy_prompt_stub stores generated prompt stub" do
    socket = socket(%{})

    assert {:noreply, updated_socket} =
             ImportComponent.handle_event("copy_prompt_stub", %{}, socket)

    assert is_binary(updated_socket.assigns.prompt_stub)
    assert updated_socket.assigns.prompt_stub =~ "return JSON only"
    assert updated_socket.assigns.prompt_stub =~ "intent_version"
  end

  defp socket(overrides) do
    %Phoenix.LiveView.Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            id: "ai-import-test",
            selecto: selecto(),
            views: [
              Views.spec(:detail, SelectoComponents.Views.Detail, "Detail", %{}),
              Views.spec(:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", %{}),
              Views.spec(:graph, SelectoComponents.Views.Graph, "Graph", %{})
            ],
            view_config: %{
              view_mode: "detail",
              filters: [],
              views: %{
                detail: %{
                  selected: [],
                  order_by: [],
                  per_page: "30",
                  max_rows: "1000",
                  count_mode: "bounded"
                },
                aggregate: %{
                  group_by: [],
                  aggregate: [],
                  per_page: "100",
                  grid: false,
                  grid_colorize: false,
                  grid_color_scale: "linear"
                },
                graph: %{x_axis: [], y_axis: [], series: [], chart_type: "bar", options: %{}}
              }
            },
            presentation_context: %{},
            import_json: "",
            import_result: nil
          },
          overrides
        )
    }
  end

  defp selecto do
    domain = %{
      name: "OrdersReporting",
      source: %{
        source_table: "orders",
        primary_key: :id,
        fields: [:id, :status, :revenue, :created_at],
        redact_fields: [],
        columns: %{
          id: %{type: :integer, name: "ID", colid: :id},
          status: %{type: :string, name: "Status", colid: :status, make_filter: true},
          revenue: %{type: :decimal, name: "Revenue", colid: :revenue},
          created_at: %{
            type: :utc_datetime,
            name: "Created At",
            colid: :created_at,
            make_filter: true
          }
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{},
      filters: %{
        "status" => %{id: "status", name: "Status", type: :string, comps: ["=", "!=", "IN"]},
        "created_at" => %{
          id: "created_at",
          name: "Created At",
          type: :utc_datetime,
          comps: [">=", "<=", "SHORTCUT"]
        }
      }
    }

    Selecto.configure(domain, nil, validate: false)
  end
end
