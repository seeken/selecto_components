defmodule SelectoComponents.TemplateEventDispatcher do
  @moduledoc false

  alias SelectoComponents.TemplateInstance

  @type diagnostic :: map()

  @spec dispatch(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch(socket, event_name, payload, opts \\ [])

  def dispatch(socket, event_name, payload, opts)
      when is_binary(event_name) and is_map(payload) and is_list(opts) do
    with {:ok, manifest, snapshot} <- TemplateInstance.runtime(socket),
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

      TemplateInstance.reduce(socket, fn ->
        SelectoTemplates.dispatch_runtime(manifest, snapshot, event)
      end)
    else
      {:error, error} -> TemplateInstance.assign_error(socket, error)
    end
  end

  def dispatch(socket, _event_name, _payload, _opts) do
    TemplateInstance.assign_error(
      socket,
      TemplateInstance.diagnostic("invalid_host_event", "template host event is invalid")
    )
  end

  @spec dispatch_params(Phoenix.LiveView.Socket.t(), binary(), map(), keyword()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
          | {:error, diagnostic(), Phoenix.LiveView.Socket.t()}
  def dispatch_params(socket, event_name, params, opts \\ [])

  def dispatch_params(socket, event_name, params, opts)
      when is_binary(event_name) and is_map(params) and is_list(opts) do
    with {:ok, manifest, _snapshot} <- TemplateInstance.runtime(socket),
         {:ok, payload} <- SelectoComponents.TemplateEvent.normalize(manifest, event_name, params) do
      dispatch(socket, event_name, payload, opts)
    else
      {:error, error} -> TemplateInstance.assign_error(socket, error)
    end
  end

  def dispatch_params(socket, _event_name, _params, _opts) do
    TemplateInstance.assign_error(
      socket,
      TemplateInstance.diagnostic("invalid_host_event", "template host event is invalid")
    )
  end

  defp event_id(opts) do
    value = Keyword.get_lazy(opts, :event_id, &UUID.uuid4/0)

    if is_binary(value) and value != "" do
      {:ok, value}
    else
      {:error, TemplateInstance.diagnostic("invalid_event_id", "template event ID is invalid")}
    end
  end
end
