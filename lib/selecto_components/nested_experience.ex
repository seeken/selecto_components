defmodule SelectoComponents.NestedExperience do
  @moduledoc """
  Adapts a published nested consumer projection into collection-editor inputs
  and exact Updato mutation representations.

  The adapter is deliberately data-only. It does not infer ownership or
  deletion semantics from an association, field name, or submitted payload.
  """

  @modes ~w(append_only delta full_set replace_one link_delta)
  @operations ~w(create update delete reorder link unlink)

  @spec collection_input(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def collection_input(release, path_id, opts \\ [])

  def collection_input(release, path_id, opts)
      when is_map(release) and is_binary(path_id) and is_list(opts) do
    with :ok <- validate_release(release),
         {:ok, relationship} <- relationship(release, path_id),
         {:ok, mode} <- select_mode(relationship, Keyword.get(opts, :mode)),
         {:ok, operation_input} <- operation_input(release, relationship, opts) do
      write = relationship["write"] || %{}
      read = relationship["read"] || %{}
      identity = relationship["identity"] || %{}
      operations = enabled_operations(write)
      pagination = pagination_policy(read, write, opts)

      {:ok,
       operation_input
       |> Map.put("type", "collection")
       |> Map.put("composition", %{
         "path_id" => relationship["path_id"],
         "ownership" => relationship["ownership"],
         "cardinality" => relationship["cardinality"],
         "mutation_mode" => mode,
         "allowed_modes" => write["modes"] || [],
         "operations" => operations,
         "omission" => write["omission"],
         "min_items" => write["min_items"] || 0,
         "max_items" => write["max_items"],
         "max_mutations" => write["max_mutations"],
         "read" => read,
         "pagination" => pagination,
         "identity_fields" => identity["fields"] || [],
         "client_identity" => identity["client_field"] || "client_id",
         "tenant_scope" => relationship["tenant_scope"] || %{},
         "capabilities" => relationship["capabilities"] || %{},
         "ordering" => relationship["ordering"] || %{},
         "validation" => relationship["validation"] || %{},
         "offline" => relationship["offline"] || %{},
         "conflict" => relationship["conflict"] || %{},
         "idempotency" => relationship["idempotency"] || %{},
         "assurance" => relationship["assurance"] || %{},
         "output" => relationship["output"] || %{}
       })
       |> Map.put("min_items", write["min_items"] || 0)
       |> Map.put("max_items", write["max_items"])
       |> Map.put("max_mutations", write["max_mutations"])
       |> Map.put("reorder", "reorder" in operations)}
    end
  end

  def collection_input(_release, _path_id, _opts), do: {:error, :invalid_nested_release}

  @spec normalize_inputs(map(), [map()]) :: {:ok, map()} | {:error, term()}
  def normalize_inputs(inputs, input_definitions)
      when is_map(inputs) and is_list(input_definitions) do
    Enum.reduce_while(input_definitions, {:ok, inputs}, fn input, {:ok, normalized} ->
      id = input["id"]

      if is_binary(id) and is_map(input["composition"]) and Map.has_key?(normalized, id) do
        case normalize_collection(input, normalized[id]) do
          {:ok, value} -> {:cont, {:ok, Map.put(normalized, id, value)}}
          {:error, reason} -> {:halt, {:error, {id, reason}}}
        end
      else
        {:cont, {:ok, normalized}}
      end
    end)
  end

  @spec normalize_collection(map(), term()) :: {:ok, term()} | {:error, term()}
  def normalize_collection(input, items) when is_map(input) and is_list(items) do
    composition = input["composition"] || %{}
    mode = composition["mutation_mode"]
    allowed = composition["allowed_modes"] || []

    cond do
      mode not in @modes ->
        {:error, {:unknown_mutation_mode, mode}}

      mode not in allowed ->
        {:error, {:undeclared_mutation_mode, mode, allowed}}

      true ->
        normalize_mode(mode, input, items)
    end
  end

  def normalize_collection(_input, value), do: {:error, {:invalid_collection_value, value}}

  @spec collection_page(map(), [map()], pos_integer()) :: map()
  def collection_page(input, items, requested_page \\ 1)

  def collection_page(input, items, requested_page)
      when is_map(input) and is_list(items) and is_integer(requested_page) do
    page_size = get_in(input, ["composition", "pagination", "page_size"]) || 20
    page_size = if is_integer(page_size) and page_size > 0, do: page_size, else: 20
    total_items = length(items)
    total_pages = max(div(total_items + page_size - 1, page_size), 1)
    page = requested_page |> max(1) |> min(total_pages)

    visible =
      items
      |> Enum.with_index()
      |> Enum.slice((page - 1) * page_size, page_size)

    %{
      page: page,
      page_size: page_size,
      total_items: total_items,
      total_pages: total_pages,
      items: visible,
      previous?: page > 1,
      next?: page < total_pages
    }
  end

  def collection_page(_input, _items, _requested_page) do
    %{
      page: 1,
      page_size: 20,
      total_items: 0,
      total_pages: 1,
      items: [],
      previous?: false,
      next?: false
    }
  end

  @spec remove_item(map(), [map()], non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def remove_item(input, items, index)
      when is_map(input) and is_list(items) and is_integer(index) and index >= 0 do
    case Enum.fetch(items, index) do
      :error ->
        {:error, :unknown_nested_item}

      {:ok, item} ->
        mode = get_in(input, ["composition", "mutation_mode"])
        operations = get_in(input, ["composition", "operations"]) || []

        cond do
          newly_created?(item) ->
            {:ok, List.delete_at(items, index)}

          mode == "append_only" ->
            {:error, :append_only_item_cannot_be_removed}

          mode == "link_delta" and "unlink" in operations ->
            {:ok, List.replace_at(items, index, mark_operation(item, "unlink"))}

          mode in ~w(delta replace_one) and "delete" in operations ->
            {:ok, List.replace_at(items, index, mark_operation(item, "delete"))}

          mode == "full_set" and get_in(input, ["composition", "omission"]) == "delete_missing" ->
            {:ok, List.delete_at(items, index)}

          true ->
            {:error, :nested_remove_not_permitted}
        end
    end
  end

  def remove_item(_input, _items, _index), do: {:error, :invalid_nested_item_index}

  @spec retry_item(map(), [map()], non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def retry_item(input, items, index)
      when is_map(input) and is_list(items) and is_integer(index) and index >= 0 do
    with {:ok, item} <- fetch_item(items, index),
         true <-
           item["state"] in ~w(conflict rejected failed) or {:error, :nested_retry_not_needed},
         true <- retry_allowed?(input) or {:error, :nested_retry_not_permitted} do
      retried = item |> Map.put("state", "editable") |> Map.drop(["errors", "conflict"])
      {:ok, List.replace_at(items, index, retried)}
    end
  end

  def retry_item(_input, _items, _index), do: {:error, :invalid_nested_item_index}

  @spec restore_item(map(), [map()], non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
  def restore_item(input, items, index)
      when is_map(input) and is_list(items) and is_integer(index) and index >= 0 do
    with {:ok, item} <- fetch_item(items, index),
         true <- item["state"] == "removed" or {:error, :nested_item_not_removed} do
      case canonical_operation(item["op"]) do
        "delete" ->
          restored = item |> Map.put("op", "update") |> Map.put("state", "editable")
          {:ok, List.replace_at(items, index, restored)}

        "unlink" ->
          # Removing the pending unlink is the only non-destructive way to
          # preserve the already-existing association.
          {:ok, List.delete_at(items, index)}

        _operation ->
          {:error, :nested_restore_not_permitted}
      end
    end
  end

  def restore_item(_input, _items, _index), do: {:error, :invalid_nested_item_index}

  @spec retry_allowed?(map()) :: boolean()
  def retry_allowed?(input) do
    get_in(input, ["composition", "offline", "eligible"]) == true or
      map_size(get_in(input, ["composition", "conflict"]) || %{}) > 0
  end

  @spec new_item_operation(map()) :: String.t()
  def new_item_operation(input) do
    if get_in(input, ["composition", "mutation_mode"]) == "link_delta", do: "link", else: "create"
  end

  @spec reorder_allowed?(map()) :: boolean()
  def reorder_allowed?(input),
    do: get_in(input, ["composition", "operations"]) |> List.wrap() |> Enum.member?("reorder")

  @spec item_path(map(), map(), non_neg_integer()) :: String.t()
  def item_path(input, item, index) do
    composition = input["composition"] || %{}
    path = composition["path_id"] || input["id"] || "nested"
    identity_fields = composition["identity_fields"] || []
    client_field = composition["client_identity"] || "client_id"

    identity =
      Enum.find_value(identity_fields, fn field ->
        case item[to_string(field)] do
          nil -> nil
          value -> "#{field}=#{value}"
        end
      end) ||
        case item[to_string(client_field)] || item["client_id"] do
          nil -> "index=#{index}"
          value -> "#{client_field}=#{value}"
        end

    "#{path}[#{identity}]"
  end

  @spec error_path(map(), map(), non_neg_integer(), String.t()) :: String.t()
  def error_path(input, item, index, field), do: "#{item_path(input, item, index)}.#{field}"

  defp normalize_mode("append_only", input, items) do
    with :ok <- only_operations(items, ~w(create add), "append_only") do
      {:ok, %{"mode" => "append_only", "items" => Enum.map(items, &payload_item(&1, input))}}
    end
  end

  defp normalize_mode("delta", input, items) do
    with :ok <- only_operations(items, ~w(create add update edit delete remove), "delta") do
      grouped =
        items
        |> Enum.group_by(&canonical_operation(&1["op"]))
        |> Map.new(fn {operation, operation_items} ->
          {operation, Enum.map(operation_items, &payload_item(&1, input))}
        end)

      {:ok,
       %{
         "mode" => "delta",
         "create" => grouped["create"] || [],
         "update" => grouped["update"] || [],
         "delete" => grouped["delete"] || []
       }}
    end
  end

  defp normalize_mode("full_set", input, items) do
    with :ok <- only_operations(items, ~w(create add update edit keep), "full_set") do
      {:ok, %{"mode" => "full_set", "items" => Enum.map(items, &payload_item(&1, input))}}
    end
  end

  defp normalize_mode("replace_one", input, items) do
    with true <- length(items) <= 1 or {:error, :replace_one_cardinality},
         true <- items != [] or {:error, :replace_one_intent_required},
         :ok <- only_operations(items, ~w(create add update edit delete remove), "replace_one") do
      [item] = items
      value = %{canonical_operation(item["op"]) => payload_item(item, input)}

      {:ok, %{"mode" => "replace_one", "value" => value}}
    end
  end

  defp normalize_mode("link_delta", input, items) do
    with :ok <- only_operations(items, ~w(link unlink), "link_delta") do
      grouped = Enum.group_by(items, &canonical_operation(&1["op"]))

      {:ok,
       %{
         "mode" => "link_delta",
         "link" => Enum.map(grouped["link"] || [], &payload_item(&1, input)),
         "unlink" => Enum.map(grouped["unlink"] || [], &payload_item(&1, input))
       }}
    end
  end

  defp only_operations(items, allowed, mode) do
    invalid =
      items
      |> Enum.map(&to_string(&1["op"] || "create"))
      |> Enum.reject(&(&1 in allowed))
      |> Enum.uniq()

    if invalid == [], do: :ok, else: {:error, {:invalid_item_operations, mode, invalid}}
  end

  defp payload_item(item, input) do
    client_field = get_in(input, ["composition", "client_identity"]) || "client_id"
    client_id = item["client_id"]

    item
    |> Map.drop(["op", "state", "errors", "client_id"])
    |> maybe_put(client_field, client_id)
  end

  defp canonical_operation(operation) when operation in ~w(create add), do: "create"
  defp canonical_operation(operation) when operation in ~w(update edit keep), do: "update"
  defp canonical_operation(operation) when operation in ~w(delete remove), do: "delete"
  defp canonical_operation(operation) when operation in ~w(link unlink), do: operation
  defp canonical_operation(operation), do: to_string(operation || "create")

  defp newly_created?(item),
    do:
      canonical_operation(item["op"]) in ["create", "link"] and not authoritative_identity?(item)

  defp authoritative_identity?(item) do
    Enum.any?(item, fn {key, value} ->
      to_string(key) in ~w(id uuid) and value not in [nil, ""]
    end)
  end

  defp mark_operation(item, operation),
    do: item |> Map.put("op", operation) |> Map.put("state", "removed")

  defp fetch_item(items, index) do
    case Enum.fetch(items, index) do
      {:ok, item} -> {:ok, item}
      :error -> {:error, :unknown_nested_item}
    end
  end

  defp validate_release(%{"schema" => "selecto.consumer_projection_release.v1"}), do: :ok
  defp validate_release(_release), do: {:error, :unsupported_consumer_projection_release}

  defp relationship(release, path_id) do
    release
    |> get_in(["composition", "relationships"])
    |> flatten_relationships()
    |> Map.fetch(path_id)
    |> case do
      {:ok, relationship} -> {:ok, relationship}
      :error -> {:error, {:unknown_composition_path, path_id}}
    end
  end

  defp flatten_relationships(relationships) when is_map(relationships) do
    Enum.reduce(relationships, %{}, fn {_id, relationship}, flattened ->
      flattened
      |> Map.put(relationship["path_id"], relationship)
      |> Map.merge(flatten_relationships(relationship["relationships"] || %{}))
    end)
  end

  defp flatten_relationships(_relationships), do: %{}

  defp select_mode(relationship, requested) do
    allowed = get_in(relationship, ["write", "modes"]) || []
    mode = if(is_nil(requested), do: List.first(allowed), else: to_string(requested))

    if mode in allowed,
      do: {:ok, mode},
      else: {:error, {:unsupported_mutation_mode, mode, allowed}}
  end

  defp pagination_policy(read, write, opts) do
    authored = Keyword.get(opts, :page_size)
    read_limit = positive_integer(read["max_rows"])
    write_limit = positive_integer(write["max_items"])

    ceiling =
      [read_limit, write_limit, 20]
      |> Enum.reject(&is_nil/1)
      |> Enum.min()

    requested = positive_integer(authored) || ceiling || 20
    page_size = if ceiling, do: min(requested, ceiling), else: requested

    %{
      "strategy" =>
        if(is_integer(write_limit) and write_limit > page_size, do: "lazy", else: "bounded"),
      "page_size" => page_size
    }
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp operation_input(release, relationship, opts) do
    operation_id = Keyword.get(opts, :operation_id)

    operations = release["operations"] || %{}

    operation =
      if operation_id do
        operations[to_string(operation_id)]
      else
        operations
        |> Map.values()
        |> Enum.find(fn operation ->
          Enum.any?(operation["nested_inputs"] || [], &nested_input_matches?(&1, relationship))
        end)
      end

    input =
      operation &&
        Enum.find(operation["nested_inputs"] || [], &nested_input_matches?(&1, relationship))

    if is_map(input) do
      item = input["item"] || input["fields"] || []

      {:ok,
       input
       |> Map.put_new("id", relationship["id"])
       |> Map.put_new("label", relationship["id"])
       |> Map.put("item", item)}
    else
      {:error, {:nested_operation_input_not_found, relationship["path_id"], operation_id}}
    end
  end

  defp nested_input_matches?(input, relationship) do
    input["path_id"] == relationship["path_id"] or input["id"] == relationship["id"]
  end

  defp enabled_operations(write) do
    Enum.filter(@operations, &(write[&1] == true))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
