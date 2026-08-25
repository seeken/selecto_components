defmodule SelectoComponents.NestedExperienceTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.NestedExperience

  test "projects a published composition and Operation into one collection editor contract" do
    assert {:ok, input} =
             NestedExperience.collection_input(release(), "orders.items", mode: :delta)

    assert input["id"] == "items"
    assert input["composition"]["ownership"] == "composition"
    assert input["composition"]["mutation_mode"] == "delta"
    assert input["composition"]["identity_fields"] == ["id"]
    assert input["composition"]["ordering"] == %{"field" => "position"}
    assert input["composition"]["validation"]["unique_fields"] == ["sku"]
    assert input["min_items"] == 1
    assert input["max_items"] == 25

    assert input["composition"]["pagination"] == %{
             "strategy" => "lazy",
             "page_size" => 20
           }

    assert Enum.map(input["item"], & &1["id"]) == ["sku", "quantity"]
  end

  test "pages bounded collections without changing global item identities" do
    {:ok, input} =
      NestedExperience.collection_input(release(), "orders.items", mode: :delta, page_size: 10)

    items = Enum.map(1..25, &%{"op" => "update", "id" => &1, "quantity" => &1})
    page = NestedExperience.collection_page(input, items, 2)

    assert page.page == 2
    assert page.page_size == 10
    assert page.total_pages == 3
    assert page.total_items == 25
    assert page.previous?
    assert page.next?

    assert Enum.map(page.items, fn {item, index} -> {item["id"], index} end) ==
             Enum.map(11..20, &{&1, &1 - 1})

    assert NestedExperience.collection_page(input, items, 99).page == 3
  end

  test "normalizes delta items without converting them to a full set" do
    {:ok, input} = NestedExperience.collection_input(release(), "orders.items", mode: :delta)

    items = [
      %{"op" => "create", "client_id" => "new-1", "sku" => "A", "quantity" => 2},
      %{"op" => "update", "id" => 42, "sku" => "B", "quantity" => 3},
      %{"op" => "delete", "id" => 43}
    ]

    assert {:ok,
            %{
              "mode" => "delta",
              "create" => [%{"client_id" => "new-1", "sku" => "A", "quantity" => 2}],
              "update" => [%{"id" => 42, "sku" => "B", "quantity" => 3}],
              "delete" => [%{"id" => 43}]
            }} = NestedExperience.normalize_collection(input, items)

    assert NestedExperience.error_path(input, Enum.at(items, 0), 0, "quantity") ==
             "orders.items[client_id=new-1].quantity"

    assert NestedExperience.error_path(input, Enum.at(items, 1), 1, "quantity") ==
             "orders.items[id=42].quantity"
  end

  test "full-set and append-only representations reject ambiguous item operations" do
    {:ok, full_set} =
      NestedExperience.collection_input(release(), "orders.items", mode: :full_set)

    assert {:error, {:invalid_item_operations, "full_set", ["delete"]}} =
             NestedExperience.normalize_collection(full_set, [%{"op" => "delete", "id" => 42}])

    {:ok, append_only} =
      NestedExperience.collection_input(release(), "orders.items", mode: :append_only)

    assert {:error, {:invalid_item_operations, "append_only", ["update"]}} =
             NestedExperience.normalize_collection(append_only, [%{"op" => "update", "id" => 42}])
  end

  test "removal preserves stable persisted identity for delta and discards an unsaved create" do
    {:ok, input} = NestedExperience.collection_input(release(), "orders.items", mode: :delta)

    items = [
      %{"op" => "update", "id" => 42, "sku" => "A"},
      %{"op" => "create", "client_id" => "new-1", "sku" => "B"}
    ]

    assert {:ok, [%{"id" => 42, "op" => "delete", "state" => "removed"}, _new]} =
             NestedExperience.remove_item(input, items, 0)

    assert {:ok, [%{"id" => 42}]} =
             input
             |> NestedExperience.remove_item(items, 1)
             |> then(fn {:ok, [item]} -> {:ok, [Map.drop(item, ["op", "sku"])]} end)
  end

  test "fails closed for an undeclared editor representation" do
    assert {:error, {:unsupported_mutation_mode, "link_delta", allowed}} =
             NestedExperience.collection_input(release(), "orders.items", mode: :link_delta)

    assert allowed == ["append_only", "delta", "full_set"]
  end

  test "replace-one requires an explicit create, update, or delete intent" do
    input = %{
      "composition" => %{
        "mutation_mode" => "replace_one",
        "allowed_modes" => ["replace_one"]
      }
    }

    assert {:error, :replace_one_intent_required} =
             NestedExperience.normalize_collection(input, [])
  end

  test "conflicted items can retry and explicit removals can be restored" do
    {:ok, input} = NestedExperience.collection_input(release(), "orders.items", mode: :delta)

    conflicted = [
      %{
        "op" => "update",
        "state" => "conflict",
        "errors" => %{"quantity" => "stale"},
        "id" => 42,
        "quantity" => 3
      }
    ]

    assert {:ok, [retried]} = NestedExperience.retry_item(input, conflicted, 0)
    assert retried["state"] == "editable"
    refute Map.has_key?(retried, "errors")

    assert {:ok, [removed]} = NestedExperience.remove_item(input, [retried], 0)
    assert removed["op"] == "delete"
    assert removed["state"] == "removed"

    assert {:ok, [restored]} = NestedExperience.restore_item(input, [removed], 0)
    assert restored["op"] == "update"
    assert restored["state"] == "editable"
  end

  defp release do
    %{
      "schema" => "selecto.consumer_projection_release.v1",
      "composition" => %{
        "relationships" => %{
          "items" => %{
            "id" => "items",
            "path_id" => "orders.items",
            "ownership" => "composition",
            "cardinality" => "many",
            "identity" => %{"fields" => ["id"], "client_field" => "client_id"},
            "write" => %{
              "modes" => ["append_only", "delta", "full_set"],
              "create" => true,
              "update" => true,
              "delete" => true,
              "reorder" => false,
              "link" => false,
              "unlink" => false,
              "omission" => "retain_missing",
              "min_items" => 1,
              "max_items" => 25,
              "max_mutations" => 30
            },
            "offline" => %{"eligible" => true},
            "ordering" => %{"field" => "position"},
            "validation" => %{"unique_fields" => ["sku"]},
            "conflict" => %{"child_fields" => ["lock_version"]},
            "relationships" => %{}
          }
        }
      },
      "operations" => %{
        "edit-order" => %{
          "nested_inputs" => [
            %{
              "id" => "items",
              "path_id" => "orders.items",
              "label" => "Items",
              "fields" => [
                %{"id" => "sku", "label" => "SKU", "type" => "text", "required" => true},
                %{
                  "id" => "quantity",
                  "label" => "Quantity",
                  "type" => "number",
                  "required" => true
                }
              ]
            }
          ]
        }
      }
    }
  end
end
