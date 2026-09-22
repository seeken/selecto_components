defmodule SelectoComponents.TemplateHost do
  @moduledoc """
  Public LiveView adapter for a compiled Selecto template.

  `TemplateHost` is a stable facade. Instance state, browser-event dispatch, and
  asynchronous effect execution live in separate modules so each boundary can
  evolve without coupling the portable runtime to a LiveView socket.

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

  alias SelectoComponents.TemplateEffectRunner
  alias SelectoComponents.TemplateEventDispatcher
  alias SelectoComponents.TemplateInstance

  @type diagnostic :: map()

  @spec mount(Phoenix.LiveView.Socket.t(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:error, diagnostic()}
  def mount(socket, manifest, opts) do
    with {:ok, socket} <- TemplateInstance.mount(socket, manifest, opts) do
      {:ok, TemplateEffectRunner.initialize(socket)}
    end
  end

  @doc "Applies a declared event using server-owned runtime identity."
  @spec dispatch(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch(socket, event_name, payload, opts \\ []) do
    TemplateEventDispatcher.dispatch(socket, event_name, payload, opts)
  end

  @doc "Normalizes browser parameters through the declared event and dispatches them."
  @spec dispatch_params(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch_params(socket, event_name, params, opts \\ []) do
    TemplateEventDispatcher.dispatch_params(socket, event_name, params, opts)
  end

  @doc "Applies an authorized source completion through the portable reducer."
  @spec complete(Phoenix.LiveView.Socket.t(), map()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  defdelegate complete(socket, completion), to: TemplateInstance

  @doc "Returns queued effects and clears them from the socket."
  @spec take_effects(Phoenix.LiveView.Socket.t()) :: {[map()], Phoenix.LiveView.Socket.t()}
  defdelegate take_effects(socket), to: TemplateInstance

  @doc "Starts queued data-only effects on a connected LiveView."
  @spec start_effects(Phoenix.LiveView.Socket.t(), (map() -> {:ok, term()} | {:error, term()})) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  defdelegate start_effects(socket, executor), to: TemplateEffectRunner

  @doc "Starts queued source effects with fresh host authorization."
  @spec start_source_effects(
          Phoenix.LiveView.Socket.t(),
          SelectoComponents.TemplateSourceExecutor.authorize(),
          keyword()
        ) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def start_source_effects(socket, authorize, opts \\ []) do
    TemplateEffectRunner.start_source_effects(socket, authorize, opts)
  end

  @doc "Handles a completion delivered by `Phoenix.LiveView.start_async/3`."
  @spec handle_async(term(), {:ok, map()} | {:exit, term()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defdelegate handle_async(name, result, socket), to: TemplateEffectRunner
end
