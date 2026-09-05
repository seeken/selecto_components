defmodule SelectoComponents.Views.Detail.BusinessHeadersTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias SelectoComponents.Views.Detail.Component

  test "headers prefer explicit aliases and otherwise preserve canonical business names" do
    html =
      render_headers([
        %{"field" => "inspection_number", "alias" => "", "uuid" => "reference"},
        %{"field" => "score", "alias" => "Safety rating", "uuid" => "score"},
        %{"field" => "status", "alias" => "  ", "uuid" => "status"}
      ])

    assert html =~ "Inspection reference"
    assert html =~ "Safety rating"
    assert html =~ "Inspection status"
    refute html =~ "Inspection score"
  end

  test "unknown field metadata retains the readable storage-name fallback" do
    html =
      render_headers([
        %{"field" => "unregistered.review_notes", "alias" => "", "uuid" => "notes"}
      ])

    assert html =~ "Review notes"
  end

  defp render_headers(columns) do
    domain = %{
      name: "Inspection headers",
      source: %{
        source_table: "inspections",
        primary_key: :id,
        fields: [:id, :inspection_number, :score, :status],
        redact_fields: [],
        columns: %{
          id: %{type: :integer},
          inspection_number: %{type: :string, name: "Inspection reference"},
          score: %{type: :integer, name: "Inspection score"},
          status: %{type: :string, name: "Inspection status"}
        },
        associations: %{}
      },
      schemas: %{},
      joins: %{}
    }

    selecto = Selecto.configure(domain, nil) |> Map.put(:set, %{columns: columns})
    fields = Enum.map(columns, & &1["field"])

    render_component(Component, %{
      id: "business-header-test",
      executed: true,
      execution_error: nil,
      selecto: selecto,
      query_results: {[Enum.map(fields, fn _ -> "Sample" end)], fields, fields},
      view_meta: %{page: 0, per_page: 10, total_rows: 1, subselect_configs: []}
    })
  end
end
