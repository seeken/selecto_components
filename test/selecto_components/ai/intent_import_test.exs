defmodule SelectoComponents.AI.IntentImportTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.IntentImport
  alias SelectoComponents.AI.QueryContract

  test "import returns preview for valid intent json" do
    result =
      IntentImport.import(
        ~s({"intent_version":1,"mode":"draft","view_mode":"detail","selected":[{"field":"status"}]}),
        contract(),
        socket()
      )

    assert result.ok == true
    assert result.validation.ok == true
    assert is_map(result.preview)
    assert result.preview["preview"]["next_params"]["view_mode"] == "detail"
  end

  test "import returns validation errors for invalid intent json payload" do
    result =
      IntentImport.import(
        ~s({"intent_version":1,"mode":"replace","view_mode":"detail","selected":[{"field":"unknown"}]}),
        contract(),
        socket()
      )

    assert result.ok == false
    assert result.validation.ok == false
    assert Enum.any?(result.validation.errors, &(&1["code"] == "unknown_field"))
    assert result.preview == nil
  end

  test "import rejects malformed json" do
    result = IntentImport.import("not json", contract(), socket())

    assert result.ok == false
    assert Enum.any?(result.validation.errors, &(&1["code"] == "invalid_json"))
  end

  defp contract do
    QueryContract.generate(selecto(), views())
  end

  defp views do
    [
      {:detail, SelectoComponents.Views.Detail, "Detail", %{}},
      {:aggregate, SelectoComponents.Views.Aggregate, "Aggregate", %{}},
      {:graph, SelectoComponents.Views.Graph, "Graph", %{}}
    ]
  end

  defp socket do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        selecto: selecto(),
        views: views(),
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
        presentation_context: %{}
      }
    }
  end

  defp selecto do
    domain = %{
      name: "OrdersReporting",
      description: "Order reporting domain",
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
