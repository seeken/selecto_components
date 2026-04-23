defmodule SelectoComponents.AI.ImportComponent do
  @moduledoc """
  Lightweight import/review surface for AI intent JSON.

  This first slice renders the paste/import affordance plus structural preview
  feedback. Event wiring can be layered on later.
  """

  use Phoenix.LiveComponent

  alias SelectoComponents.Theme

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        theme: Map.get(assigns, :theme, Theme.default_theme(:light)),
        import_json: Map.get(assigns, :import_json, ""),
        import_result: Map.get(assigns, :import_result)
      )

    ~H"""
    <div class={Theme.slot(@theme, :panel) <> " p-4 space-y-4"} data-selecto-ai-import style="background: var(--sc-surface-bg);">
      <div>
        <h3 class="text-sm font-semibold" style="color: var(--sc-text-primary);">Import AI Intent</h3>
        <p class="text-xs" style="color: var(--sc-text-secondary);">
          Paste AI intent JSON, validate it, review the preview, then apply it explicitly.
        </p>
      </div>

      <div>
        <label for={"#{@id}-intent-json"} class="mb-1 block text-xs font-medium" style="color: var(--sc-text-secondary);">
          Intent JSON
        </label>
        <textarea
          id={"#{@id}-intent-json"}
          name="ai_intent_json"
          rows="12"
          class={Theme.slot(@theme, :input)}
          placeholder={~s({"intent_version":1,"mode":"replace","view_mode":"detail","selected":[{"field":"status"}]})}
        ><%= @import_json %></textarea>
      </div>

      <div class="flex items-center gap-2">
        <button type="button" class={Theme.slot(@theme, :button_secondary) <> " px-3 py-2 text-sm"}>
          Preview Intent
        </button>
        <button
          type="button"
          class={Theme.slot(@theme, :button_primary) <> " px-3 py-2 text-sm"}
          disabled={is_nil(@import_result) || @import_result[:ok] != true}
          style={if is_nil(@import_result) || @import_result[:ok] != true, do: "opacity: 0.55; cursor: not-allowed;", else: nil}
        >
          Apply Intent
        </button>
      </div>

      <div :if={@import_result && @import_result[:validation]} data-selecto-ai-validation class="space-y-3">
        <div
          :if={!@import_result.validation.ok}
          class="rounded-lg border px-4 py-3"
          style="background: var(--sc-danger-soft); border-color: color-mix(in srgb, var(--sc-danger) 35%, var(--sc-surface-border)); color: var(--sc-danger);"
        >
          <div class="font-semibold mb-1">Validation Errors</div>
          <ul class="space-y-1 text-sm">
            <li :for={error <- @import_result.validation.errors}>
              <code>{format_path(error["path"])}</code>: {error["message"]}
            </li>
          </ul>
        </div>

        <div
          :if={@import_result[:ok] && @import_result[:preview]}
          class={Theme.slot(@theme, :panel) <> " rounded-lg p-4 space-y-2"}
          style="background: var(--sc-surface-bg-alt);"
        >
          <div class="font-semibold" style="color: var(--sc-text-primary);">Preview Summary</div>
          <div class="text-sm" style="color: var(--sc-text-secondary);">
            View mode: <span class="font-medium" style="color: var(--sc-text-primary);"><%= @import_result.preview["preview"]["diff"]["view_mode"]["from"] || "none" %></span>
            ->
            <span class="font-medium" style="color: var(--sc-text-primary);"><%= @import_result.preview["preview"]["diff"]["view_mode"]["to"] || "none" %></span>
          </div>
          <div class="text-sm" style="color: var(--sc-text-secondary);">
            Changed sections: <%= Enum.join(@import_result.preview["preview"]["diff"]["changed_sections"], ", ") %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_path(path) when is_list(path) do
    Enum.map_join(path, ".", &to_string/1)
  end

  defp format_path(_path), do: "root"
end
