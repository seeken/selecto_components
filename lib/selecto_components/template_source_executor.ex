defmodule SelectoComponents.TemplateSourceExecutor do
  @moduledoc """
  Executes a template source through fresh authority supplied by the host.

  The compiled manifest may describe query intent, but it cannot provide a
  connection, tenant, actor, or authorization scope. The host authorization
  callback is invoked for every effect and must return an already scoped
  `%Selecto{}`. Lowering can only add the compiled source constraints.

  Before execution, the host's effective root limit and every nested
  `max-items` bound must fit the source resource budget. The default allows
  100 roots, 10,000 projected nodes, three collection levels, two data
  statements per source read, and 1 MiB each
  for source-effect input and projected JSON; trusted
  hosts can override these with `:resource_budget` in `execute/4` options.
  Projected results are checked again against the effective root limit and
  each compiled collection limit before they are returned.

  A trusted host can opt into a root keyset read with `root_cursor: :first` or
  `root_cursor: token`. Continuations require `:root_snapshot` and
  `:root_secret`; the executor reauthorizes before resolving the token. These
  options must be assembled by the host, never copied from request parameters.
  """

  @type authorize :: (map(), map() ->
                        {:ok, Selecto.t()}
                        | {:ok, Selecto.t(), map()}
                        | {:error, term()})

  @default_resource_budget %{
    max_root_rows: 100,
    max_result_nodes: 10_000,
    max_collection_depth: 3,
    max_source_statements: 2,
    max_input_bytes: 1_048_576,
    max_result_bytes: 1_048_576
  }

  @spec execute(map(), map(), authorize(), keyword()) :: {:ok, [map()] | map()} | {:error, map()}
  def execute(manifest, effect, authorize, opts \\ [])

  def execute(%{"sources" => sources} = manifest, effect, authorize, opts)
      when is_list(sources) and is_map(effect) and is_function(authorize, 2) and is_list(opts) do
    with :ok <- valid_effect(effect),
         {:ok, budget} <- resource_budget(Keyword.get(opts, :resource_budget)),
         :ok <- check_input_bytes(effect, budget),
         {:ok, source} <- find_source(sources, effect["source"]),
         {:ok, authorized} <- authorize(source, effect, authorize),
         {:ok, lowered} <- lower_source(manifest, source, effect, authorized, opts),
         :ok <- check_resource_budget(lowered, budget),
         :ok <- check_statement_budget(source, lowered, budget),
         {:ok, rows, totals} <-
           execute_source_read(source, lowered, authorized.query, effect, opts),
         {:ok, projected} <- project(lowered.result_shape, rows),
         {:ok, projected} <- merge_page_result(lowered, projected, effect, opts),
         {:ok, projected, root_page} <- project_root_page(lowered, projected),
         {:ok, projected} <- attach_source_totals(source, projected, totals),
         {:ok, projected} <- attach_root_page(projected, root_page),
         :ok <-
           check_projected_nodes(
             projected_rows(projected),
             lowered.result_shape,
             lowered.query.set.limit,
             budget
           ),
         :ok <- check_result_bytes(projected, budget) do
      {:ok, projected}
    end
  rescue
    _exception ->
      {:error, diagnostic("source_execution_failed", "template source execution failed")}
  catch
    _kind, _reason ->
      {:error, diagnostic("source_execution_failed", "template source execution failed")}
  end

  def execute(_manifest, _effect, _authorize, _opts),
    do: {:error, diagnostic("invalid_source_effect", "template source effect is invalid")}

  defp valid_effect(%{
         "schema" => "selecto.template.runtime-effect.v1",
         "kind" => "load_source",
         "effect_id" => effect_id,
         "source" => source,
         "generation" => generation,
         "bindings" => %{"input" => inputs, "state" => state}
       })
       when is_binary(effect_id) and effect_id != "" and is_binary(source) and source != "" and
              is_integer(generation) and generation > 0 and is_map(inputs) and is_map(state),
       do: :ok

  defp valid_effect(_effect),
    do: {:error, diagnostic("invalid_source_effect", "template source effect is invalid")}

  defp find_source(sources, source_id) do
    case Enum.find(sources, &source_named?(&1, source_id)) do
      nil -> {:error, diagnostic("unknown_source", "template source is not declared")}
      source -> {:ok, source}
    end
  end

  defp source_named?(%{"id" => id}, expected), do: id == expected
  defp source_named?(_source, _expected), do: false

  defp authorize(source, effect, callback) do
    case callback.(source, effect) do
      {:ok, %Selecto{} = selecto} ->
        {:ok, %{query: selecto, scope: nil}}

      {:ok, %Selecto{} = selecto, %{} = scope} ->
        {:ok, %{query: selecto, scope: scope}}

      _other ->
        {:error,
         diagnostic("source_authorization_failed", "template source authorization failed")}
    end
  end

  defp lower_source(manifest, source, effect, %{query: selecto, scope: scope}, opts) do
    cond do
      Keyword.has_key?(opts, :root_cursor) and Keyword.has_key?(opts, :page_cursor) ->
        invalid_root_cursor()

      Keyword.get(opts, :root_cursor) == :first ->
        SelectoTemplates.lower_root_cursor_query(source, selecto, effect["bindings"])

      Keyword.has_key?(opts, :root_cursor) ->
        snapshot = Keyword.get(opts, :root_snapshot)
        secret = Keyword.get(opts, :root_secret)
        cursor_opts = Keyword.take(opts, [:now, :ttl_seconds])

        with :ok <- current_root_effect(manifest, snapshot, effect),
             {:ok, position} <-
               SelectoComponents.TemplateRootCursor.resolve(
                 snapshot,
                 source["id"],
                 source,
                 scope,
                 secret,
                 Keyword.get(opts, :root_cursor),
                 cursor_opts
               ),
             {:ok, lowered} <-
               SelectoTemplates.lower_root_cursor_query(
                 source,
                 selecto,
                 effect["bindings"],
                 position
               ) do
          {:ok, Map.put(lowered, :root_position, position)}
        end

      true ->
        lower_collection_source(manifest, source, effect, selecto, scope, opts)
    end
  end

  defp lower_collection_source(manifest, source, effect, selecto, scope, opts) do
    case Keyword.fetch(opts, :page_cursor) do
      :error ->
        SelectoTemplates.lower_query(source, selecto, effect["bindings"])

      {:ok, token} ->
        snapshot = Keyword.get(opts, :page_snapshot)
        secret = Keyword.get(opts, :page_secret)
        cursor_opts = Keyword.take(opts, [:now, :ttl_seconds])

        with :ok <- current_page_effect(manifest, snapshot, effect),
             {:ok, position} <-
               SelectoComponents.TemplatePageCursor.resolve(
                 snapshot,
                 source["id"],
                 source,
                 scope,
                 secret,
                 token,
                 cursor_opts
               ),
             {:ok, narrowed_source} <-
               SelectoTemplates.narrow_collection_page(
                 source,
                 get_in(snapshot, ["sources", source["id"], "result"]),
                 position
               ),
             {:ok, scoped_selecto} <- scope_page_root(selecto, source, position) do
          case SelectoTemplates.lower_page_query(
                 without_root_offset(narrowed_source),
                 scoped_selecto,
                 effect["bindings"],
                 position
               ) do
            {:ok, lowered} -> {:ok, Map.put(lowered, :page_position, position)}
            failure -> failure
          end
        end
    end
  end

  # The signed collection position identifies a root already visible in the
  # server-held page. Applying the source's offset again after constraining
  # the fresh host query to that root would skip it.
  defp without_root_offset(source),
    do: update_in(source, ["query"], &Map.delete(&1, "page"))

  defp scope_page_root(%Selecto{domain: domain} = selecto, source, position) do
    root = Map.get(domain, :source) || Map.get(domain, "source") || %{}
    primary_key = Map.get(root, :primary_key) || Map.get(root, "primary_key")
    primary_key = if is_atom(primary_key), do: Atom.to_string(primary_key), else: primary_key
    parent_path = position["parent_path"]
    selections = get_in(source, ["query", "select"])

    if is_binary(primary_key) and is_list(selections) and primary_key in selections and
         is_list(parent_path) and parent_path != [] and
         (is_integer(hd(parent_path)) or is_binary(hd(parent_path))) do
      try do
        {:ok, Selecto.filter(selecto, {primary_key, hd(parent_path)})}
      rescue
        _ -> invalid_page_cursor()
      end
    else
      invalid_page_cursor()
    end
  end

  defp current_root_effect(manifest, snapshot, effect) do
    case current_page_effect(manifest, snapshot, effect) do
      :ok -> :ok
      _ -> invalid_root_cursor()
    end
  end

  defp invalid_root_cursor do
    {:error,
     %{
       "schema" => "selecto.template.page-cursor-diagnostic.v1",
       "code" => "invalid_root_cursor",
       "message" => "root page cursor is invalid"
     }}
  end

  defp current_page_effect(manifest, snapshot, effect)
       when is_map(manifest) and is_map(snapshot) do
    source = effect["source"]
    generation = effect["generation"]

    if snapshot["template_fingerprint"] == get_in(manifest, ["template", "fingerprint"]) do
      if get_in(snapshot, ["sources", source, "generation"]) == generation and
           effect["effect_id"] == "#{snapshot["instance_id"]}:source:#{source}:#{generation}" and
           effect["bindings"] == %{
             "input" => snapshot["inputs"],
             "state" => snapshot["state"]
           } do
        :ok
      else
        invalid_page_cursor()
      end
    else
      invalid_page_cursor()
    end
  end

  defp current_page_effect(_manifest, _snapshot, _effect), do: invalid_page_cursor()

  defp invalid_page_cursor do
    {:error,
     %{
       "schema" => "selecto.template.page-cursor-diagnostic.v1",
       "code" => "invalid_page_cursor",
       "message" => "collection page cursor is invalid"
     }}
  end

  defp merge_page_result(%{page_position: position, result_shape: shape}, incoming, effect, opts)
       when is_map(position) do
    current = get_in(Keyword.get(opts, :page_snapshot), ["sources", effect["source"], "result"])
    max_items = collection_max_items(shape["collections"], position["collection_path"])

    SelectoTemplates.merge_collection_page(shape, current, incoming, position, max_items)
  end

  defp merge_page_result(_lowered, projected, _effect, _opts), do: {:ok, projected}

  defp project_root_page(%{cursor_page: config}, projected) do
    rows = projected_rows(projected)

    with {:ok, %{"items" => visible, "has_more" => has_more, "after_values" => values}} <-
           SelectoTemplates.project_root_cursor_page(config, rows),
         {:ok, result} <- visible_root_result(projected, visible, config["primary_key"]) do
      {:ok, result, %{"config" => config, "has_more" => has_more, "after_values" => values}}
    else
      _ -> {:error, diagnostic("invalid_source_result", "template source result is invalid")}
    end
  end

  defp project_root_page(_lowered, projected), do: {:ok, projected, nil}

  defp visible_root_result(rows, visible, _primary_key) when is_list(rows),
    do: {:ok, visible}

  defp visible_root_result(
         %{"rows" => _rows, "pages" => pages, "identities" => identities} = result,
         visible,
         primary_key
       )
       when is_list(pages) and is_list(identities) do
    keys = MapSet.new(Enum.map(visible, &Map.fetch!(&1, primary_key)))

    if Enum.sort(Map.keys(result)) == ["identities", "pages", "rows"] and
         Enum.all?(pages ++ identities, fn
           %{"parent_path" => [root | _]} -> not is_nil(root)
           _ -> false
         end) do
      retain = fn entry -> MapSet.member?(keys, hd(entry["parent_path"])) end

      {:ok,
       %{
         "rows" => visible,
         "pages" => Enum.filter(pages, retain),
         "identities" => Enum.filter(identities, retain)
       }}
    else
      {:error, :invalid_root_metadata}
    end
  end

  defp visible_root_result(_projected, _visible, _primary_key),
    do: {:error, :invalid_root_metadata}

  defp attach_root_page(projected, nil), do: {:ok, projected}

  defp attach_root_page(projected, page) when is_list(projected),
    do: {:ok, %{"rows" => projected, "root_page" => page}}

  defp attach_root_page(%{"rows" => _} = projected, page),
    do: {:ok, Map.put(projected, "root_page", page)}

  defp attach_root_page(_projected, _page),
    do: {:error, diagnostic("invalid_source_result", "template source result is invalid")}

  defp collection_max_items(collections, [id | rest]) when is_list(collections) do
    case Enum.filter(collections, &match?(%{"id" => ^id}, &1)) do
      [collection] when rest == [] -> collection["max_items"]
      [collection] -> collection_max_items(collection["collections"], rest)
      _ -> nil
    end
  end

  defp collection_max_items(_collections, _path), do: nil

  defp check_resource_budget(lowered, budget) do
    with root_rows when is_integer(root_rows) and root_rows > 0 <- lowered.query.set.limit,
         :ok <- within_limit(root_rows, budget.max_root_rows),
         {:ok, nodes_per_root} <-
           count_nodes(lowered.result_shape["collections"], 1, budget),
         :ok <- within_limit(root_rows * nodes_per_root, budget.max_result_nodes) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, diagnostic("invalid_source_shape", "template source shape is invalid")}
    end
  end

  defp check_statement_budget(source, lowered, budget) do
    case statement_roles(source, lowered) do
      {:ok, roles} -> within_limit(length(roles), budget.max_source_statements)
      {:error, error} -> {:error, error}
    end
  end

  defp statement_roles(source, lowered) do
    case get_in(source, ["query", "source_totals"]) || [] do
      declarations when is_list(declarations) ->
        if Map.has_key?(lowered, :page_position) do
          {:ok, ["page"]}
        else
          valid? = Enum.all?(declarations, &valid_source_total?/1)

          if valid? do
            roles =
              declarations
              |> Enum.filter(&external_total?/1)
              |> Enum.map(fn %{"id" => id, "scope" => scope} -> "#{scope}_total:#{id}" end)
              |> Enum.sort()

            {:ok, ["page" | roles]}
          else
            {:error, diagnostic("invalid_source_shape", "template source shape is invalid")}
          end
        end

      _ ->
        {:error, diagnostic("invalid_source_shape", "template source shape is invalid")}
    end
  end

  defp valid_source_total?(%{"id" => id, "scope" => scope, "function" => function} = total)
       when is_binary(id) and id != "" and scope in ["page", "filtered"] do
    case Map.get(total, "association") do
      nil ->
        function == "count"

      association when is_binary(association) and association != "" ->
        function in ["count", "sum"] and
          Enum.all?([total["target_schema"], total["field"]], &(is_binary(&1) and &1 != ""))

      _ ->
        false
    end
  end

  defp valid_source_total?(_), do: false

  defp external_total?(%{"scope" => "filtered"}), do: true
  defp external_total?(%{"association" => association}) when is_binary(association), do: true
  defp external_total?(_), do: false

  defp resource_budget(nil), do: {:ok, @default_resource_budget}

  defp resource_budget(overrides) when is_map(overrides) do
    budget = Map.merge(@default_resource_budget, overrides)

    if Enum.all?(@default_resource_budget, fn {key, _default} ->
         value = Map.get(budget, key)
         is_integer(value) and value > 0
       end) and Enum.all?(Map.keys(overrides), &Map.has_key?(@default_resource_budget, &1)) do
      {:ok, budget}
    else
      {:error, diagnostic("invalid_source_budget", "host source budget is invalid")}
    end
  end

  defp resource_budget(_overrides),
    do: {:error, diagnostic("invalid_source_budget", "host source budget is invalid")}

  defp count_nodes(collections, depth, budget) when is_list(collections) do
    Enum.reduce_while(collections, {:ok, 1}, fn collection, {:ok, count} ->
      case count_collection(collection, depth, budget) do
        {:ok, child_count} -> {:cont, {:ok, count + child_count}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp count_nodes(_collections, _depth, _budget),
    do: {:error, diagnostic("invalid_source_shape", "template source shape is invalid")}

  defp count_collection(%{"max_items" => max_items, "collections" => nested}, depth, budget)
       when is_integer(max_items) and max_items > 0 and is_list(nested) do
    with :ok <- within_limit(depth, budget.max_collection_depth),
         {:ok, nodes_per_child} <- count_nodes(nested, depth + 1, budget) do
      {:ok, max_items * nodes_per_child}
    end
  end

  defp count_collection(%{"collections" => _nested}, _depth, _budget),
    do: {:error, diagnostic("unbounded_collection", "template collection has no row bound")}

  defp count_collection(_collection, _depth, _budget),
    do: {:error, diagnostic("invalid_source_shape", "template source shape is invalid")}

  defp within_limit(value, maximum) when value <= maximum, do: :ok

  defp within_limit(_value, _maximum),
    do: {:error, diagnostic("source_budget_exceeded", "template source exceeds host budget")}

  defp check_input_bytes(effect, budget) do
    case Jason.encode_to_iodata(effect) do
      {:ok, encoded} ->
        if IO.iodata_length(encoded) <= budget.max_input_bytes do
          :ok
        else
          {:error,
           diagnostic("source_input_too_large", "template source input exceeds host byte budget")}
        end

      {:error, _reason} ->
        {:error, diagnostic("invalid_source_effect", "template source effect is invalid")}
    end
  end

  defp check_result_bytes(projected, budget) do
    case Jason.encode_to_iodata(projected) do
      {:ok, encoded} ->
        if IO.iodata_length(encoded) <= budget.max_result_bytes do
          :ok
        else
          {:error,
           diagnostic(
             "source_result_too_large",
             "template source result exceeds host byte budget"
           )}
        end

      {:error, _reason} ->
        {:error, diagnostic("invalid_source_result", "template source result is invalid")}
    end
  end

  defp check_projected_nodes(rows, %{"collections" => collections}, root_limit, budget)
       when is_list(rows) and is_list(collections) do
    with :ok <- within_limit(length(rows), root_limit),
         :ok <- within_limit(length(rows), budget.max_root_rows),
         {:ok, actual_nodes} <- count_projected_rows(rows, collections, budget),
         :ok <- within_limit(actual_nodes, budget.max_result_nodes) do
      :ok
    end
  end

  defp check_projected_nodes(_rows, _shape, _root_limit, _budget),
    do: {:error, diagnostic("invalid_source_result", "template source result is invalid")}

  defp count_projected_rows(rows, collections, budget) do
    Enum.reduce_while(rows, {:ok, 0}, fn row, {:ok, total} ->
      case count_projected_row(row, collections, budget) do
        {:ok, count} when total + count <= budget.max_result_nodes ->
          {:cont, {:ok, total + count}}

        {:ok, _count} ->
          {:halt,
           {:error, diagnostic("source_budget_exceeded", "template source exceeds host budget")}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp count_projected_row(row, collections, budget) when is_map(row) do
    Enum.reduce_while(collections, {:ok, 1}, fn collection, {:ok, total} ->
      items = Map.get(row, collection["id"])

      with true <- is_list(items),
           :ok <- within_limit(length(items), collection["max_items"]),
           {:ok, count} <- count_projected_rows(items, collection["collections"], budget),
           :ok <- within_limit(total + count, budget.max_result_nodes) do
        {:cont, {:ok, total + count}}
      else
        false ->
          {:halt,
           {:error, diagnostic("invalid_source_result", "template source result is invalid")}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp count_projected_row(_row, _collections, _budget),
    do: {:error, diagnostic("invalid_source_result", "template source result is invalid")}

  defp execute_query(query, opts) do
    execute = Keyword.get(opts, :execute, &Selecto.execute/2)
    execute_opts = Keyword.get(opts, :execute_options, [])

    if is_function(execute, 2) and is_list(execute_opts) do
      case execute.(query, execute_opts) do
        {:ok, {rows, _columns, _aliases}} when is_list(rows) ->
          {:ok, rows}

        _other ->
          {:error, diagnostic("source_execution_failed", "template source execution failed")}
      end
    else
      {:error, diagnostic("invalid_source_executor", "template source executor is invalid")}
    end
  end

  defp execute_source_read(source, lowered, authorized_query, effect, opts) do
    declarations = get_in(source, ["query", "source_totals"]) || []
    external = Enum.filter(declarations, &external_total?/1)

    cond do
      Map.has_key?(lowered, :page_position) ->
        with {:ok, rows} <- execute_query(lowered.query, opts) do
          {:ok, rows, nil}
        end

      external == [] ->
        with {:ok, rows} <- execute_query(lowered.query, opts) do
          {:ok, rows, if(declarations == [], do: nil, else: %{})}
        end

      true ->
        with {:ok, roles} <- statement_roles(source, lowered),
             {:ok, total_queries} <-
               lower_source_totals(
                 source,
                 external,
                 authorized_query,
                 effect["bindings"],
                 Map.get(lowered, :root_position)
               ),
             execute_snapshot when is_function(execute_snapshot, 3) <-
               Keyword.get(opts, :execute_snapshot),
             execute_opts when is_list(execute_opts) <- Keyword.get(opts, :execute_options, []),
             {:ok, {rows, totals}} when is_list(rows) and is_map(totals) <-
               execute_snapshot.(
                 lowered.query,
                 total_queries,
                 Keyword.put(execute_opts, :statement_roles, roles)
               ) do
          {:ok, rows, totals}
        else
          nil ->
            {:error,
             diagnostic("source_snapshot_unavailable", "template source snapshot is unavailable")}

          {:error, %{} = error} ->
            {:error, error}

          {:error, _reason} ->
            {:error, diagnostic("source_execution_failed", "template source execution failed")}

          _ ->
            {:error, diagnostic("source_execution_failed", "template source execution failed")}
        end
    end
  end

  defp lower_source_totals(source, declarations, authorized_query, bindings, root_position) do
    Enum.reduce_while(declarations, {:ok, %{}}, fn %{"id" => id} = declaration, {:ok, queries} ->
      result =
        if Map.has_key?(declaration, "association") do
          with {:ok, %{query: query, column: column}} <-
                 SelectoTemplates.lower_declared_related_total(
                   source,
                   authorized_query,
                   bindings,
                   id,
                   root_position
                 ) do
            {:ok, %{query: query, column: column, function: declaration["function"]}}
          end
        else
          SelectoTemplates.lower_declared_filtered_total(
            source,
            authorized_query,
            bindings,
            id
          )
        end

      case result do
        {:ok, query} -> {:cont, {:ok, Map.put(queries, id, query)}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp attach_source_totals(_source, projected, nil), do: {:ok, projected}

  defp attach_source_totals(source, projected, totals) do
    case SelectoTemplates.attach_source_totals(source, projected, totals) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} ->
        {:error, diagnostic("invalid_source_result", "template source result is invalid")}
    end
  end

  defp project(result_shape, rows) do
    projector =
      if paged_collections?(result_shape["collections"]),
        do: &SelectoTemplates.project_rows_with_pages/2,
        else: &SelectoTemplates.project_rows/2

    case projector.(result_shape, rows) do
      {:ok, projected} ->
        {:ok, projected}

      {:error, _reason} ->
        {:error, diagnostic("invalid_source_result", "template source result is invalid")}
    end
  end

  defp projected_rows(%{"rows" => rows}) when is_list(rows),
    do: rows

  defp projected_rows(rows), do: rows

  defp paged_collections?(collections) when is_list(collections) do
    Enum.any?(collections, fn
      %{"page_size" => _size} -> true
      %{"collections" => children} -> paged_collections?(children)
      _ -> false
    end)
  end

  defp paged_collections?(_), do: false

  defp diagnostic(code, message) do
    %{
      "schema" => "selecto.template.diagnostic.v1",
      "severity" => "error",
      "code" => code,
      "message" => message,
      "path" => []
    }
  end
end
