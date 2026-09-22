defmodule SelectoComponents.TemplateHostTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateHost

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/order-browser.compile.json",
             __DIR__
           )

  test "mount stores pure runtime state and exposes initial effects for the host" do
    assert {:ok, socket} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert socket.assigns.template_runtime_snapshot["state_revision"] == 0
    assert socket.assigns.template_runtime_snapshot["instance_id"] == "instance-live-1"
    assert socket.assigns.template_runtime_error == nil

    assert {[effect], drained} = TemplateHost.take_effects(socket)
    assert effect["kind"] == "load_source"
    assert effect["bindings"]["state"]["search"] == ""
    assert drained.assigns.template_pending_effects == []
  end

  test "dispatch constructs trusted identity and replaces an obsolete queued source load" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert {:ok, dispatched} =
             TemplateHost.dispatch(
               mounted,
               "search_changed",
               %{"value" => "PO-100"},
               event_id: "event-live-1"
             )

    snapshot = dispatched.assigns.template_runtime_snapshot
    assert snapshot["state_revision"] == 1
    assert snapshot["state"]["search"] == "PO-100"

    assert [effect] = dispatched.assigns.template_pending_effects
    assert effect["generation"] == 2
    assert effect["bindings"]["state"]["search"] == "PO-100"
  end

  test "stale completions are ignored and current completions update the snapshot" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert {:ok, dispatched} =
             TemplateHost.dispatch(
               mounted,
               "search_changed",
               %{"value" => "PO-100"},
               event_id: "event-live-2"
             )

    assert {:ok, stale} = TemplateHost.complete(dispatched, completion(1, [%{"id" => 99}]))
    assert stale.assigns.template_last_observation["code"] == "stale_completion"
    assert stale.assigns.template_runtime_snapshot["sources"]["orders"]["status"] == "loading"

    rows = [%{"id" => 1, "order_number" => "PO-100"}]
    assert {:ok, completed} = TemplateHost.complete(stale, completion(2, rows))
    assert completed.assigns.template_runtime_snapshot["sources"]["orders"]["result"] == rows
  end

  test "a transport revision can reject a stale event without changing state" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert {:ok, dispatched} =
             TemplateHost.dispatch(
               mounted,
               "search_changed",
               %{"value" => "fresh"},
               event_id: "event-live-3"
             )

    assert {:ok, rejected} =
             TemplateHost.dispatch(
               dispatched,
               "search_changed",
               %{"value" => "stale"},
               event_id: "event-live-4",
               expected_state_revision: 0
             )

    assert rejected.assigns.template_last_observation["outcome"] == "rejected"
    assert rejected.assigns.template_last_observation["code"] == "stale_revision"
    assert rejected.assigns.template_runtime_snapshot["state"]["search"] == "fresh"
  end

  test "dispatch reports a host error before mount" do
    assert {:error, error, returned_socket} =
             TemplateHost.dispatch(socket(), "search_changed", %{"value" => "x"},
               event_id: "event-live-5"
             )

    assert error["code"] == "template_not_mounted"
    assert returned_socket.assigns.template_runtime_error == error
  end

  defp manifest, do: @fixture |> File.read!() |> :json.decode()

  defp mount_opts do
    [instance_id: "instance-live-1", release_id: "release-live-1", inputs: %{}]
  end

  defp completion(generation, rows) do
    %{
      "schema" => "selecto.template.runtime-completion.v1",
      "instance_id" => "instance-live-1",
      "release_id" => "release-live-1",
      "effect_id" => "instance-live-1:source:orders:#{generation}",
      "source" => "orders",
      "generation" => generation,
      "outcome" => "ok",
      "result" => rows
    }
  end

  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end
end
