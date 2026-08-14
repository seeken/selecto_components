defmodule SelectoComponents.ExportedViewsTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.ExportedViews

  test "build_create_attrs snapshots the current view state" do
    assigns = %{
      selecto: %{
        domain: %{name: "orders"},
        connection: :repo,
        adapter: SelectoComponents.TestAdapter
      },
      view_config: %{
        view_mode: "detail",
        filters: [],
        views: %{detail: %{selected: []}}
      },
      views: [{:detail, SelectoComponents.Views.Detail, "Detail", %{}}],
      path: "/orders",
      exported_view_context: "tenant:1:/orders",
      current_user_id: "1"
    }

    attrs =
      ExportedViews.build_create_attrs(assigns, %{
        "name" => "Order export",
        "cache_ttl_hours" => "6",
        "ip_allowlist_text" => "10.0.0.0/24"
      })

    assert attrs.name == "Order export"
    assert attrs.context == "tenant:1:/orders"
    assert attrs.view_type == "detail"
    assert attrs.cache_ttl_hours == 6
    assert attrs.ip_allowlist_text == "10.0.0.0/24"
    assert is_binary(attrs.public_id)

    assert {:ok, snapshot} = ExportedViews.decode_term(attrs.snapshot_blob)
    assert snapshot.params["view_mode"] == "detail"
    assert snapshot.context == "tenant:1:/orders"
  end

  test "build_create_attrs never persists connection options or live handles" do
    assigns = %{
      selecto: %{
        domain: %{name: "orders"},
        connection: [
          hostname: "db",
          username: "demo",
          password: "secret",
          ssl_opts: [cacertfile: "/tmp/ca.pem"]
        ],
        adapter: SelectoComponents.TestAdapter
      },
      view_config: %{view_mode: "detail", filters: [], views: %{detail: %{selected: []}}},
      views: [{:detail, SelectoComponents.Views.Detail, "Detail", %{}}],
      path: "/orders"
    }

    attrs = ExportedViews.build_create_attrs(assigns, %{"name" => "Safe export"})
    assert {:ok, snapshot} = ExportedViews.decode_term(attrs.snapshot_blob)
    refute Map.has_key?(snapshot, :connection)
    assert snapshot.adapter == SelectoComponents.TestAdapter
    assert snapshot.adapter_name == :test
    assert snapshot.runtime_key == "/orders"
    assert snapshot.capability_evidence.text_search.supported?
  end

  test "persisted snapshots require a matching live runtime at render time" do
    snapshot = %{adapter: SelectoComponents.TestAdapter, runtime_key: "tenant:1:/orders"}

    assert {:error, %Selecto.Error{type: :configuration_error}} =
             SelectoComponents.RuntimeProvider.resolve(snapshot)

    assert {:ok, %Selecto.Runtime.Context{connection: :repo}} =
             SelectoComponents.RuntimeProvider.resolve(snapshot,
               runtime: {SelectoComponents.TestAdapter, :repo}
             )

    assert {:error, %Selecto.Error{details: %{reason: %{reason: :adapter_mismatch}}}} =
             SelectoComponents.RuntimeProvider.resolve(snapshot,
               runtime: {String, :repo}
             )
  end

  test "decode_term rejects unsafe binaries" do
    blob = <<131, 100, 0, 21, "selecto_new_atom_test">>

    assert {:error, :invalid_blob} = ExportedViews.decode_term(blob)
  end

  test "encode_term rejects snapshots that require unsafe deserialization" do
    assert_raise ArgumentError, ~r/unsafe deserialization/, fn ->
      ExportedViews.encode_term(%{domain: %{formatter: fn value -> value end}})
    end
  end

  test "decode_term rejects compressed runtime snapshots with functions" do
    blob = :erlang.term_to_binary(%{domain: %{formatter: fn value -> value end}}, compressed: 6)

    assert {:error, :invalid_blob} = ExportedViews.decode_term(blob)
  end

  test "cache_status distinguishes fresh stale and disabled exports" do
    now = ~U[2026-03-16 10:00:00Z]

    assert ExportedViews.cache_status(%{cache_blob: nil}, now) == :missing

    assert ExportedViews.cache_status(
             %{cache_blob: <<1>>, cache_expires_at: ~U[2026-03-16 12:00:00Z]},
             now
           ) == :fresh

    assert ExportedViews.cache_status(
             %{cache_blob: <<1>>, cache_expires_at: ~U[2026-03-16 08:00:00Z]},
             now
           ) == :stale

    assert ExportedViews.cache_status(%{disabled_at: now}, now) == :disabled
  end
end
