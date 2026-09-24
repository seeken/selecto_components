defmodule SelectoComponents.TemplatePageRunner do
  @moduledoc false

  alias Phoenix.Component
  alias SelectoComponents.{TemplateInstance, TemplatePageCursor, TemplateSourceExecutor}
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  @running_assign :template_running_pages
  @default_timeout_ms 15_000
  @default_max_concurrent 4

  def initialize(socket), do: Component.assign(socket, @running_assign, %{})

  @spec cursors(Phoenix.LiveView.Socket.t(), binary(), map(), binary(), keyword()) ::
          {:ok, [map()]} | {:error, map()}
  def cursors(socket, source_id, scope, secret, opts \\ []) do
    with {:ok, manifest, snapshot} <- TemplateInstance.runtime(socket),
         {:ok, source} <- source_plan(manifest, source_id) do
      TemplatePageCursor.issue(snapshot, source_id, source, scope, secret, opts)
    end
  end

  @spec start(
          Phoenix.LiveView.Socket.t(),
          binary(),
          binary(),
          TemplateSourceExecutor.authorize(),
          binary(),
          keyword()
        ) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, map(), Phoenix.LiveView.Socket.t()}
  def start(socket, source_id, token, authorize, secret, opts \\ []) do
    with true <- connected?(socket),
         true <- is_binary(token) and byte_size(token) <= 128,
         true <- is_function(authorize, 2),
         {:ok, timeout_ms, max_concurrent} <- limits(opts),
         {:ok, manifest, snapshot} <- TemplateInstance.runtime(socket),
         {:ok, _source} <- source_plan(manifest, source_id),
         {:ok, source_state} <- ready_source(snapshot, source_id),
         running <- Map.get(socket.assigns, @running_assign, %{}),
         true <- map_size(running) < max_concurrent do
      effect = %{
        "schema" => "selecto.template.runtime-effect.v1",
        "kind" => "load_source",
        "effect_id" =>
          "#{snapshot["instance_id"]}:source:#{source_id}:#{source_state["generation"]}",
        "source" => source_id,
        "generation" => source_state["generation"],
        "bindings" => %{"input" => snapshot["inputs"], "state" => snapshot["state"]}
      }

      key =
        {:selecto_template_page, source_id, source_state["generation"], source_state["page"],
         make_ref()}

      executor_opts =
        opts
        |> Keyword.drop([
          :page_snapshot,
          :page_cursor,
          :page_secret,
          :source_timeout_ms,
          :max_concurrent_pages
        ])
        |> Keyword.merge(page_snapshot: snapshot, page_cursor: token, page_secret: secret)

      commit_identity = %{
        "schema" => "selecto.template.runtime-page-commit.v1",
        "instance_id" => snapshot["instance_id"],
        "release_id" => snapshot["release_id"],
        "source" => source_id,
        "generation" => source_state["generation"],
        "expected_state_revision" => snapshot["state_revision"],
        "expected_page" => source_state["page"]
      }

      socket =
        socket
        |> start_async(key, fn ->
          execute_page(manifest, effect, authorize, executor_opts, commit_identity, timeout_ms)
        end)
        |> Component.assign(@running_assign, Map.put(running, key, true))

      {:ok, socket}
    else
      {:error, diagnostic} ->
        TemplateInstance.assign_error(socket, diagnostic)

      _ ->
        TemplateInstance.assign_error(
          socket,
          TemplateInstance.diagnostic(
            "invalid_page_request",
            "collection page request is invalid"
          )
        )
    end
  end

  def handle_async({:selecto_template_page, _, _, _, _} = key, {:ok, {:ok, commit}}, socket) do
    socket = clear_running(socket, key)

    case TemplateInstance.commit_page(socket, commit) do
      {:ok, socket} -> {:noreply, socket}
      {:error, _diagnostic, socket} -> {:noreply, socket}
    end
  end

  def handle_async({:selecto_template_page, _, _, _, _} = key, {:ok, {:error, error}}, socket) do
    {:noreply, elem(TemplateInstance.assign_error(clear_running(socket, key), error), 2)}
  end

  def handle_async({:selecto_template_page, _, _, _, _} = key, {:exit, _reason}, socket) do
    error = TemplateInstance.diagnostic("page_task_failed", "collection page task failed")
    {:noreply, elem(TemplateInstance.assign_error(clear_running(socket, key), error), 2)}
  end

  defp execute_page(manifest, effect, authorize, opts, identity, timeout_ms) do
    task = Task.async(fn -> TemplateSourceExecutor.execute(manifest, effect, authorize, opts) end)

    case Task.yield(task, timeout_ms) do
      {:ok, {:ok, result}} ->
        {:ok, Map.put(identity, "result", result)}

      {:ok, {:error, diagnostic}} ->
        {:error, diagnostic}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, TemplateInstance.diagnostic("page_timeout", "collection page timed out")}

      _ ->
        {:error, TemplateInstance.diagnostic("page_task_failed", "collection page task failed")}
    end
  end

  defp source_plan(%{"sources" => sources}, source_id)
       when is_list(sources) and is_binary(source_id) and source_id != "" do
    case Enum.filter(sources, &match?(%{"id" => ^source_id}, &1)) do
      [source] ->
        {:ok, source}

      _ ->
        {:error, TemplateInstance.diagnostic("unknown_source", "template source is not declared")}
    end
  end

  defp source_plan(_manifest, _source_id),
    do: {:error, TemplateInstance.diagnostic("unknown_source", "template source is not declared")}

  defp ready_source(snapshot, source_id) do
    case get_in(snapshot, ["sources", source_id]) do
      %{"status" => "ready", "generation" => generation, "page" => page} = source
      when is_integer(generation) and generation > 0 and is_integer(page) and page > 0 ->
        {:ok, source}

      _ ->
        {:error, TemplateInstance.diagnostic("source_not_ready", "template source is not ready")}
    end
  end

  defp limits(opts) when is_list(opts) do
    timeout = Keyword.get(opts, :source_timeout_ms, @default_timeout_ms)
    concurrent = Keyword.get(opts, :max_concurrent_pages, @default_max_concurrent)

    if is_integer(timeout) and timeout > 0 and timeout <= 300_000 and
         is_integer(concurrent) and concurrent > 0 and concurrent <= 64 do
      {:ok, timeout, concurrent}
    else
      {:error, TemplateInstance.diagnostic("invalid_page_budget", "page budget is invalid")}
    end
  end

  defp limits(_opts),
    do: {:error, TemplateInstance.diagnostic("invalid_page_budget", "page budget is invalid")}

  defp clear_running(socket, key) do
    running = Map.get(socket.assigns, @running_assign, %{})
    Component.assign(socket, @running_assign, Map.delete(running, key))
  end
end
