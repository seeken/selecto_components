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

  @manifest_assign :template_manifest
  @snapshot_assign :template_runtime_snapshot
  @effects_assign :template_pending_effects
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
