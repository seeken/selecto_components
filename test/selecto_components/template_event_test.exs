defmodule SelectoComponents.TemplateEventTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.TemplateEvent

  @fixture Path.expand(
             "../../../selecto-protocol/spec/fixtures/templates/event-transport.cases.json",
             __DIR__
           )

  test "matches every protocol-owned browser normalization case" do
    fixture = @fixture |> File.read!() |> :json.decode()
    manifest = %{"events" => fixture["events"]}

    assert TemplateEvent.max_value_bytes() == fixture["max_value_bytes"]

    Enum.each(fixture["cases"], fn test_case ->
      result = TemplateEvent.normalize(manifest, test_case["event"], test_case["params"])

      case test_case["outcome"] do
        "ok" ->
          assert result == {:ok, test_case["payload"]}, test_case["id"]

        "error" ->
          expected_code = test_case["code"]
          assert {:error, %{"code" => ^expected_code}} = result
      end
    end)
  end

  test "rejects a browser string above the fixed transport budget" do
    manifest = %{"events" => [%{"name" => "changed", "payload" => %{"value" => "string"}}]}
    oversized = String.duplicate("x", TemplateEvent.max_value_bytes() + 1)

    assert {:error, %{"code" => "event_value_too_large"}} =
             TemplateEvent.normalize(manifest, "changed", %{"value" => oversized})
  end
end
