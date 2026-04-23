defmodule SelectoComponents.AI.IntentNormalizerTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.AI.IntentNormalizer

  test "normalizes minimal detail intent with defaults" do
    normalized =
      IntentNormalizer.normalize(%{
        "intent_version" => 1,
        "mode" => "replace",
        "view_mode" => "detail",
        "selected" => [%{"field" => "status"}]
      })

    assert normalized["filters"] == []
    assert normalized["order_by"] == []
    assert normalized["group_by"] == []
    assert normalized["aggregate"] == []
    assert normalized["graph"]["chart_type"] == "bar"
    assert normalized["selected"] == [%{"field" => "status", "format" => "default"}]
  end

  test "normalizes graph metric function from format fallback" do
    normalized =
      IntentNormalizer.normalize(%{
        "intent_version" => 1,
        "mode" => "draft",
        "view_mode" => "graph",
        "graph" => %{
          "y_axis" => [%{"field" => "revenue", "format" => "sum"}]
        }
      })

    assert normalized["graph"]["y_axis"] == [%{"field" => "revenue", "function" => "sum"}]
  end

  test "normalizes atom keys and map sections" do
    normalized =
      IntentNormalizer.normalize(%{
        intent_version: 1,
        mode: :replace,
        view_mode: :aggregate,
        group_by: [%{field: "status", alias: "Status"}],
        options: %{aggregate_grid: true}
      })

    assert normalized["mode"] == "replace"
    assert normalized["view_mode"] == "aggregate"

    assert normalized["group_by"] == [
             %{"field" => "status", "alias" => "Status", "format" => "default"}
           ]

    assert normalized["options"] == %{"aggregate_grid" => true}
  end
end
