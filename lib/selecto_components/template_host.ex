defmodule SelectoComponents.TemplateHost do
  @moduledoc """
  Adapts the pure Selecto template runtime to a LiveView socket.

  The host owns authorization and effect execution. This module only stores the
  compiled manifest and runtime snapshot, constructs portable events from
  server-owned identity, and queues data-only effects for the host to drain.
  Mounting or dispatching through this module never performs database I/O.

  A host LiveView can forward its callbacks without giving the portable runtime
  access to the socket itself:

      {:ok, socket} =
        SelectoComponents.TemplateHost.mount(socket, manifest,
          instance_id: instance_id,
          release_id: release_id,
          inputs: public_inputs
        )

      {:ok, socket} =
        SelectoComponents.TemplateHost.dispatch(socket, "search_changed", %{
          "value" => params["value"]
        })

      {effects, socket} = SelectoComponents.TemplateHost.take_effects(socket)

  The host must attach fresh tenant and actor authority when it executes each
  effect. Runtime snapshots and effects intentionally contain no connection or
  authorization objects.
  """

  alias Phoenix.Component
  import Phoenix.LiveView, only: [cancel_async: 2, connected?: 1, start_async: 3]

  @manifest_assign :template_manifest
  @snapshot_assign :template_runtime_snapshot
  @effects_assign :template_pending_effects
  @running_assign :template_running_effects
  @observation_assign :template_last_observation
  @error_assign :template_runtime_error

  @type diagnostic :: map()

  @spec mount(Phoenix.LiveView.Socket.t(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, diagnostic()}
  def mount(socket, manifest, opts) when is_map(manifest) and is_list(opts) do
    runtime_opts =
      Keyword.take(opts, [:instance_id, :release_id, :inputs])

    case SelectoTemplates.mount_runtime(manifest, runtime_opts) do
      {:ok, observation} ->
        socket =
          socket
          |> Component.assign(@manifest_assign, manifest)
          |> Component.assign(@effects_assign, [])
          |> Component.assign(@running_assign, %{})
          |> assign_observation(observation)

        {:ok, socket}

      {:error, diagnostic} ->
        {:error, diagnostic}
    end
  end

  def mount(_socket, _manifest, _opts),
    do: {:error, diagnostic("invalid_host_mount", "template host mount is invalid")}

  @doc """
  Applies a declared event using the instance, release, and revision in the
  server-owned snapshot.

  `:event_id` and `:expected_state_revision` may be supplied by a host that has
  already normalized those transport values. Event and release identity cannot
  be overridden through the payload.
  """
  @spec dispatch(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch(socket, event_name, payload, opts \\ [])

  def dispatch(socket, event_name, payload, opts)
      when is_binary(event_name) and is_map(payload) and is_list(opts) do
    with {:ok, manifest, snapshot} <- runtime(socket),
         {:ok, event_id} <- event_id(opts) do
      event = %{
        "schema" => "selecto.template.runtime-event.v1",
        "instance_id" => snapshot["instance_id"],
        "release_id" => snapshot["release_id"],
        "event_id" => event_id,
        "name" => event_name,
        "expected_state_revision" =>
          Keyword.get(opts, :expected_state_revision, snapshot["state_revision"]),
        "payload" => payload
      }

      reduce(socket, fn -> SelectoTemplates.dispatch_runtime(manifest, snapshot, event) end)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def dispatch(socket, _event_name, _payload, _opts),
    do: assign_error(socket, diagnostic("invalid_host_event", "template host event is invalid"))

  @doc """
  Normalizes browser parameters through the server-owned event declaration and
  dispatches the resulting typed payload.

  The parameter map may contain only `"value"`. Event identity, release identity,
  and revisions remain server or host transport data and cannot be supplied here.
  """
  @spec dispatch_params(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch_params(socket, event_name, params, opts \\ [])

  def dispatch_params(socket, event_name, params, opts)
      when is_binary(event_name) and is_map(params) and is_list(opts) do
    with {:ok, manifest, _snapshot} <- runtime(socket),
         {:ok, payload} <- SelectoComponents.TemplateEvent.normalize(manifest, event_name, params) do
      dispatch(socket, event_name, payload, opts)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def dispatch_params(socket, _event_name, _params, _opts),
    do: assign_error(socket, diagnostic("invalid_host_event", "template host event is invalid"))

  @doc "Applies an authorized source completion through the portable reducer."
  @spec complete(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def complete(socket, completion) when is_map(completion) do
    with {:ok, manifest, snapshot} <- runtime(socket) do
      reduce(socket, fn ->
        SelectoTemplates.complete_runtime(manifest, snapshot, completion)
      end)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def complete(socket, _completion),
    do:
      assign_error(
        socket,
        diagnostic("invalid_host_completion", "template host completion is invalid")
      )

  @doc "Returns queued effects and clears them from the socket."
  @spec take_effects(Phoenix.LiveView.Socket.t()) :: {[map()], Phoenix.LiveView.Socket.t()}
  def take_effects(socket) do
    effects = Map.get(socket.assigns, @effects_assign, [])
    {effects, Component.assign(socket, @effects_assign, [])}
  end

  @doc """
  Starts queued source effects on a connected LiveView.

  The injected executor receives one data-only portable effect and must attach
  fresh host authority before lowering or executing it. It returns
  `{:ok, result}` or `{:error, error}`. The async closure captures the effect,
  runtime identity, and executor only; it never captures the socket.

  Effects remain queued during the disconnected render. Work is keyed by source,
  so a newer generation cancels and supersedes older work for that source.
  """
  @spec start_effects(Phoenix.LiveView.Socket.t(), (map() -> {:ok, term()} | {:error, term()})) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def start_effects(socket, executor) when is_function(executor, 1) do
    if connected?(socket) do
      with {:ok, _manifest, snapshot} <- runtime(socket),
           :ok <- valid_effects(Map.get(socket.assigns, @effects_assign, [])) do
        identity = Map.take(snapshot, ["instance_id", "release_id"])
        {effects, socket} = take_effects(socket)

        socket =
          Enum.reduce(effects, socket, fn effect, current ->
            source = effect["source"]
            key = async_key(source, effect["generation"])
            previous_key = Map.get(current.assigns[@running_assign], source)

            current
            |> maybe_cancel_async(previous_key)
            |> start_async(key, fn -> execute_effect(identity, effect, executor) end)
            |> Component.assign(
              @running_assign,
              Map.put(current.assigns[@running_assign], source, key)
            )
          end)

        {:ok, socket}
      else
        {:error, error} -> assign_error(socket, error)
      end
    else
      {:ok, socket}
    end
  end

  def start_effects(socket, _executor),
    do:
      assign_error(
        socket,
        diagnostic("invalid_effect_executor", "template effect executor is invalid")
      )

  @doc """
  Starts queued source effects with the manifest mounted in this socket.

  The authorization callback receives the server-resolved source plan and the
  data-only effect. It runs once per effect and must return a fresh, scoped
  `%Selecto{}`. Executor options remain host-owned and may include database
  timeout options accepted by `Selecto.execute/2`.
  """
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
    with {:ok, manifest, _snapshot} <- runtime(socket) do
      start_effects(socket, fn effect ->
        SelectoComponents.TemplateSourceExecutor.execute(manifest, effect, authorize, opts)
      end)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def start_source_effects(socket, _authorize, _opts),
    do:
      assign_error(
        socket,
        diagnostic("invalid_effect_executor", "template effect executor is invalid")
      )

  @doc "Handles a completion delivered by `Phoenix.LiveView.start_async/3`."
  @spec handle_async(term(), {:ok, map()} | {:exit, term()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_async(
        {:selecto_template_source, source, generation} = key,
        {:ok, completion},
        socket
      )
      when is_binary(source) and is_integer(generation) and is_map(completion) do
    socket = clear_running_effect(socket, source, key)

    case complete(socket, completion) do
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
        case complete(socket, completion) do
          {:ok, socket} -> {:noreply, socket}
          {:error, _diagnostic, socket} -> {:noreply, socket}
        end

      {:error, diagnostic} ->
        {:noreply, elem(assign_error(socket, diagnostic), 2)}
    end
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp runtime(socket) do
    case {
      Map.get(socket.assigns, @manifest_assign),
      Map.get(socket.assigns, @snapshot_assign)
    } do
      {%{} = manifest, %{} = snapshot} -> {:ok, manifest, snapshot}
      _ -> {:error, diagnostic("template_not_mounted", "template runtime is not mounted")}
    end
  end

  defp event_id(opts) do
    value = Keyword.get_lazy(opts, :event_id, &UUID.uuid4/0)

    if is_binary(value) and value != "" do
      {:ok, value}
    else
      {:error, diagnostic("invalid_event_id", "template event ID is invalid")}
    end
  end

  defp valid_effects(effects) when is_list(effects) do
    if Enum.all?(effects, &valid_effect?/1) do
      :ok
    else
      {:error, diagnostic("invalid_effect", "template effect queue is invalid")}
    end
  end

  defp valid_effects(_effects),
    do: {:error, diagnostic("invalid_effect", "template effect queue is invalid")}

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

  defp execute_effect(identity, effect, executor) do
    result =
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

    completion(identity, effect, result)
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
    with {:ok, _manifest, snapshot} <- runtime(socket),
         %{} <- snapshot["sources"][source] do
      effect = %{
        "effect_id" => "#{snapshot["instance_id"]}:source:#{source}:#{generation}",
        "source" => source,
        "generation" => generation
      }

      {:ok,
       completion(Map.take(snapshot, ["instance_id", "release_id"]), effect, {:error, error})}
    else
      nil -> {:error, diagnostic("invalid_effect", "template effect source is invalid")}
      {:error, diagnostic} -> {:error, diagnostic}
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

  defp reduce(socket, operation) do
    case operation.() do
      {:ok, observation} -> {:ok, assign_observation(socket, observation)}
      {:error, diagnostic} -> assign_error(socket, diagnostic)
    end
  end

  defp assign_observation(socket, observation) do
    effects =
      socket.assigns
      |> Map.get(@effects_assign, [])
      |> queue_effects(observation["effects"])

    socket
    |> Component.assign(@snapshot_assign, observation["snapshot"])
    |> Component.assign(@effects_assign, effects)
    |> Component.assign(@observation_assign, observation)
    |> Component.assign(@error_assign, nil)
  end

  defp queue_effects(queued, new_effects) when is_list(queued) and is_list(new_effects) do
    Enum.reduce(new_effects, queued, fn effect, current ->
      current
      |> discard_obsolete_source_effect(effect)
      |> Kernel.++([effect])
    end)
  end

  defp discard_obsolete_source_effect(queued, %{"kind" => "load_source", "source" => source}) do
    Enum.reject(queued, fn
      %{"kind" => "load_source", "source" => ^source} -> true
      _effect -> false
    end)
  end

  defp discard_obsolete_source_effect(queued, _effect), do: queued

  defp assign_error(socket, error) do
    {:error, error, Component.assign(socket, @error_assign, error)}
  end

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
