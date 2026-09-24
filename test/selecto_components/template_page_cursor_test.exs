defmodule SelectoComponents.TemplatePageCursorTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplatePageCursor

  @source_fixture Path.expand(
                    "../../../selecto-protocol/spec/fixtures/templates/order-lines-top-n.compile.json",
                    __DIR__
                  )
  @result_fixture Path.expand(
                    "../../../selecto-protocol/spec/fixtures/templates/collection-page-result.cases.json",
                    __DIR__
                  )
  @secret String.duplicate("s", 32)
  @scope %{
    "tenant_id" => "tenant-7",
    "principal_id" => "actor-1",
    "authorization_revision" => "acl-2",
    "membership_revision" => "open-orders-v1"
  }

  test "issues opaque parent-specific tokens and resolves only current positions" do
    {snapshot, source} = fixture()

    unpaged =
      source
      |> update_in(["query", "collections", Access.at(0)], &Map.delete(&1, "page_size"))
      |> update_in(
        ["query", "collections", Access.at(0), "collections", Access.at(0)],
        &Map.delete(&1, "page_size")
      )

    assert {:error, %{"code" => "invalid_page_cursor"}} =
             TemplatePageCursor.issue(snapshot, source["id"], unpaged, @scope, @secret)

    assert {:ok, issued} =
             TemplatePageCursor.issue(snapshot, source["id"], source, @scope, @secret,
               now: 1_000,
               ttl_seconds: 60
             )

    assert length(issued) == 4
    assert Enum.map(issued, & &1["has_more"]) == [true, true, false, false]

    assert Enum.all?(
             Enum.take(issued, 2),
             &Regex.match?(~r/^pc1\.1060\.[0-9a-f]{64}$/, &1["token"])
           )

    assert Enum.all?(Enum.drop(issued, 2), &is_nil(&1["token"]))
    refute hd(issued)["token"] =~ "tenant-7"
    refute hd(issued)["token"] =~ "A"

    assert {:ok,
            %{"collection_path" => ["lines"], "parent_path" => [1], "after_values" => ["A", 11]}} =
             TemplatePageCursor.resolve(
               snapshot,
               source["id"],
               source,
               @scope,
               @secret,
               hd(issued)["token"],
               now: 1_001,
               ttl_seconds: 60
             )

    assert {:ok, %{"collection_path" => ["lines", "allocations"], "parent_path" => [1, 11]}} =
             TemplatePageCursor.resolve(
               snapshot,
               source["id"],
               source,
               @scope,
               @secret,
               Enum.at(issued, 1)["token"],
               now: 1_001,
               ttl_seconds: 60
             )
  end

  test "scope, source, generation, binding, parent, expiry and tampering fail closed" do
    {snapshot, source} = fixture()

    {:ok, [first | _]} =
      TemplatePageCursor.issue(snapshot, source["id"], source, @scope, @secret,
        now: 1_000,
        ttl_seconds: 60
      )

    token = first["token"]

    altered = [
      {snapshot, source, %{@scope | "tenant_id" => "tenant-8"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "principal_id" => "actor-2"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "authorization_revision" => "acl-3"}, @secret, token, 1_001},
      {snapshot, source, %{@scope | "membership_revision" => "closed-orders-v1"}, @secret, token,
       1_001},
      {put_in(snapshot, ["release_id"], "release-2"), source, @scope, @secret, token, 1_001},
      {put_in(snapshot, ["sources", source["id"], "generation"], 2), source, @scope, @secret,
       token, 1_001},
      {put_in(snapshot, ["state", "search"], "changed"), source, @scope, @secret, token, 1_001},
      {snapshot, put_in(source, ["query", "limit"], 1), @scope, @secret, token, 1_001},
      {snapshot, source, @scope, String.duplicate("t", 32), token, 1_001},
      {snapshot, source, @scope, @secret, token <> "0", 1_001},
      {snapshot, source, @scope, @secret, token, 1_061},
      {put_in(
         snapshot,
         ["sources", source["id"], "result", "pages"],
         Enum.drop(get_in(snapshot, ["sources", source["id"], "result", "pages"]), 2)
       ), source, @scope, @secret, token, 1_001}
    ]

    for {current_snapshot, current_source, current_scope, secret, supplied, now} <- altered do
      assert {:error, %{"code" => "invalid_page_cursor"}} =
               TemplatePageCursor.resolve(
                 current_snapshot,
                 source["id"],
                 current_source,
                 current_scope,
                 secret,
                 supplied,
                 now: now,
                 ttl_seconds: 60
               )
    end
  end

  defp fixture do
    source =
      @source_fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("sources")
      |> hd()
      |> put_in(["query", "collections", Access.at(0), "page_size"], 1)
      |> put_in(
        ["query", "collections", Access.at(0), "collections", Access.at(0), "page_size"],
        1
      )

    page_result =
      @result_fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> hd()
      |> Map.fetch!("expected")

    snapshot = %{
      "instance_id" => "instance-1",
      "release_id" => "release-1",
      "template_fingerprint" => "sha256:template-1",
      "inputs" => %{},
      "state" => %{"search" => "A"},
      "sources" => %{
        source["id"] => %{
          "status" => "ready",
          "generation" => 1,
          "result" => page_result
        }
      }
    }

    {snapshot, source}
  end
end
