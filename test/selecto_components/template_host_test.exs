defmodule SelectoComponents.TemplateHostTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateHost

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/order-browser.compile.json",
             __DIR__
           )

  @lazy_fixture Path.expand(
                  "../../../selecto-protocol/spec/fixtures/templates/order-lazy-source.compile.json",
                  __DIR__
                )

  @page_commit_fixture Path.expand(
                         "../../../selecto-protocol/spec/fixtures/templates/runtime-page-commit.cases.json",
                         __DIR__
                       )

  @paged_manifest_fixture Path.expand(
                            "../../../selecto-protocol/spec/fixtures/templates/order-lines-top-n.compile.json",
                            __DIR__
                          )

  @paged_result_fixture Path.expand(
                          "../../../selecto-protocol/spec/fixtures/templates/collection-page-result.cases.json",
                          __DIR__
                        )

  test "page controls and an async request stay behind server authorization" do
    {manifest, ready} = paged_host(socket(self()))
    source = hd(manifest["sources"])

    scope = %{
      "tenant_id" => "tenant-7",
      "principal_id" => "actor-1",
      "authorization_revision" => "acl-2",
      "membership_revision" => "orders-v1"
    }

    assert {:ok, controls} =
             TemplateHost.page_cursors(ready, source["id"], scope, String.duplicate("s", 32),
               now: 1_000,
               ttl_seconds: 60
             )

    assert Enum.count(controls, & &1["has_more"]) == 2
    token = hd(controls)["token"]
    parent = self()

    assert {:ok, running} =
             TemplateHost.start_page(
               ready,
               source["id"],
               token,
               fn _source, _effect ->
                 send(parent, :page_authorized)
                 {:error, :denied}
               end,
               String.duplicate("s", 32),
               now: 1_001,
               ttl_seconds: 60
             )

    assert_receive :page_authorized

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_page, "orders", 1, 1, _} = key,
                      {:ok, {:error, %{"code" => "source_authorization_failed"} = error}}}}}

    assert {:noreply, rejected} = TemplateHost.handle_async(key, {:ok, {:error, error}}, running)
    assert rejected.assigns.template_runtime_error["code"] == "source_authorization_failed"
    assert get_in(rejected.assigns.template_runtime_snapshot, ["sources", "orders", "page"]) == 1
  end

  test "a completed page task passes through the guarded socket commit" do
    {_manifest, ready} = paged_host(socket())
    snapshot = ready.assigns.template_runtime_snapshot

    commit = %{
      "schema" => "selecto.template.runtime-page-commit.v1",
      "instance_id" => snapshot["instance_id"],
      "release_id" => snapshot["release_id"],
      "source" => "orders",
      "generation" => 1,
      "expected_state_revision" => 0,
      "expected_page" => 1,
      "result" => get_in(snapshot, ["sources", "orders", "result"])
    }

    key = {:selecto_template_page, "orders", 1, 1, make_ref()}
    assert {:noreply, advanced} = TemplateHost.handle_async(key, {:ok, {:ok, commit}}, ready)
    assert get_in(advanced.assigns.template_runtime_snapshot, ["sources", "orders", "page"]) == 2

    assert {:noreply, stale} = TemplateHost.handle_async(key, {:ok, {:ok, commit}}, advanced)
    assert stale.assigns.template_last_observation["code"] == "stale_page_commit"
  end

  test "a LiveView page commit updates only the ready source version" do
    test_case =
      @page_commit_fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("cases") |> hd()

    snapshot = test_case["snapshot"]
    commit = test_case["commit"]

    assert {:ok, mounted} =
             TemplateHost.mount(socket(), manifest(),
               instance_id: snapshot["instance_id"],
               release_id: snapshot["release_id"],
               inputs: %{}
             )

    completion = %{
      "schema" => "selecto.template.runtime-completion.v1",
      "instance_id" => snapshot["instance_id"],
      "release_id" => snapshot["release_id"],
      "effect_id" => "#{snapshot["instance_id"]}:source:orders:1",
      "source" => "orders",
      "generation" => 1,
      "outcome" => "ok",
      "result" => get_in(snapshot, ["sources", "orders", "result"])
    }

    assert {:ok, ready} = TemplateHost.complete(mounted, completion)
    assert {:ok, advanced} = TemplateHost.commit_page(ready, commit)
    assert advanced.assigns.template_runtime_snapshot == test_case["expected"]["snapshot"]
    assert advanced.assigns.template_last_observation["outcome"] == "accepted"

    assert {:ok, repeated} = TemplateHost.commit_page(advanced, commit)
    assert repeated.assigns.template_last_observation["code"] == "stale_page_commit"

    assert repeated.assigns.template_runtime_snapshot ==
             advanced.assigns.template_runtime_snapshot
  end

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

  test "a lazy source stays idle at mount and selection replaces its pending load" do
    manifest = @lazy_fixture |> File.read!() |> Jason.decode!()
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest, mount_opts())

    assert get_in(mounted.assigns.template_runtime_snapshot, [
             "sources",
             "selected_order",
             "status"
           ]) ==
             "idle"

    assert {[initial], mounted} = TemplateHost.take_effects(mounted)
    assert initial["source"] == "orders"

    assert {:ok, first} =
             TemplateHost.dispatch_params(mounted, "order_selected", %{"value" => "PO-100"},
               event_id: "select-1"
             )

    assert {:ok, second} =
             TemplateHost.dispatch_params(first, "order_selected", %{"value" => "PO-200"},
               event_id: "select-2"
             )

    assert {[effect], _drained} = TemplateHost.take_effects(second)
    assert effect["source"] == "selected_order"
    assert effect["generation"] == 2
    assert effect["bindings"]["state"]["selected_order_number"] == "PO-200"
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

  test "dispatch_params converts a browser integer before the reducer sees it" do
    assert {:ok, mounted} = TemplateHost.mount(socket(), manifest(), mount_opts())

    assert {:ok, dispatched} =
             TemplateHost.dispatch_params(
               mounted,
               "order_selected",
               %{"value" => "17"},
               event_id: "event-live-browser-1"
             )

    assert dispatched.assigns.template_runtime_snapshot["state"]["selected_order_id"] == 17

    assert {:error, error, unchanged} =
             TemplateHost.dispatch_params(
               dispatched,
               "order_selected",
               %{"value" => "017", "tenant_id" => "9"},
               event_id: "event-live-browser-2"
             )

    assert error["code"] == "invalid_event_params"
    assert unchanged.assigns.template_runtime_snapshot["state_revision"] == 1
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

  test "authorized source effects use the manifest mounted in the socket" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())
    parent = self()

    assert {:ok, running} =
             TemplateHost.start_source_effects(mounted, fn source, effect ->
               send(parent, {:authorize_source, source["id"], effect["generation"]})
               {:error, %{private_reason: "must-not-escape"}}
             end)

    assert_receive {:authorize_source, "orders", 1}

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_source, "orders", 1}, {:ok, completion}}}}

    assert completion["outcome"] == "error"
    assert completion["error"]["code"] == "source_authorization_failed"
    refute inspect(completion) =~ "must-not-escape"

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

  test "a stalled source task is terminated and completed with a bounded timeout" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())
    parent = self()

    authorize = fn _source, _effect ->
      send(parent, {:blocked_source, self()})

      receive do
        :release -> {:error, :released}
      end
    end

    assert {:ok, running} =
             TemplateHost.start_source_effects(mounted, authorize, source_timeout_ms: 1_000)

    assert_receive {:blocked_source, worker}, 1_000
    monitor = Process.monitor(worker)

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_source, "orders", 1}, {:ok, completion}}}},
                   2_000

    assert completion["outcome"] == "error"
    assert completion["error"]["code"] == "source_timeout"
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000

    assert {:noreply, completed} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:ok, completion},
               running
             )

    assert completed.assigns.template_runtime_snapshot["sources"]["orders"]["status"] ==
             "error"
  end

  test "reloading a source cancels its old worker and ignores a late old result" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())
    parent = self()

    executor = fn effect ->
      if effect["generation"] == 1 do
        send(parent, {:old_source_worker, self()})

        receive do
          :release -> {:ok, [%{"id" => 1}]}
        end
      else
        {:ok, [%{"id" => 2}]}
      end
    end

    assert {:ok, first_running} = TemplateHost.start_effects(mounted, executor)
    assert_receive {:old_source_worker, old_worker}, 1_000
    monitor = Process.monitor(old_worker)

    assert {:ok, dispatched} =
             TemplateHost.dispatch(first_running, "search_changed", %{"value" => "new"},
               event_id: "event-live-reload"
             )

    assert {:ok, second_running} = TemplateHost.start_effects(dispatched, executor)
    assert_receive {:DOWN, ^monitor, :process, ^old_worker, _reason}, 1_000

    assert_receive {:phoenix, :async_result,
                    {:start, {_ref, nil, {:selecto_template_source, "orders", 2}, {:ok, current}}}},
                   1_000

    assert {:noreply, ready} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 2},
               {:ok, current},
               second_running
             )

    assert ready.assigns.template_runtime_snapshot["sources"]["orders"]["result"] ==
             [%{"id" => 2}]

    assert {:noreply, unchanged} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:ok, completion(1, [%{"id" => 1}])},
               ready
             )

    assert unchanged.assigns.template_runtime_snapshot["sources"]["orders"]["result"] ==
             [%{"id" => 2}]

    assert unchanged.assigns.template_last_observation["code"] == "stale_completion"
  end

  test "a full source worker budget completes excess effects as errors" do
    [source] = manifest()["sources"]
    second = Map.put(source, "id", "other_orders")
    manifest = put_in(manifest(), ["sources"], [source, second])
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest, mount_opts())
    parent = self()

    executor = fn effect ->
      send(parent, {:started_source, effect["source"], self()})

      receive do
        :release -> {:ok, []}
      end
    end

    assert {:ok, running} =
             TemplateHost.start_effects(mounted, executor, max_concurrent_effects: 1)

    assert map_size(running.assigns.template_running_effects) == 1

    assert running.assigns.template_runtime_snapshot["sources"]["other_orders"]["status"] ==
             "error"

    assert running.assigns.template_runtime_snapshot["sources"]["other_orders"]["error"]["code"] ==
             "source_workers_busy"

    assert_receive {:started_source, "orders", worker}
    refute_receive {:started_source, "other_orders", _worker}
    send(worker, :release)

    assert_receive {:phoenix, :async_result,
                    {:start,
                     {_ref, nil, {:selecto_template_source, "orders", 1}, {:ok, completion}}}}

    assert {:noreply, completed} =
             TemplateHost.handle_async(
               {:selecto_template_source, "orders", 1},
               {:ok, completion},
               running
             )

    assert completed.assigns.template_runtime_snapshot["sources"]["orders"]["status"] ==
             "ready"
  end

  test "invalid host effect budgets leave the source queue untouched" do
    assert {:ok, mounted} = TemplateHost.mount(socket(self()), manifest(), mount_opts())

    assert {:error, diagnostic, returned} =
             TemplateHost.start_effects(mounted, fn _effect -> flunk() end,
               max_concurrent_effects: 0
             )

    assert diagnostic["code"] == "invalid_effect_budget"
    assert length(returned.assigns.template_pending_effects) == 1
  end

  defp manifest, do: @fixture |> File.read!() |> :json.decode()

  defp paged_host(socket) do
    manifest =
      @paged_manifest_fixture
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["sources", Access.at(0), "query", "collections", Access.at(0), "page_size"], 1)
      |> put_in(
        [
          "sources",
          Access.at(0),
          "query",
          "collections",
          Access.at(0),
          "collections",
          Access.at(0),
          "page_size"
        ],
        1
      )

    result =
      @paged_result_fixture
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("cases")
      |> hd()
      |> Map.fetch!("expected")

    assert {:ok, mounted} =
             TemplateHost.mount(socket, manifest,
               instance_id: "paged-live-instance",
               release_id: "paged-live-release",
               inputs: %{}
             )

    completion = %{
      "schema" => "selecto.template.runtime-completion.v1",
      "instance_id" => "paged-live-instance",
      "release_id" => "paged-live-release",
      "effect_id" => "paged-live-instance:source:orders:1",
      "source" => "orders",
      "generation" => 1,
      "outcome" => "ok",
      "result" => result
    }

    assert {:ok, ready} = TemplateHost.complete(mounted, completion)
    {manifest, ready}
  end

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
