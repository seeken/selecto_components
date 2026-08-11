defmodule SelectoComponents.Views.Analytic.DefaultsTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Views.Analytic.Defaults

  test "column hints provide defaults without domain registries" do
    selecto =
      Selecto.configure(
        %{
          name: "Bookings",
          source: %{
            source_table: "bookings",
            primary_key: :id,
            fields: [:id, :booked_at, :hours],
            redact_fields: [],
            columns: %{
              id: %{type: :integer},
              booked_at: %{type: :utc_datetime, default_grouping: :month},
              hours: %{type: :integer, default_aggregate: :sum}
            },
            associations: %{}
          },
          schemas: %{},
          joins: %{}
        },
        nil
      )

    assert Defaults.group_by(selecto) == [{"booked_at", %{"format" => "month"}}]
    assert Defaults.aggregate(selecto) == [{"hours", %{"format" => "sum"}}]
  end

  test "explicit domain defaults remain authoritative" do
    selecto =
      Selecto.configure(
        %{
          name: "Bookings",
          source: %{
            source_table: "bookings",
            primary_key: :id,
            fields: [:id, :hours],
            redact_fields: [],
            columns: %{
              id: %{type: :integer},
              hours: %{type: :integer, default_aggregate: :sum}
            },
            associations: %{}
          },
          schemas: %{},
          joins: %{},
          default_group_by: ["id"],
          default_aggregate: [{"id", %{"format" => "count"}}]
        },
        nil
      )

    assert Defaults.group_by(selecto) == ["id"]
    assert Defaults.aggregate(selecto) == [{"id", %{"format" => "count"}}]
  end
end
