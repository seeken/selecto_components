defmodule SelectoComponents.TemplateEffectRunner do
  @moduledoc false

  alias Phoenix.Component
  alias SelectoComponents.TemplateInstance
  import Phoenix.LiveView, only: [cancel_async: 2, connected?: 1, start_async: 3]

  @running_assign :template_running_effects
  @default_source_timeout_ms 15_000
  @default_max_concurrent_effects 4

  @type diagnostic :: map()

  @spec initialize(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def initialize(socket), do: Component.assign(socket, @running_assign, %{})

  @spec start_effects(
          Phoenix.LiveView.Socket.t(),
          (map() -> {:ok, term()} | {:error, term()}),
          keyword()
        ) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def start_effects(socket, executor, opts \\ [])

  def start_effects(socket, executor, opts)
      when is_function(executor, 1) and is_list(opts) do
    if connected?(socket) do
      with {:ok, _manifest, snapshot} <- TemplateInstance.runtime(socket),
           :ok <- valid_effects(Map.get(socket.assigns, :template_pending_effects, [])),
           {:ok, timeout_ms, max_concurrent} <- runner_limits(opts) do
        identity = Map.take(snapshot, ["instance_id", "release_id"])
        {effects, socket} = TemplateInstance.take_effects(socket)

        socket =
          Enum.reduce(effects, socket, fn effect, current ->
            source = effect["source"]
            key = async_key(source, effect["generation"])
            running = Map.get(current.assigns, @running_assign, %{})
            previous_key = Map.get(running, source)
            current = maybe_cancel_async(current, previous_key)
            running = Map.delete(running, source)

            if map_size(running) >= max_concurrent do
              current
              |> Component.assign(@running_assign, running)
              |> reject_busy_effect(identity, effect)
            else
              current
              |> start_async(key, fn -> execute_effect(identity, effect, executor, timeout_ms) end)
              |> Component.assign(@running_assign, Map.put(running, source, key))
            end
          end)

        {:ok, socket}
      else
        {:error, error} -> TemplateInstance.assign_error(socket, error)
      end
    else
      {:ok, socket}
    end
  end

  def start_effects(socket, _executor, _opts) do
    TemplateInstance.assign_error(
      socket,
      TemplateInstance.diagnostic(
        "invalid_effect_executor",
        "template effect executor is invalid"
      )
    )
  end

  @spec start_source_effects(
          Phoenix.LiveView.Socket.t(),
          SelectoComponents.TemplateSourceExecutor.authorize(),
          keyword()
        ) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def start_source_effects(socket, authorize, opts \\ [])

  def start_source_effects(socket, authorize, opts)
      when is_function(authorize, 2) and is_list(opts) do
    with {:ok, manifest, _snapshot} <- TemplateInstance.runtime(socket) do
      start_effects(
        socket,
        fn effect ->
          SelectoComponents.TemplateSourceExecutor.execute(manifest, effect, authorize, opts)
        end,
        opts
      )
    else
      {:error, error} -> TemplateInstance.assign_error(socket, error)
    end
  end

  def start_source_effects(socket, _authorize, _opts) do
    TemplateInstance.assign_error(
      socket,
      TemplateInstance.diagnostic(
        "invalid_effect_executor",
        "template effect executor is invalid"
      )
    )
  end

  @spec handle_async(term(), {:ok, map()} | {:exit, term()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_async(
        {:selecto_template_source, source, generation} = key,
        {:ok, completion},
        socket
      )
      when is_binary(source) and is_integer(generation) and is_map(completion) do
    socket = clear_running_effect(socket, source, key)

    case TemplateInstance.complete(socket, completion) do
      {:ok, socket} -> {:noreply, socket}
      {:error, _diagnostic, socket} -> {:noreply, socket}
    end
  end

  def handle_async(
        {:selecto_template_source, source, generation} = key,
        {:exit, _reason},
        socket
      )
      when is_binary(source) and is_integer(generation) do
    socket = clear_running_effect(socket, source, key)

    case failed_effect_completion(socket, source, generation, %{
           "code" => "effect_task_failed",
           "message" => "template source task failed"
         }) do
      {:ok, completion} ->
        case TemplateInstance.complete(socket, completion) do
          {:ok, socket} -> {:noreply, socket}
          {:error, _diagnostic, socket} -> {:noreply, socket}
        end

      {:error, diagnostic} ->
        {:noreply, elem(TemplateInstance.assign_error(socket, diagnostic), 2)}
    end
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp valid_effects(effects) when is_list(effects) do
    if Enum.all?(effects, &valid_effect?/1) do
      :ok
    else
      {:error, TemplateInstance.diagnostic("invalid_effect", "template effect queue is invalid")}
    end
  end

  defp valid_effects(_effects) do
    {:error, TemplateInstance.diagnostic("invalid_effect", "template effect queue is invalid")}
  end

  defp valid_effect?(%{
         "schema" => "selecto.template.runtime-effect.v1",
         "kind" => "load_source",
         "effect_id" => effect_id,
         "source" => source,
         "generation" => generation,
         "bindings" => %{"input" => inputs, "state" => state}
       }) do
    is_binary(effect_id) and effect_id != "" and is_binary(source) and source != "" and
      is_integer(generation) and generation > 0 and is_map(inputs) and is_map(state)
  end

  defp valid_effect?(_effect), do: false

  defp runner_limits(opts) do
    timeout_ms = Keyword.get(opts, :source_timeout_ms, @default_source_timeout_ms)
    max_concurrent = Keyword.get(opts, :max_concurrent_effects, @default_max_concurrent_effects)

    if is_integer(timeout_ms) and timeout_ms > 0 and timeout_ms <= 300_000 and
         is_integer(max_concurrent) and max_concurrent > 0 and max_concurrent <= 64 do
      {:ok, timeout_ms, max_concurrent}
    else
      {:error,
       TemplateInstance.diagnostic("invalid_effect_budget", "host effect budget is invalid")}
    end
  end

  defp reject_busy_effect(socket, identity, effect) do
    error = %{
      "code" => "source_workers_busy",
      "message" => "template source workers are busy"
    }

    case TemplateInstance.complete(socket, completion(identity, effect, {:error, error})) do
      {:ok, completed} ->
        completed

      {:error, diagnostic, returned} ->
        elem(TemplateInstance.assign_error(returned, diagnostic), 2)
    end
  end

  defp execute_effect(identity, effect, executor, timeout_ms) do
    task = Task.async(fn -> safely_execute_effect(effect, executor) end)

    result =
      case Task.yield(task, timeout_ms) do
        {:ok, result} ->
          result

        nil ->
          Task.shutdown(task, :brutal_kill)

          {:error,
           %{
             "code" => "source_timeout",
             "message" => "template source execution timed out"
           }}

        {:exit, _reason} ->
          {:error,
           %{
             "code" => "effect_execution_failed",
             "message" => "template source execution failed"
           }}
      end

    completion(identity, effect, result)
  end

  defp safely_execute_effect(effect, executor) do
    try do
      executor.(effect)
    rescue
      _exception ->
        {:error,
         %{
           "code" => "effect_execution_failed",
           "message" => "template source execution failed"
         }}
    catch
      _kind, _reason ->
        {:error,
         %{
           "code" => "effect_execution_failed",
           "message" => "template source execution failed"
         }}
    end
  end

  defp completion(identity, effect, {:ok, result}) do
    completion_identity(identity, effect)
    |> Map.merge(%{"outcome" => "ok", "result" => result})
  end

  defp completion(identity, effect, {:error, error}) do
    completion_identity(identity, effect)
    |> Map.merge(%{"outcome" => "error", "error" => error})
  end

  defp completion(identity, effect, _other) do
    completion(identity, effect, {
      :error,
      %{
        "code" => "invalid_effect_result",
        "message" => "template source executor returned an invalid result"
      }
    })
  end

  defp completion_identity(identity, effect) do
    %{
      "schema" => "selecto.template.runtime-completion.v1",
      "instance_id" => identity["instance_id"],
      "release_id" => identity["release_id"],
      "effect_id" => effect["effect_id"],
      "source" => effect["source"],
      "generation" => effect["generation"]
    }
  end

  defp failed_effect_completion(socket, source, generation, error) do
    with {:ok, _manifest, snapshot} <- TemplateInstance.runtime(socket),
         %{} <- snapshot["sources"][source] do
      effect = %{
        "effect_id" => "#{snapshot["instance_id"]}:source:#{source}:#{generation}",
        "source" => source,
        "generation" => generation
      }

      {:ok,
       completion(Map.take(snapshot, ["instance_id", "release_id"]), effect, {:error, error})}
    else
      nil ->
        {:error,
         TemplateInstance.diagnostic("invalid_effect", "template effect source is invalid")}

      {:error, diagnostic} ->
        {:error, diagnostic}
    end
  end

  defp maybe_cancel_async(socket, nil), do: socket
  defp maybe_cancel_async(socket, key), do: cancel_async(socket, key)

  defp clear_running_effect(socket, source, key) do
    running = Map.get(socket.assigns, @running_assign, %{})

    if running[source] == key do
      Component.assign(socket, @running_assign, Map.delete(running, source))
    else
      socket
    end
  end

  defp async_key(source, generation),
    do: {:selecto_template_source, source, generation}
end
