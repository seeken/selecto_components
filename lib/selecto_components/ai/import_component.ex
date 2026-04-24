defmodule SelectoComponents.AI.ImportComponent do
  @moduledoc """
  Lightweight import/review surface for AI intent JSON.

  This first slice renders the paste/import affordance plus structural preview
  feedback. Event wiring can be layered on later.
  """

  use Phoenix.LiveComponent

  alias SelectoComponents.AI.IntentImport
  alias SelectoComponents.AI.PromptStub
  alias SelectoComponents.AI.QueryContract
  alias SelectoComponents.Theme

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:theme, fn -> Theme.default_theme(:light) end)
      |> assign_new(:import_json, fn -> "" end)
      |> assign_new(:import_result, fn -> nil end)
      |> assign_new(:contract_json, fn -> nil end)
      |> assign_new(:prompt_stub, fn -> nil end)
      |> assign_new(:apply_status, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        theme: Map.get(assigns, :theme, Theme.default_theme(:light)),
        import_json: Map.get(assigns, :import_json, ""),
        import_result: Map.get(assigns, :import_result),
        contract_json: Map.get(assigns, :contract_json),
        prompt_stub: Map.get(assigns, :prompt_stub),
        apply_status: Map.get(assigns, :apply_status)
      )

    ~H"""
    <div class={Theme.slot(@theme, :panel) <> " p-4 space-y-4"} data-selecto-ai-import style="background: var(--sc-surface-bg);">
      <div>
        <h3 class="text-sm font-semibold" style="color: var(--sc-text-primary);">Import AI Intent</h3>
        <p class="text-xs" style="color: var(--sc-text-secondary);">
          Paste AI intent JSON, validate it, review the preview, then apply it explicitly.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" phx-click="copy_contract_json" phx-target={@myself} class={Theme.slot(@theme, :button_secondary) <> " px-3 py-2 text-sm"}>
          Copy Contract JSON
        </button>
        <button type="button" phx-click="copy_prompt_stub" phx-target={@myself} class={Theme.slot(@theme, :button_secondary) <> " px-3 py-2 text-sm"}>
          Copy Prompt Stub
        </button>
      </div>

      <.form for={%{}} as={:ai_import} phx-change="update_import_json" phx-target={@myself}>
      <div>
        <label for={"#{@id}-intent-json"} class="mb-1 block text-xs font-medium" style="color: var(--sc-text-secondary);">
          Intent JSON
        </label>
        <textarea
          id={"#{@id}-intent-json"}
          name="ai_import[json]"
          rows="12"
          class={Theme.slot(@theme, :input)}
          placeholder={~s({"intent_version":1,"mode":"replace","view_mode":"detail","selected":[{"field":"status"}]})}
        ><%= @import_json %></textarea>
      </div>
      </.form>

      <div class="flex items-center gap-2">
        <button type="button" phx-click="preview_import" phx-target={@myself} class={Theme.slot(@theme, :button_secondary) <> " px-3 py-2 text-sm"}>
          Preview Intent
        </button>
        <button
          type="button"
          phx-click="apply_import"
          phx-target={@myself}
          class={Theme.slot(@theme, :button_primary) <> " px-3 py-2 text-sm"}
          disabled={is_nil(@import_result) || @import_result[:ok] != true}
          style={if is_nil(@import_result) || @import_result[:ok] != true, do: "opacity: 0.55; cursor: not-allowed;", else: nil}
        >
          Apply Intent
        </button>
      </div>

      <div
        :if={@apply_status == :applied}
        class="rounded-lg border px-4 py-3"
        style="background: color-mix(in srgb, var(--sc-accent-soft) 55%, var(--sc-surface-bg)); border-color: color-mix(in srgb, var(--sc-accent) 35%, var(--sc-surface-border)); color: var(--sc-text-primary);"
      >
        <div class="font-semibold">AI intent applied</div>
        <div class="text-sm" style="color: var(--sc-text-secondary);">
          The previewed configuration has been applied to the current explorer.
        </div>
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

          <div class="grid grid-cols-1 md:grid-cols-2 gap-3 pt-2">
            <%= for {section, diff} <- preview_sections(@import_result.preview) do %>
              <div class={Theme.slot(@theme, :panel) <> " rounded-md p-3"} style="background: var(--sc-surface-bg);">
                <div class="font-medium text-sm mb-2" style="color: var(--sc-text-primary); text-transform: capitalize;">
                  {section}
                </div>
                <div class="text-xs" style="color: var(--sc-text-secondary);">
                  From {length(diff["from"])} to {length(diff["to"])}
                </div>
                <div :if={diff["added"] != []} class="mt-2 text-xs" style="color: var(--sc-text-primary);">
                  <div class="font-medium">Added</div>
                  <ul class="list-disc ml-4 mt-1 space-y-1">
                    <li :for={item <- diff["added"]}>{item}</li>
                  </ul>
                </div>
                <div :if={diff["removed"] != []} class="mt-2 text-xs" style="color: var(--sc-text-secondary);">
                  <div class="font-medium">Removed</div>
                  <ul class="list-disc ml-4 mt-1 space-y-1">
                    <li :for={item <- diff["removed"]}>{item}</li>
                  </ul>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".AiImportClipboard">
        export default {
          mounted() {
            this.handleEvent("selecto_ai_copy_to_clipboard", ({ text }) => {
              if (!navigator.clipboard || typeof text !== "string") return;
              navigator.clipboard.writeText(text);
            });
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  def handle_event("update_import_json", %{"ai_import" => %{"json" => json}}, socket) do
    {:noreply,
     socket
     |> assign(:import_json, json)
     |> assign(:apply_status, nil)}
  end

  def handle_event("preview_import", _params, socket) do
    contract = QueryContract.generate(socket.assigns.selecto, socket.assigns.views)
    preview_socket = preview_socket(socket.assigns)
    result = IntentImport.import(socket.assigns.import_json || "", contract, preview_socket)

    {:noreply,
     socket
     |> assign(:import_result, result)
     |> assign(:apply_status, nil)}
  end

  def handle_event("copy_contract_json", _params, socket) do
    contract = QueryContract.generate(socket.assigns.selecto, socket.assigns.views)
    encoded = Jason.encode!(contract, pretty: true)

    {:noreply,
     socket
     |> assign(:contract_json, encoded)
     |> push_event("selecto_ai_copy_to_clipboard", %{text: encoded})}
  end

  def handle_event("copy_prompt_stub", _params, socket) do
    contract = QueryContract.generate(socket.assigns.selecto, socket.assigns.views)
    prompt_stub = PromptStub.build(contract)

    {:noreply,
     socket
     |> assign(:prompt_stub, prompt_stub)
     |> push_event("selecto_ai_copy_to_clipboard", %{text: prompt_stub})}
  end

  def handle_event(
        "apply_import",
        _params,
        %{assigns: %{import_result: %{ok: true} = result}} = socket
      ) do
    send(self(), {:apply_ai_intent_preview, result.preview})
    {:noreply, assign(socket, :apply_status, :applied)}
  end

  def handle_event("apply_import", _params, socket), do: {:noreply, socket}

  defp format_path(path) when is_list(path) do
    Enum.map_join(path, ".", &to_string/1)
  end

  defp format_path(_path), do: "root"

  defp preview_sections(preview) do
    preview
    |> get_in(["preview", "diff", "sections"])
    |> case do
      sections when is_map(sections) ->
        sections
        |> Enum.filter(fn {_section, diff} -> diff["added"] != [] or diff["removed"] != [] end)

      _ ->
        []
    end
  end

  defp preview_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns:
        assigns
        |> Map.take([:selecto, :views, :view_config, :presentation_context])
        |> Map.put_new(:presentation_context, %{})
        |> Map.put_new(:view_config, %{})
        |> Map.put_new(:__changed__, %{})
    }
  end
end
