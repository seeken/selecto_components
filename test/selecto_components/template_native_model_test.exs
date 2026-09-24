defmodule SelectoComponents.TemplateNativeModelTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateHost

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/order-browser.compile.json",
             __DIR__
           )

  test "builds an authority-free HEEx model from the server-owned runtime" do
    assert {:ok, mounted} =
             TemplateHost.mount(socket(), manifest(),
               instance_id: "native/live:1",
               release_id: "release-native-1",
               inputs: %{}
             )

    assert {:ok, model} = TemplateHost.native_model(mounted)

    assert model["schema"] == "selecto.template.native-heex-model.v1"
    assert model["root_id"] == "selecto-native-template-native-2Flive-3A1"
    assert model["state_revision"] == 0

    assert model["sources"]["orders"] == %{
             "generation" => 1,
             "page_size" => 25,
             "status" => "loading"
           }

    assert Enum.find(model["events"], &(&1["component"] == "SearchInput")) == %{
             "binding" => "change",
             "component" => "SearchInput",
             "component_id" => "root.children.5",
             "event" => "search_changed",
             "input_name" => "value",
             "value_type" => "string"
           }

    refute Map.has_key?(model, "manifest")
    refute inspect(model) =~ "authorization"
    refute inspect(model) =~ "domain_fingerprint"
  end

  test "refreshes state and projected source rows after reducer transitions" do
    assert {:ok, mounted} =
             TemplateHost.mount(socket(), manifest(),
               instance_id: "native-live-2",
               release_id: "release-native-2",
               inputs: %{}
             )

    assert {:ok, dispatched} =
             TemplateHost.dispatch_params(
               mounted,
               "search_changed",
               %{"value" => "PO-100"},
               event_id: "native-event-1"
             )

    assert {:ok, completed} =
             TemplateHost.complete(dispatched, %{
               "schema" => "selecto.template.runtime-completion.v1",
               "instance_id" => "native-live-2",
               "release_id" => "release-native-2",
               "effect_id" => "native-live-2:source:orders:2",
               "source" => "orders",
               "generation" => 2,
               "outcome" => "ok",
               "result" => [%{"id" => 1, "order_number" => "PO-100"}]
             })

    assert {:ok, model} = TemplateHost.native_model(completed)
    assert model["state_revision"] == 1
    assert model["state"]["search"] == "PO-100"
    assert model["sources"]["orders"]["status"] == "ready"

    assert model["sources"]["orders"]["rows"] == [
             %{"id" => 1, "order_number" => "PO-100"}
           ]
  end

  test "native HEEx model preserves an idle lazy source without exposing a result" do
    lazy_fixture =
      Path.expand(
        "../../../selecto-protocol/spec/fixtures/templates/order-lazy-source.compile.json",
        __DIR__
      )

    assert {:ok, mounted} =
             TemplateHost.mount(socket(), lazy_fixture |> File.read!() |> :json.decode(),
               instance_id: "native-lazy",
               release_id: "release-native-lazy",
               inputs: %{}
             )

    assert {:ok, model} = TemplateHost.native_model(mounted)

    assert model["sources"]["selected_order"] == %{
             "generation" => 0,
             "page_size" => 1,
             "status" => "idle"
           }

    refute inspect(model) =~ "authorization"
  end

  test "native HEEx models receive public page rows without internal positions" do
    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest(),
               instance_id: "native-page",
               release_id: "release-native-page",
               inputs: %{}
             )

    snapshot =
      put_in(mounted["snapshot"], ["sources", "orders", "result"], %{
        "rows" => [%{"id" => 1}],
        "pages" => [%{"private_position" => "must-not-expose"}],
        "identities" => [%{"row_keys" => ["private-row-key"]}],
        "root_page" => %{"after_values" => ["private-root-tuple"]}
      })

    assert {:ok, model} = SelectoComponents.TemplateNativeModel.build(manifest(), snapshot)
    assert model["sources"]["orders"]["rows"] == [%{"id" => 1}]
    refute inspect(model) =~ "must-not-expose"
    refute inspect(model) =~ "private-row-key"
    refute inspect(model) =~ "private-root-tuple"
  end

  test "native HEEx models receive filtered source totals without private metadata" do
    assert {:ok, mounted} =
             SelectoTemplates.mount_runtime(manifest(),
               instance_id: "native-total",
               release_id: "release-native-total",
               inputs: %{}
             )

    snapshot =
      put_in(mounted["snapshot"], ["sources", "orders", "result"], %{
        "rows" => [%{"id" => 1}],
        "totals" => %{"order_count" => 2, "related_sum" => "9007199254740993.3"},
        "identities" => [%{"row_keys" => ["private-row-key"]}]
      })

    assert {:ok, model} = SelectoComponents.TemplateNativeModel.build(manifest(), snapshot)
    assert model["sources"]["orders"]["rows"] == [%{"id" => 1}]

    assert model["sources"]["orders"]["totals"] == %{
             "order_count" => 2,
             "related_sum" => "9007199254740993.3"
           }

    refute inspect(model) =~ "private-row-key"

    malformed =
      put_in(snapshot, ["sources", "orders", "result", "totals"], %{"order_count" => -1})

    assert {:error, %{"code" => "invalid_native_sources"}} =
             SelectoComponents.TemplateNativeModel.build(manifest(), malformed)

    rounded =
      put_in(snapshot, ["sources", "orders", "result", "totals"], %{"related_sum" => 0.3})

    assert {:error, %{"code" => "invalid_native_sources"}} =
             SelectoComponents.TemplateNativeModel.build(manifest(), rounded)
  end

  defp manifest, do: @fixture |> File.read!() |> :json.decode()

  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end
end
