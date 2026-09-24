defmodule SelectoComponents.TemplateInstance do
  @moduledoc false

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
    runtime_opts = Keyword.take(opts, [:instance_id, :release_id, :inputs])

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

  @spec runtime(Phoenix.LiveView.Socket.t()) ::
          {:ok, map(), map()} | {:error, diagnostic()}
  def runtime(socket) do
    case {
      Map.get(socket.assigns, @manifest_assign),
      Map.get(socket.assigns, @snapshot_assign)
    } do
      {%{} = manifest, %{} = snapshot} ->
        {:ok, manifest, snapshot}

      _other ->
        {:error, diagnostic("template_not_mounted", "template runtime is not mounted")}
    end
  end

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

  @spec commit_page(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def commit_page(socket, commit) when is_map(commit) do
    with {:ok, manifest, snapshot} <- runtime(socket) do
      reduce(socket, fn ->
        SelectoTemplates.commit_page_runtime(manifest, snapshot, commit)
      end)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def commit_page(socket, _commit),
    do: assign_error(socket, diagnostic("invalid_page_commit", "page commit is invalid"))

  @spec commit_root_page(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def commit_root_page(socket, commit) when is_map(commit) do
    with {:ok, manifest, snapshot} <- runtime(socket) do
      reduce(socket, fn ->
        SelectoTemplates.commit_root_page_runtime(manifest, snapshot, commit)
      end)
    else
      {:error, error} -> assign_error(socket, error)
    end
  end

  def commit_root_page(socket, _commit),
    do:
      assign_error(socket, diagnostic("invalid_root_page_commit", "root page commit is invalid"))

  @spec take_effects(Phoenix.LiveView.Socket.t()) :: {[map()], Phoenix.LiveView.Socket.t()}
  def take_effects(socket) do
    effects = Map.get(socket.assigns, @effects_assign, [])
    {effects, Component.assign(socket, @effects_assign, [])}
  end

  @spec reduce(Phoenix.LiveView.Socket.t(), (-> {:ok, map()} | {:error, diagnostic()})) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def reduce(socket, operation) when is_function(operation, 0) do
    case operation.() do
      {:ok, observation} -> {:ok, assign_observation(socket, observation)}
      {:error, diagnostic} -> assign_error(socket, diagnostic)
    end
  end

  @spec assign_error(Phoenix.LiveView.Socket.t(), diagnostic()) ::
          {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def assign_error(socket, error) do
    {:error, error, Component.assign(socket, @error_assign, error)}
  end

  @spec diagnostic(binary(), binary()) :: diagnostic()
  def diagnostic(code, message) do
    %{
      "schema" => "selecto.template.diagnostic.v1",
      "severity" => "error",
      "code" => code,
      "message" => message,
      "path" => []
    }
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
end
