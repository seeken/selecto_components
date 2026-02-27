defmodule SelectoComponents.Form.ParamsStateTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Form.ParamsState

  test "view_config_to_params includes detail max_rows and per_page" do
    view_config = %{
      view_mode: "detail",
      filters: [],
      views: %{
        detail: %{
          selected: [],
          order_by: [],
          per_page: "60",
          max_rows: "10000",
          prevent_denormalization: true
        }
      }
    }

    params = ParamsState.view_config_to_params(view_config)

    assert params["view_mode"] == "detail"
    assert params["per_page"] == "60"
    assert params["max_rows"] == "10000"
    assert params["prevent_denormalization"] == "true"
  end

  test "view_config_to_params includes aggregate per-page config" do
    view_config = %{
      view_mode: "aggregate",
      filters: [],
      views: %{
        aggregate: %{
          group_by: [],
          aggregate: [],
          per_page: "300"
        }
      }
    }

    params = ParamsState.view_config_to_params(view_config)

    assert params["view_mode"] == "aggregate"
    assert params["aggregate_per_page"] == "300"
    refute Map.has_key?(params, "max_rows")
  end

  test "view_config_to_params includes document-specific keys" do
    view_config = %{
      view_mode: "document",
      filters: [],
      views: %{
        document: %{
          selected: [{"doc-1", "title", %{}}],
          subtable_fields: [{"sub-1", "actors.name", %{}}],
          template: %{"blocks" => [%{"type" => "title", "text" => "Film: {{title}}"}]},
          per_page: "15",
          max_rows: "all"
        }
      }
    }

    params = ParamsState.view_config_to_params(view_config)

    assert params["view_mode"] == "document"
    assert get_in(params, ["document_selected", "doc-1", "field"]) == "title"
    assert get_in(params, ["document_subtable_fields", "sub-1", "field"]) == "actors.name"
    assert get_in(params, ["document_template", "blocks"]) == [
             %{"type" => "title", "text" => "Film: {{title}}"}
           ]
    assert params["document_per_page"] == "15"
    assert params["document_max_rows"] == "all"
  end

  test "convert_saved_config_to_full_params for document" do
    saved = %{
      "document" => %{
        "selected" => [["doc-1", "title", %{}]],
        "subtable_fields" => [["sub-1", "actors.name", %{}]],
        "template" => %{"blocks" => [%{"type" => "text", "text" => "{{title}}"}]},
        "per_page" => "25",
        "max_rows" => "10000"
      }
    }

    params = ParamsState.convert_saved_config_to_full_params(saved, "document")

    assert params["view_mode"] == "document"
    assert get_in(params, ["document_selected", "doc-1", "field"]) == "title"
    assert get_in(params, ["document_subtable_fields", "sub-1", "field"]) == "actors.name"
    assert params["document_per_page"] == "25"
    assert params["document_max_rows"] == "10000"
    assert get_in(params, ["document_template", "blocks"]) ==
             [%{"type" => "text", "text" => "{{title}}"}]
  end
end
