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
    assert model["sources"]["orders"] == %{"generation" => 1, "status" => "loading"}

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

  defp manifest, do: @fixture |> File.read!() |> :json.decode()

  defp socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end
end
