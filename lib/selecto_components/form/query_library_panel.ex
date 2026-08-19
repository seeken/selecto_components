defmodule SelectoComponents.Form.QueryLibraryPanel do
  use Phoenix.Component

  alias SelectoComponents.QueryLibrary
  alias SelectoComponents.Theme

  attr(:selecto, :any, required: true)
  attr(:view_config, :map, required: true)
  attr(:theme, :map, required: true)

  def panel(assigns) do
    selection = QueryLibrary.selection(assigns.view_config)

    assigns =
      assign(assigns,
        selection: selection,
        views: QueryLibrary.entries(assigns.selecto, :views),
        segments: QueryLibrary.entries(assigns.selecto, :segments),
        parameters: QueryLibrary.parameter_entries(assigns.selecto, selection),
        selected_view:
          Enum.find(QueryLibrary.entries(assigns.selecto, :views), &(&1.id == selection.view))
      )

    ~H"""
    <div class="space-y-5">
      <p class="text-sm" style="color: var(--sc-text-secondary);">
        Named views seed the editable Detail columns and ordering. Named segments remain active as governed constraints alongside visual filters.
      </p>

      <label :if={@views != []} class="block text-sm">
        <span class="font-medium">Named view</span>
        <select
          name="query_library[view]"
          class={Theme.slot(@theme, :input) <> " mt-1 w-full"}
        >
          <option value="" selected={is_nil(@selection.view)}>No named view</option>
          <option :for={view <- @views} value={view.id} selected={@selection.view == view.id}>
            {view.label}
          </option>
        </select>
      </label>

      <div :if={@selected_view} class={Theme.slot(@theme, :panel) <> " px-3 py-2 text-sm"}>
        <strong>{@selected_view.label}</strong>
        <p :if={@selected_view.description} class="mt-1" style="color: var(--sc-text-secondary);">
          {@selected_view.description}
        </p>
        <p :if={@selected_view.capability} class="mt-1 text-xs" style="color: var(--sc-text-secondary);">
          Capability metadata: {@selected_view.capability}
        </p>
      </div>

      <fieldset :if={@segments != []}>
        <legend class="text-sm font-medium">Additional named segments</legend>
        <div class="mt-2 grid gap-2 md:grid-cols-2">
          <label :for={segment <- @segments} class={Theme.slot(@theme, :panel) <> " flex gap-2 px-3 py-2 text-sm"}>
            <input
              type="checkbox"
              name="query_library[segments][]"
              value={segment.id}
              checked={segment.id in @selection.segments}
            />
            <span>
              <strong>{segment.label}</strong>
              <span :if={segment.description} class="block text-xs" style="color: var(--sc-text-secondary);">
                {segment.description}
              </span>
              <span :if={segment.capability} class="block text-xs" style="color: var(--sc-text-secondary);">
                Capability metadata: {segment.capability}
              </span>
            </span>
          </label>
        </div>
      </fieldset>

      <fieldset :if={@parameters != []}>
        <legend class="text-sm font-medium">Parameters</legend>
        <div class="mt-2 grid gap-3 md:grid-cols-2">
          <label :for={parameter <- @parameters} class="block text-sm">
            <span>{parameter.label}{if parameter.required, do: " *", else: ""}</span>
            <input
              :if={QueryLibrary.input_type(parameter.type) != "checkbox"}
              type={QueryLibrary.input_type(parameter.type)}
              name={"query_library[parameters][#{parameter.id}]"}
              value={Map.get(@selection.parameters, parameter.id, parameter.default)}
              required={parameter.required}
              step={if parameter.type in ["float", "decimal"], do: "any"}
              class={Theme.slot(@theme, :input) <> " mt-1 w-full"}
            />
            <span :if={QueryLibrary.input_type(parameter.type) == "checkbox"} class="mt-1 flex items-center gap-2">
              <input type="hidden" name={"query_library[parameters][#{parameter.id}]"} value="false" />
              <input
                type="checkbox"
                name={"query_library[parameters][#{parameter.id}]"}
                value="true"
                checked={Map.get(@selection.parameters, parameter.id, parameter.default) in [true, "true", 1, "1"]}
              />
              Enabled
            </span>
            <span :if={parameter.description} class="mt-1 block text-xs" style="color: var(--sc-text-secondary);">
              {parameter.description}
            </span>
          </label>
        </div>
      </fieldset>
    </div>
    """
  end
end
