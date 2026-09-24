defmodule SelectoComponents.TemplateRootCursorTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateRootCursor

  @source_fixture Path.expand(
                    "../../../selecto-protocol/spec/fixtures/templates/order-root-page.compile.json",
                    __DIR__
                  )
  @secret String.duplicate("s", 32)
  @scope %{
    "tenant_id" => "tenant-7",
    "principal_id" => "actor-1",
    "authorization_revision" => "acl-2",
    "membership_revision" => "open-orders-v1"
  }

  test "issues an opaque current root cursor and resolves only its server-held position" do
    {snapshot, source} = fixture()

    assert {:ok, %{"has_more" => true, "token" => token}} =
             TemplateRootCursor.issue(snapshot, source["id"], source, @scope, @secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert Regex.match?(~r/^rc1\.1060\.[0-9a-f]{64}$/, token)
    refute token =~ "tenant-7"
    refute token =~ "PO-100"

    assert {:ok, %{"after_values" => [1]}} =
             TemplateRootCursor.resolve(
               snapshot,
               source["id"],
               source,
               @scope,
               @secret,
               token,
               now: 1_001,
               ttl_seconds: 60
             )

    final =
      snapshot
      |> put_in(["sources", source["id"], "result", "rows"], [%{"id" => 4}])
      |> put_in(["sources", source["id"], "result", "root_page", "has_more"], false)
      |> put_in(["sources", source["id"], "result", "root_page", "after_values"], nil)

    assert {:ok, %{"has_more" => false, "token" => nil}} =
             TemplateRootCursor.issue(final, source["id"], source, @scope, @secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateRootCursor.resolve(final, source["id"], source, @scope, @secret, token,
               now: 1_001,
               ttl_seconds: 60
             )
  end

  test "changed scope, release, bindings, generation, source, position, secret and expiry fail closed" do
    {snapshot, source} = fixture()

    {:ok, %{"token" => token}} =
      TemplateRootCursor.issue(snapshot, source["id"], source, @scope, @secret,
        now: 1_000,
        ttl_seconds: 60
      )

    altered = [
      {snapshot, source, %{@scope | "tenant_id" => "tenant-8"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "principal_id" => "actor-2"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "authorization_revision" => "acl-3"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "membership_revision" => "open-orders-v2"}, @secret, token,
       1_001},
      {put_in(snapshot, ["release_id"], "release-2"), source, @scope, @secret, token, 1_001},
      {put_in(snapshot, ["template_fingerprint"], "sha256:other"), source, @scope, @secret, token,
       1_001},
      {put_in(snapshot, ["sources", source["id"], "generation"], 2), source, @scope, @secret,
       token, 1_001},
      {put_in(snapshot, ["state", "search"], "changed"), source, @scope, @secret, token, 1_001},
      {snapshot, put_in(source, ["query", "limit"], 2), @scope, @secret, token, 1_001},
      {put_in(snapshot, ["sources", source["id"], "result", "root_page", "after_values"], [4]),
       source, @scope, @secret, token, 1_001},
      {snapshot, source, @scope, String.duplicate("t", 32), token, 1_001},
      {snapshot, source, @scope, @secret, token <> "0", 1_001},
      {snapshot, source, @scope, @secret, token, 1_061}
    ]

    for {current_snapshot, current_source, scope, secret, supplied, now} <- altered do
      assert {:error, %{"code" => "invalid_root_cursor"}} =
               TemplateRootCursor.resolve(
                 current_snapshot,
                 source["id"],
                 current_source,
                 scope,
                 secret,
                 supplied,
                 now: now,
                 ttl_seconds: 60
               )
    end

    bad_row = put_in(snapshot, ["sources", source["id"], "result", "rows"], [%{"id" => 4}])

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateRootCursor.issue(bad_row, source["id"], source, @scope, @secret)

    offset_source = put_in(source, ["query", "page"], %{"expression" => "state.root_page"})

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateRootCursor.issue(snapshot, source["id"], offset_source, @scope, @secret)
  end

  test "declared named date ordering binds a cursor to the current state choice" do
    {snapshot, source} = fixture()

    source =
      source
      |> put_in(["query", "order_by"], [])
      |> put_in(["query", "select"], ["id", "order_number", "ordered_at"])
      |> put_in(["query", "ordering_choice"], %{
        "binding" => %{"expression" => "state.sort"},
        "choices" => ["oldest", "newest"]
      })

    config = %{
      "page_size" => 1,
      "order_by" => [
        %{"field" => "ordered_at", "direction" => "desc"},
        %{"field" => "id", "direction" => "desc"}
      ],
      "order_types" => ["date", "integer"],
      "primary_key" => "id"
    }

    snapshot =
      snapshot
      |> put_in(["state", "sort"], "newest")
      |> put_in(["sources", "orders", "result"], %{
        "rows" => [%{"id" => 7, "ordered_at" => ~D[2026-09-18]}],
        "root_page" => %{
          "config" => config,
          "has_more" => true,
          "after_values" => ["2026-09-18", 7]
        }
      })

    assert {:ok, %{"token" => token}} =
             TemplateRootCursor.issue(snapshot, "orders", source, @scope, @secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert {:ok, %{"after_values" => ["2026-09-18", 7]}} =
             TemplateRootCursor.resolve(snapshot, "orders", source, @scope, @secret, token,
               now: 1_001,
               ttl_seconds: 60
             )

    changed = put_in(snapshot, ["state", "sort"], "oldest")

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateRootCursor.resolve(changed, "orders", source, @scope, @secret, token,
               now: 1_001,
               ttl_seconds: 60
             )
  end

  test "decimal and null root positions stay exact through the opaque host token" do
    {snapshot, source} = fixture()

    source =
      source
      |> put_in(["query", "select"], ["id", "order_number", "amount"])
      |> put_in(["query", "order_by"], [
        %{"field" => "amount", "direction" => "asc"},
        %{"field" => "id", "direction" => "asc"}
      ])

    config = %{
      "page_size" => 1,
      "order_by" => source["query"]["order_by"],
      "order_types" => ["decimal", "integer"],
      "primary_key" => "id"
    }

    decimal_snapshot =
      snapshot
      |> put_in(["sources", "orders", "result"], %{
        "rows" => [%{"id" => 1, "amount" => Decimal.new("9007199254740993.2500")}],
        "root_page" => %{
          "config" => config,
          "has_more" => true,
          "after_values" => ["9007199254740993.25", 1]
        }
      })

    assert {:ok, %{"token" => token}} =
             TemplateRootCursor.issue(decimal_snapshot, "orders", source, @scope, @secret)

    assert {:ok, %{"after_values" => ["9007199254740993.25", 1]}} =
             TemplateRootCursor.resolve(
               decimal_snapshot,
               "orders",
               source,
               @scope,
               @secret,
               token
             )

    wrong =
      put_in(decimal_snapshot, ["sources", "orders", "result", "root_page", "after_values"], [
        "9007199254740993.2500",
        1
      ])

    assert {:error, %{"code" => "invalid_root_cursor"}} =
             TemplateRootCursor.issue(wrong, "orders", source, @scope, @secret)

    descending = put_in(source, ["query", "order_by", Access.at(0), "direction"], "desc")

    null_snapshot =
      decimal_snapshot
      |> put_in(["sources", "orders", "result", "rows"], [%{"id" => 5, "amount" => nil}])
      |> put_in(
        ["sources", "orders", "result", "root_page", "config", "order_by"],
        descending["query"]["order_by"]
      )
      |> put_in(["sources", "orders", "result", "root_page", "after_values"], [nil, 5])

    assert {:ok, %{"token" => null_token}} =
             TemplateRootCursor.issue(null_snapshot, "orders", descending, @scope, @secret)

    assert {:ok, %{"after_values" => [nil, 5]}} =
             TemplateRootCursor.resolve(
               null_snapshot,
               "orders",
               descending,
               @scope,
               @secret,
               null_token
             )
  end

  defp fixture do
    source =
      @source_fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("sources")
      |> hd()
      |> update_in(["query"], fn query ->
        query |> Map.delete("page") |> Map.put("limit", 1)
      end)

    config = %{
      "page_size" => 1,
      "order_by" => [%{"field" => "id", "direction" => "asc"}],
      "order_types" => ["integer"],
      "primary_key" => "id"
    }

    snapshot = %{
      "instance_id" => "instance-1",
      "release_id" => "release-1",
      "template_fingerprint" => "sha256:template-1",
      "inputs" => %{},
      "state" => %{"search" => "PO"},
      "sources" => %{
        source["id"] => %{
          "generation" => 1,
          "status" => "ready",
          "result" => %{
            "rows" => [%{"id" => 1, "order_number" => "PO-100"}],
            "root_page" => %{
              "config" => config,
              "has_more" => true,
              "after_values" => [1]
            }
          }
        }
      }
    }

    {snapshot, source}
  end
end
