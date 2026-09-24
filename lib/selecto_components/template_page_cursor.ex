defmodule SelectoComponents.TemplatePageCursor do
  @moduledoc """
  Issues opaque collection cursors from a server-held source result.

  A cursor contains only an expiry and a keyed digest. Resolution compares it
  with the current source's private page positions after the host has obtained
  fresh tenant and authorization scope. The host supplies a shared secret and
  never passes browser-supplied positions to query lowering.
  """

  @token_version "pc1"
  @default_ttl_seconds 900
  @max_pages 10_000

  @spec issue(map(), binary(), map(), map(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, map()}
  def issue(snapshot, source_id, source_plan, scope, secret, opts \\ []) do
    with {:ok, context, pages} <- context_and_pages(snapshot, source_id, source_plan, scope),
         {:ok, now, ttl} <- clock_and_ttl(secret, opts) do
      expires_at = now + ttl

      {:ok,
       Enum.map(pages, fn page ->
         position = position(page)

         %{
           "collection_path" => page["collection_path"],
           "parent_path" => page["parent_path"],
           "has_more" => page["has_more"],
           "token" =>
             if(page["has_more"],
               do: token(context, position, expires_at, secret),
               else: nil
             )
         }
       end)}
    end
  end

  @spec resolve(map(), binary(), map(), map(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def resolve(snapshot, source_id, source_plan, scope, secret, supplied, opts \\ []) do
    with {:ok, context, pages} <- context_and_pages(snapshot, source_id, source_plan, scope),
         {:ok, now, ttl} <- clock_and_ttl(secret, opts),
         {:ok, expires_at} <- token_expiry(supplied, now, ttl) do
      pages
      |> Enum.filter(& &1["has_more"])
      |> Enum.find_value(fn page ->
        page_position = position(page)
        expected = token(context, page_position, expires_at, secret)

        if Plug.Crypto.secure_compare(expected, supplied), do: page_position
      end)
      |> case do
        nil -> invalid_cursor()
        page_position -> {:ok, page_position}
      end
    end
  end

  defp context_and_pages(snapshot, source_id, source_plan, scope)
       when is_map(snapshot) and is_binary(source_id) and is_map(source_plan) and is_map(scope) do
    source = get_in(snapshot, ["sources", source_id])
    result = if is_map(source), do: source["result"]

    with true <- non_empty?(snapshot["instance_id"]),
         true <- non_empty?(snapshot["release_id"]),
         true <- non_empty?(snapshot["template_fingerprint"]),
         true <- source_plan["id"] == source_id and non_empty?(source_id),
         true <- paged_source?(source_plan),
         true <- non_empty?(scope["tenant_id"]),
         true <- non_empty?(scope["principal_id"]),
         true <- non_empty?(scope["authorization_revision"]),
         true <- non_empty?(scope["membership_revision"]),
         %{"generation" => generation, "status" => "ready"} <- source,
         true <- is_integer(generation) and generation > 0,
         %{"pages" => pages, "rows" => rows} <- result,
         true <- is_list(rows) and is_list(pages) and pages != [] and length(pages) <= @max_pages,
         true <- Enum.all?(pages, &(valid_page?(&1) and declared_page?(source_plan, &1))),
         {:ok, source_fingerprint} <- fingerprint(source_plan),
         {:ok, bindings_fingerprint} <-
           fingerprint(%{"input" => snapshot["inputs"], "state" => snapshot["state"]}) do
      context = %{
        "schema" => "selecto.template.page-cursor.v1",
        "instance_id" => snapshot["instance_id"],
        "release_id" => snapshot["release_id"],
        "template_fingerprint" => snapshot["template_fingerprint"],
        "source_id" => source_id,
        "source_fingerprint" => source_fingerprint,
        "generation" => generation,
        "tenant_id" => scope["tenant_id"],
        "principal_id" => scope["principal_id"],
        "authorization_revision" => scope["authorization_revision"],
        "membership_revision" => scope["membership_revision"],
        "bindings_fingerprint" => bindings_fingerprint
      }

      {:ok, context, pages}
    else
      _ -> invalid_cursor()
    end
  end

  defp context_and_pages(_snapshot, _source_id, _source_plan, _scope), do: invalid_cursor()

  defp paged_source?(%{"query" => %{"collections" => collections}}),
    do: paged_collections?(collections)

  defp paged_source?(_source_plan), do: false

  defp paged_collections?(collections) when is_list(collections) do
    Enum.any?(collections, fn
      %{"page_size" => size} when is_integer(size) and size > 0 -> true
      %{"collections" => children} -> paged_collections?(children)
      _ -> false
    end)
  end

  defp paged_collections?(_collections), do: false

  defp declared_page?(source_plan, %{"collection_path" => path}) do
    collections = get_in(source_plan, ["query", "collections"])

    case find_collection(collections, path) do
      %{"page_size" => size} when is_integer(size) and size > 0 -> true
      _ -> false
    end
  end

  defp find_collection(collections, [id | rest]) when is_list(collections) do
    case Enum.filter(collections, &match?(%{"id" => ^id}, &1)) do
      [collection] when rest == [] -> collection
      [collection] -> find_collection(collection["collections"], rest)
      _ -> nil
    end
  end

  defp find_collection(_collections, _path), do: nil

  defp clock_and_ttl(secret, opts)
       when is_binary(secret) and byte_size(secret) >= 32 and is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)

    if is_integer(now) and now >= 0 and is_integer(ttl) and ttl > 0 and
         ttl <= @default_ttl_seconds do
      {:ok, now, ttl}
    else
      invalid_cursor()
    end
  end

  defp clock_and_ttl(_secret, _opts), do: invalid_cursor()

  defp token_expiry(supplied, now, ttl) when is_binary(supplied) and byte_size(supplied) <= 128 do
    case Regex.run(~r/\Apc1\.([1-9][0-9]{0,11})\.[0-9a-f]{64}\z/, supplied) do
      [_, expiry] ->
        expires_at = String.to_integer(expiry)

        if expires_at >= now and expires_at <= now + ttl do
          {:ok, expires_at}
        else
          invalid_cursor()
        end

      _ ->
        invalid_cursor()
    end
  end

  defp token_expiry(_supplied, _now, _ttl), do: invalid_cursor()

  defp token(context, position, expires_at, secret) do
    payload = %{"context" => context, "position" => position, "expires_at" => expires_at}

    digest =
      :crypto.mac(:hmac, :sha256, secret, canonical_json(payload)) |> Base.encode16(case: :lower)

    "#{@token_version}.#{expires_at}.#{digest}"
  end

  defp position(page),
    do: Map.take(page, ["collection_path", "parent_path", "after_values"])

  defp valid_page?(
         %{
           "collection_path" => path,
           "parent_path" => parents,
           "has_more" => has_more,
           "after_values" => values
         } = page
       )
       when is_list(path) and path != [] and is_list(parents) and
              is_boolean(has_more) do
    Map.keys(page) |> Enum.sort() ==
      ["after_values", "collection_path", "has_more", "parent_path"] and
      length(path) == length(parents) and
      Enum.all?(path, &non_empty?/1) and
      Enum.all?(parents, &valid_key?/1) and
      if(has_more,
        do:
          is_list(values) and values != [] and Enum.all?(values, &valid_seek_value?/1) and
            valid_key?(List.last(values)),
        else: is_nil(values)
      )
  end

  defp valid_page?(_page), do: false

  defp valid_key?(value) when is_binary(value), do: value != ""
  defp valid_key?(value) when is_integer(value) or is_float(value), do: true
  defp valid_key?(_value), do: false

  defp valid_seek_value?(nil), do: true
  defp valid_seek_value?(value) when is_binary(value), do: true
  defp valid_seek_value?(value) when is_integer(value) or is_float(value), do: true
  defp valid_seek_value?(_value), do: false

  defp non_empty?(value), do: is_binary(value) and value != ""

  defp fingerprint(value) do
    {:ok,
     "sha256:" <> (:crypto.hash(:sha256, canonical_json(value)) |> Base.encode16(case: :lower))}
  rescue
    _ -> invalid_cursor()
  end

  defp canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {key, child} ->
        [Jason.encode!(key), ?:, canonical_json(child)]
      end)

    IO.iodata_to_binary([?{, Enum.intersperse(members, ?,), ?}])
  end

  defp canonical_json(value) when is_list(value) do
    IO.iodata_to_binary([?[, Enum.intersperse(Enum.map(value, &canonical_json/1), ?,), ?]])
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp invalid_cursor do
    {:error,
     %{
       "schema" => "selecto.template.page-cursor-diagnostic.v1",
       "code" => "invalid_page_cursor",
       "message" => "collection page cursor is invalid"
     }}
  end
end
