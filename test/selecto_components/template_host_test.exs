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

  test "effects remain queued during disconnected rendering" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())
    assert {:ok, returned} = TemplateHost.start_effects(mounted, fn _effect -> flunk() end)
    assert length(returned.assigns.template_pending_effects) == 1
  end

  test "a connected host executes only data effects and applies the async completion" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())
    parent = self()

    executor = fn effect ->
      send(parent, {:executed_effect, effect})
      {:ok, [%{"id" => 1, "order_number" => "PO-100"}]}
    end

    assert {:ok, running} = TemplateHost.start_effects(mounted, executor)
    assert running.assigns.template_pending_effects == []

    assert_receive {:executed_effect, effect}

    assert effect["bindings"] == %{
             "input" => %{},
             "state" => %{"search" => "", "selected_order_id" => nil}
           }

    refute Map.has_key?(effect, "tenant_id")

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_source, "orders", 1}, {:ok, completion}}}}

    assert completion["instance_id"] == "instance-live-1"
    assert completion["generation"] == 1

    assert {:noreply, completed} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:ok, completion},
               running
             )

    assert completed.assigns.template_runtime_snapshot["sources"]["orders"]["status"] ==
             "ready"
  end

  test "executor failures become bounded error completions" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())

    assert {:ok, running} =
             TemplateHost.start_effects(mounted, fn _effect ->
               raise "database details must not escape"
             end)

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_source, "orders", 1}, {:ok, completion}}}}

    assert completion["outcome"] == "error"
    assert completion["error"]["code"] == "effect_execution_failed"
    refute inspect(completion) =~ "database details"

    assert {:noreply, completed} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:ok, completion},
               running
             )

    assert completed.assigns.template_runtime_snapshot["sources"]["orders"]["status"] ==
             "error"
  end

  test "an exited older task cannot mark a newer generation as failed" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert {:ok, dispatched} =
             TemplateHost.dispatch(
               mounted,
               "search_changed",
               %{"value" => "new"},
               event_id: "event-live-6"
             )

    assert {:noreply, returned} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:exit, :timeout},
               dispatched
             )

    assert returned.assigns.template_last_observation["outcome"] == "ignored"
    assert returned.assigns.template_last_observation["code"] == "stale_completion"
    assert returned.assigns.template_runtime_snapshot["sources"]["orders"]["generation"] == 2
    assert returned.assigns.template_runtime_snapshot["sources"]["orders"]["status"] == "loading"
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

  defp socket(transport_pid \\ nil) do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}, transport_pid: transport_pid}
  end
end
