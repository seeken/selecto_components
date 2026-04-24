defmodule SelectoComponents.AI.QueryGuide do
  @moduledoc """
  Renders an AI-readable query guide from a generated query contract.
  """

  @spec render(map()) :: String.t()
  def render(contract) when is_map(contract) do
    domain = Map.get(contract, "domain", %{})
    context = Map.get(contract, "context", %{})
    params_schema = Map.get(contract, "params_schema", %{})
    fields = Map.get(contract, "fields", [])
    capabilities = Map.get(contract, "capabilities", %{})
    examples = Map.get(contract, "examples", [])
    errors = Map.get(contract, "errors", %{})

    [
      "# Selecto Query Guide",
      "",
      "## Domain",
      "",
      "- ID: `#{Map.get(domain, "id", "unknown_domain")}`",
      "- Name: #{Map.get(domain, "name", "Unknown Domain")}",
      maybe_line(
        "- Description: #{Map.get(domain, "description")}",
        Map.get(domain, "description")
      ),
      maybe_line("- Path: `#{Map.get(domain, "path")}`", Map.get(domain, "path")),
      "",
      "## Context",
      "",
      "- View modes: #{Enum.join(Map.get(context, "view_modes", []), ", ")}",
      "- Default view mode: `#{Map.get(context, "default_view_mode", "detail")}`",
      "- Export formats: #{Enum.join(Map.get(context, "exports", []), ", ")}",
      "",
      "## Params Schema",
      "",
      render_params_schema(params_schema),
      "",
      "## Fields",
      "",
      render_fields(fields),
      "",
      "## Capabilities",
      "",
      render_capabilities(capabilities),
      "",
      "## Examples",
      "",
      render_examples(examples),
      "",
      "## Errors",
      "",
      render_errors(errors)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def render(_contract), do: "# Selecto Query Guide\n\nNo contract available."

  defp render_params_schema(params_schema) do
    top_level_keys = get_in(params_schema, ["top_level_keys"]) || %{}

    top_level_keys
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, meta} ->
      allowed = Map.get(meta, "allowed")
      item_shape = Map.get(meta, "item_shape")

      [
        "- `#{key}`",
        maybe_line("  - Type: `#{Map.get(meta, "type", "unknown")}`", Map.get(meta, "type")),
        maybe_line("  - Allowed: #{Enum.join(allowed || [], ", ")}", allowed),
        maybe_line("  - Item shape: `#{item_shape}`", item_shape)
      ]
    end)
  end

  defp render_fields(fields) do
    fields
    |> Enum.map(fn field ->
      [
        "- `#{field["id"]}` (#{field["label"]})",
        "  - Type: `#{field["type"]}`",
        "  - Filterable: #{inspect(field["filterable"])}",
        "  - Detail selectable: #{inspect(field["detail_selectable"])}",
        "  - Groupable: #{inspect(field["groupable"])}",
        "  - Aggregatable: #{inspect(field["aggregatable"])}",
        maybe_line(
          "  - Comparators: #{Enum.join(field["comparators"] || [], ", ")}",
          field["comparators"]
        ),
        maybe_line(
          "  - Aggregate functions: #{Enum.join(field["aggregate_functions"] || [], ", ")}",
          field["aggregate_functions"]
        ),
        maybe_line(
          "  - Shortcut values: #{Enum.join(field["shortcut_values"] || [], ", ")}",
          field["shortcut_values"]
        ),
        maybe_line("  - Visibility: #{field["visibility"]}", field["visibility"])
      ]
    end)
  end

  defp render_capabilities(capabilities) do
    aggregate_grid = Map.get(capabilities, "aggregate_grid", %{})
    views = Map.get(capabilities, "views", %{})
    exports = get_in(capabilities, ["exports", "formats"]) || []

    [
      "- Aggregate grid",
      "  - Enabled: #{inspect(Map.get(aggregate_grid, "enabled", false))}",
      "  - Requires group-by count: #{inspect(Map.get(aggregate_grid, "requires_group_by_count"))}",
      "  - Requires aggregate count: #{inspect(Map.get(aggregate_grid, "requires_aggregate_count"))}",
      maybe_line(
        "  - Color scales: #{Enum.join(Map.get(aggregate_grid, "supports_color_scales", []), ", ")}",
        Map.get(aggregate_grid, "supports_color_scales")
      ),
      "- Views",
      Enum.map(views, fn {view, meta} ->
        "  - `#{view}`: #{inspect(Map.get(meta, "enabled", false))}"
      end),
      "- Exports",
      "  - Formats: #{Enum.join(exports, ", ")}"
    ]
  end

  defp render_examples(examples) when is_list(examples) and examples != [] do
    Enum.map(examples, fn example ->
      [
        "- #{example["id"]}",
        maybe_line("  - Prompt: #{example["prompt"]}", example["prompt"]),
        maybe_line("  - Description: #{example["description"]}", example["description"]),
        maybe_line(
          "  - Intent view mode: #{get_in(example, ["intent", "view_mode"])}",
          get_in(example, ["intent", "view_mode"])
        ),
        maybe_line("  - Notes: #{Enum.join(example["notes"] || [], "; ")}", example["notes"])
      ]
    end)
  end

  defp render_examples(_examples), do: ["- No examples available."]

  defp render_errors(errors) when is_map(errors) do
    errors
    |> Enum.sort_by(fn {code, _meta} -> code end)
    |> Enum.map(fn {code, meta} -> "- `#{code}`: #{Map.get(meta, "message", "")}" end)
  end

  defp render_errors(_errors), do: ["- No documented errors."]

  defp maybe_line(_line, nil), do: nil
  defp maybe_line(_line, []), do: nil
  defp maybe_line(line, _value), do: line
end
