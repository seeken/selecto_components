defmodule SelectoComponents.TemplateRootCursor do
  @moduledoc """
  Issues opaque root-page cursors from a server-held template snapshot.

  The token reveals only its expiry and a keyed digest. Resolution compares it
  with the current server-held page after the caller obtains fresh tenant and
  authorization scope; browser input never becomes a trusted seek tuple.
  """

  @token_version "rc1"
  @default_ttl_seconds 900

  @spec issue(map(), binary(), map(), map(), binary(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def issue(snapshot, source_id, source_plan, scope, secret, opts \\ []) do
    with {:ok, context, page} <- context_and_page(snapshot, source_id, source_plan, scope),
         {:ok, now, ttl} <- clock_and_ttl(secret, opts) do
      {:ok,
       %{
         "has_more" => page["has_more"],
         "token" =>
           if(page["has_more"],
             do: token(context, position(page), now + ttl, secret),
             else: nil
           )
       }}
    end
  end

  @spec resolve(map(), binary(), map(), map(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def resolve(snapshot, source_id, source_plan, scope, secret, supplied, opts \\ []) do
    with {:ok, context, %{"has_more" => true} = page} <-
           context_and_page(snapshot, source_id, source_plan, scope),
         {:ok, now, ttl} <- clock_and_ttl(secret, opts),
         {:ok, expires_at} <- token_expiry(supplied, now, ttl),
         expected <- token(context, position(page), expires_at, secret),
         true <- Plug.Crypto.secure_compare(expected, supplied) do
      {:ok, position(page)}
    else
      _ -> invalid_cursor()
    end
  end

  defp context_and_page(snapshot, source_id, source_plan, scope)
       when is_map(snapshot) and is_binary(source_id) and is_map(source_plan) and is_map(scope) do
    source = get_in(snapshot, ["sources", source_id])
    result = if is_map(source), do: source["result"]

    with true <- non_empty?(snapshot["instance_id"]),
         true <- non_empty?(snapshot["release_id"]),
         true <- non_empty?(snapshot["template_fingerprint"]),
         true <- source_plan["id"] == source_id and non_empty?(source_id),
         true <- valid_scope?(scope),
         %{"generation" => generation, "status" => "ready"} <- source,
         true <- is_integer(generation) and generation > 0,
         %{"rows" => rows, "root_page" => page} <- result,
         true <- is_list(rows) and valid_page?(source_plan, snapshot["state"], rows, page),
         {:ok, source_fingerprint} <- fingerprint(source_plan),
         {:ok, bindings_fingerprint} <-
           fingerprint(%{"input" => snapshot["inputs"], "state" => snapshot["state"]}),
         {:ok, config_fingerprint} <- fingerprint(page["config"]) do
      {:ok,
       %{
         "schema" => "selecto.template.root-cursor.v1",
         "instance_id" => snapshot["instance_id"],
         "release_id" => snapshot["release_id"],
         "template_fingerprint" => snapshot["template_fingerprint"],
         "source_id" => source_id,
         "source_fingerprint" => source_fingerprint,
         "config_fingerprint" => config_fingerprint,
         "generation" => generation,
         "tenant_id" => scope["tenant_id"],
         "principal_id" => scope["principal_id"],
         "authorization_revision" => scope["authorization_revision"],
         "membership_revision" => scope["membership_revision"],
         "bindings_fingerprint" => bindings_fingerprint
       }, page}
    else
      _ -> invalid_cursor()
    end
  end

  defp context_and_page(_snapshot, _source_id, _source_plan, _scope), do: invalid_cursor()

  defp valid_scope?(scope) do
    Enum.all?(~w(tenant_id principal_id authorization_revision membership_revision), fn key ->
      non_empty?(scope[key])
    end)
  end

  defp valid_page?(
         source,
         state,
         rows,
         %{"config" => config, "has_more" => has_more, "after_values" => values} = page
       )
       when is_map(config) and is_boolean(has_more) do
    query = source["query"] || %{}
    orders = query["order_by"]
    primary_key = config["primary_key"]

    dynamic_ordering? =
      case query["ordering_choice"] do
        %{"choices" => choices, "binding" => %{"expression" => "state." <> name}}
        when is_list(choices) and is_map(state) ->
          name != "" and Map.get(state, name) in choices

        _ ->
          false
      end

    expected_orders =
      if dynamic_ordering? do
        config["order_by"]
      else
        if is_list(orders) and is_binary(primary_key) and
             Enum.any?(orders, &match?(%{"field" => ^primary_key}, &1)),
           do: orders,
           else: (orders || []) ++ [%{"field" => primary_key, "direction" => "asc"}]
      end

    valid_shape? =
      Map.keys(page) |> Enum.sort() == ["after_values", "config", "has_more"] and
        is_map(query) and is_integer(query["limit"]) and query["limit"] > 0 and
        not Map.has_key?(query, "page") and
        (dynamic_ordering? or (is_list(orders) and orders != [])) and
        config["page_size"] == query["limit"] and
        config["order_by"] == expected_orders and
        is_list(query["select"]) and primary_key in query["select"] and
        Enum.all?(expected_orders, &(&1["field"] in query["select"]))

    with true <- valid_shape?,
         {:ok, _} <- SelectoTemplates.project_root_cursor_page(config, rows),
         true <- if(has_more, do: length(rows) == config["page_size"], else: true),
         {:ok, expected_values} <-
           if(has_more,
             do: SelectoTemplates.root_cursor_position(config, List.last(rows)),
             else: {:ok, nil}
           ),
         true <-
           if(has_more,
             do: is_list(values) and values == expected_values,
             else: is_nil(values)
           ) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_page?(_source, _state, _rows, _page), do: false

  defp clock_and_ttl(secret, opts)
       when is_binary(secret) and byte_size(secret) >= 32 and is_list(opts) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    ttl = Keyword.get(opts, :ttl_seconds, @default_ttl_seconds)

    if is_integer(now) and now >= 0 and is_integer(ttl) and ttl > 0 and
         ttl <= @default_ttl_seconds,
       do: {:ok, now, ttl},
       else: invalid_cursor()
  end

  defp clock_and_ttl(_secret, _opts), do: invalid_cursor()

  defp token_expiry(supplied, now, ttl) when is_binary(supplied) and byte_size(supplied) <= 128 do
    case Regex.run(~r/\Arc1\.([1-9][0-9]{0,11})\.[0-9a-f]{64}\z/, supplied) do
      [_, expiry] ->
        expires_at = String.to_integer(expiry)

        if expires_at >= now and expires_at <= now + ttl,
          do: {:ok, expires_at},
          else: invalid_cursor()

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

  defp position(page), do: %{"after_values" => page["after_values"]}

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
      |> Enum.map(fn {key, child} -> [Jason.encode!(key), ?:, canonical_json(child)] end)

    IO.iodata_to_binary([?{, Enum.intersperse(members, ?,), ?}])
  end

  defp canonical_json(value) when is_list(value) do
    IO.iodata_to_binary([?[, Enum.intersperse(Enum.map(value, &canonical_json/1), ?,), ?]])
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp non_empty?(value), do: is_binary(value) and value != ""

  defp invalid_cursor do
    {:error,
     %{
       "schema" => "selecto.template.page-cursor-diagnostic.v1",
       "code" => "invalid_root_cursor",
       "message" => "root page cursor is invalid"
     }}
  end
end
