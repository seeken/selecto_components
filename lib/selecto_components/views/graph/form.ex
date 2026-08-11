defmodule SelectoComponents.Views.Graph.Form do
  use Phoenix.LiveComponent

  import SelectoComponents.Components.Common
  alias SelectoComponents.Theme
  alias SelectoComponents.Views.Aggregate.Form, as: AnalyticForm
  alias SelectoComponents.Views.Graph.Process

  @impl true
  def render(assigns) do
    graph_view_key = current_view_key(assigns[:view])
    component_view = normalize_view(assigns[:view], graph_view_key)

    graph_state =
      assigns[:view_config]
      |> view_state(graph_view_key)
      |> Process.normalize_state()

    visual = Map.get(graph_state, :visual, %{})
    graph_view_config = put_graph_state(assigns[:view_config], graph_view_key, graph_state)

    assigns =
      assigns
      |> assign_new(:theme, fn -> Theme.default_theme(:light) end)
      |> assign_new(:id, fn -> "graph" end)
      |> assign(
        component_view: component_view,
        graph_view_config: graph_view_config,
        graph_view_key: graph_view_key,
        graph_state: graph_state,
        graph_group_by: Map.get(graph_state, :group_by, []),
        graph_aggregate: Map.get(graph_state, :aggregate, []),
        graph_visual: visual,
        graph_chart_type: map_get(visual, :type, "auto"),
        graph_x: map_get(visual, :x),
        graph_series: map_get(visual, :series, []),
        graph_stack: map_get(visual, :stack, "auto"),
        graph_measure_overrides: map_get(visual, :measure_overrides, %{}),
        graph_options: map_get(visual, :options, %{})
      )

    ~H"""
    <div id={"graph-form-#{@id}"} class="space-y-3">
      <div class={Theme.slot(@theme, :panel) <> " px-3 py-3"} style="background: var(--sc-surface-bg-alt);">
        <h3 class="text-sm font-semibold" style="color: var(--sc-text-primary);">
          Aggregate query, graph projection
        </h3>
        <p class="mt-1 text-sm" style="color: var(--sc-text-secondary);">
          Group By and Aggregates use the same controls and query semantics as Aggregate View.
          The settings below only decide how that result is drawn.
        </p>
      </div>

      <.live_component
        module={AnalyticForm}
        id={"#{@id}-analytic-query"}
        theme={@theme}
        columns={@columns}
        view_config={@graph_view_config}
        view={@component_view}
        selecto={@selecto}
        state_view_key={@graph_view_key}
        query_only={true}
        group_param="graph_group_by"
        aggregate_param="graph_aggregate"
      />

      <.sc_collapsible_section
        theme={@theme}
        title="Visual Mapping"
        summary={visual_summary(@graph_chart_type, @graph_group_by)}
        open={true}
      >
        <div class="grid gap-4 md:grid-cols-3">
          <label class="block text-sm">
            <span class="text-xs font-medium" style="color: var(--sc-text-secondary);">Chart Type</span>
            <.sc_select_with_slot theme={@theme} name="graph_chart_type" class="mt-1 w-full">
              <option value="auto" selected={@graph_chart_type == "auto"}>Auto</option>
              <option value="bar" selected={@graph_chart_type == "bar"}>Bar</option>
              <option value="line" selected={@graph_chart_type == "line"}>Line</option>
              <option value="area" selected={@graph_chart_type == "area"}>Area</option>
              <option value="pie" selected={@graph_chart_type == "pie"}>Pie</option>
              <option value="scatter" selected={@graph_chart_type == "scatter"}>Scatter</option>
            </.sc_select_with_slot>
          </label>

          <label class="block text-sm">
            <span class="text-xs font-medium" style="color: var(--sc-text-secondary);">X Group</span>
            <.sc_select_with_slot theme={@theme} name="graph_x" class="mt-1 w-full">
              <option value="" selected={@graph_x in [nil, ""]}>Auto (first Group By)</option>
              <option
                :for={item <- @graph_group_by}
                value={item_id(item)}
                selected={@graph_x == item_id(item)}
              >
                {item_label(item, @selecto)}
              </option>
            </.sc_select_with_slot>
          </label>

          <label class="block text-sm">
            <span class="text-xs font-medium" style="color: var(--sc-text-secondary);">Series Layout</span>
            <.sc_select_with_slot theme={@theme} name="graph_stack" class="mt-1 w-full">
              <option value="auto" selected={@graph_stack == "auto"}>Auto</option>
              <option value="grouped" selected={@graph_stack == "grouped"}>Grouped</option>
              <option value="stacked" selected={@graph_stack == "stacked"}>Stacked</option>
            </.sc_select_with_slot>
          </label>
        </div>

        <div :if={length(@graph_group_by) > 1} class="mt-4">
          <div class="text-xs font-medium" style="color: var(--sc-text-secondary);">Series Groups</div>
          <p class="mt-1 text-xs" style="color: var(--sc-text-muted);">
            With none selected, every Group By after X becomes a series automatically.
          </p>
          <input type="hidden" name="graph_series[]" value="" />
          <div class="mt-2 flex flex-wrap gap-3">
            <label
              :for={item <- non_x_items(@graph_group_by, @graph_x)}
              class="flex items-center gap-2 text-sm"
              style="color: var(--sc-text-secondary);"
            >
              <input
                type="checkbox"
                name="graph_series[]"
                value={item_id(item)}
                checked={item_id(item) in @graph_series}
                class="checkbox checkbox-sm"
              />
              <span>{item_label(item, @selecto)}</span>
            </label>
          </div>
        </div>
      </.sc_collapsible_section>

      <.sc_collapsible_section
        :if={@graph_aggregate != []}
        theme={@theme}
        title="Measure Display"
        summary="Mark, axis, and color overrides"
        open={false}
      >
        <div class="space-y-4">
          <div
            :for={item <- @graph_aggregate}
            class="grid gap-3 rounded-lg border p-3 md:grid-cols-[minmax(10rem,1fr)_9rem_9rem_10rem]"
            style="border-color: var(--sc-surface-border);"
          >
            <% override = map_get(@graph_measure_overrides, item_id(item), %{}) %>
            <div class="self-center text-sm font-medium" style="color: var(--sc-text-primary);">
              {item_label(item, @selecto)}
            </div>
            <label class="text-xs" style="color: var(--sc-text-secondary);">
              Mark
              <.sc_select_with_slot
                theme={@theme}
                name={"graph_measure_overrides[#{item_id(item)}][mark]"}
                class="mt-1 w-full"
              >
                <option value="auto" selected={map_get(override, :mark, "auto") == "auto"}>Auto</option>
                <option value="bar" selected={map_get(override, :mark) == "bar"}>Bar</option>
                <option value="line" selected={map_get(override, :mark) == "line"}>Line</option>
              </.sc_select_with_slot>
            </label>
            <label class="text-xs" style="color: var(--sc-text-secondary);">
              Axis
              <.sc_select_with_slot
                theme={@theme}
                name={"graph_measure_overrides[#{item_id(item)}][axis]"}
                class="mt-1 w-full"
              >
                <option value="auto" selected={map_get(override, :axis, "auto") == "auto"}>Auto</option>
                <option value="left" selected={map_get(override, :axis) == "left"}>Left</option>
                <option value="right" selected={map_get(override, :axis) == "right"}>Right</option>
              </.sc_select_with_slot>
            </label>
            <label class="text-xs" style="color: var(--sc-text-secondary);">
              Color
              <.sc_input
                theme={@theme}
                name={"graph_measure_overrides[#{item_id(item)}][color]"}
                value={map_get(override, :color, "")}
                placeholder="#3b82f6"
                class="mt-1 w-full"
              />
            </label>
          </div>
        </div>
      </.sc_collapsible_section>

      <.sc_collapsible_section
        theme={@theme}
        title="Display Options"
        summary={display_options_summary(@graph_options)}
        open={false}
      >
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <label class="block text-sm" style="color: var(--sc-text-secondary);">
            Chart Title
            <.sc_input theme={@theme} name="graph_options[title]" value={option_value(@graph_options, :title, "")} />
          </label>
          <label class="block text-sm" style="color: var(--sc-text-secondary);">
            X-Axis Label
            <.sc_input theme={@theme} name="graph_options[x_axis_label]" value={option_value(@graph_options, :x_axis_label, "")} />
          </label>
          <label class="block text-sm" style="color: var(--sc-text-secondary);">
            Y-Axis Label
            <.sc_input theme={@theme} name="graph_options[y_axis_label]" value={option_value(@graph_options, :y_axis_label, "")} />
          </label>
          <label class="block text-sm" style="color: var(--sc-text-secondary);">
            Y2-Axis Label
            <.sc_input theme={@theme} name="graph_options[y2_axis_label]" value={option_value(@graph_options, :y2_axis_label, "")} />
          </label>
          <label class="block text-sm" style="color: var(--sc-text-secondary);">
            Legend Position
            <.sc_select_with_slot theme={@theme} name="graph_options[legend_position]" class="mt-1 w-full">
              <option :for={position <- ~w(top bottom left right none)} value={position} selected={option_value(@graph_options, :legend_position, "bottom") == position}>
                {position_label(position)}
              </option>
            </.sc_select_with_slot>
          </label>
        </div>

        <div class="mt-4 flex flex-wrap gap-4">
          <.boolean_option name="show_grid" label="Show grid lines" options={@graph_options} />
          <.boolean_option name="enable_animations" label="Enable animations" options={@graph_options} default={true} />
          <.boolean_option name="responsive" label="Responsive" options={@graph_options} default={true} />
        </div>
      </.sc_collapsible_section>
    </div>
    """
  end

  attr(:name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:options, :map, required: true)
  attr(:default, :boolean, default: false)

  defp boolean_option(assigns) do
    ~H"""
    <label class="flex items-center gap-2 text-sm" style="color: var(--sc-text-secondary);">
      <input type="hidden" name={"graph_options[#{@name}]"} value="false" />
      <input
        type="checkbox"
        name={"graph_options[#{@name}]"}
        value="true"
        checked={option_checked(@options, @name, @default)}
        class="checkbox checkbox-sm"
      />
      <span>{@label}</span>
    </label>
    """
  end

  defp current_view_key({id, _mod, _name, _opts}) when is_atom(id), do: id
  defp current_view_key(id) when is_atom(id), do: id
  defp current_view_key(_view), do: :graph

  defp normalize_view({id, _module, _name, _opts} = view, _view_key) when is_atom(id), do: view

  defp normalize_view(_view, view_key),
    do: {view_key, SelectoComponents.Views.Graph, "Graph View", %{}}

  defp view_state(view_config, view_key) do
    view_config
    |> map_get(:views, %{})
    |> map_get(view_key, %{})
  end

  defp put_graph_state(view_config, view_key, graph_state) when is_map(view_config) do
    views = map_get(view_config, :views, %{}) |> Map.put(view_key, graph_state)
    Map.put(view_config, :views, views)
  end

  defp put_graph_state(_view_config, view_key, graph_state),
    do: %{views: %{view_key => graph_state}}

  defp visual_summary(type, group_by) do
    chart = if type == "auto", do: "Automatic chart", else: "#{String.capitalize(type)} chart"
    "#{chart}; #{length(group_by)} grouping(s)"
  end

  defp display_options_summary(options) do
    case option_value(options, :title, "") do
      title when title not in [nil, ""] -> "Title: #{title}"
      _ -> "Labels, legend, grid, animation"
    end
  end

  defp non_x_items(items, nil), do: Enum.drop(items, 1)

  defp non_x_items(items, x_id),
    do: Enum.reject(items, &(item_id(&1) == x_id))

  defp item_id({id, _field, _config}), do: id
  defp item_id([id, _field, _config]), do: id
  defp item_id(_item), do: nil

  defp item_field({_id, field, _config}), do: field
  defp item_field([_id, field, _config]), do: field
  defp item_field(_item), do: nil

  defp item_label(item, selecto) do
    field = item_field(item)

    case field_definition(selecto, field) do
      %{name: name} when is_binary(name) -> name
      _ -> to_string(field || "")
    end
  end

  defp field_definition(%{field: resolver}, field) when is_function(resolver, 1),
    do: resolver.(field)

  defp field_definition(selecto, field), do: Selecto.field(selecto, field)

  defp position_label("none"), do: "Hide legend"
  defp position_label(position), do: String.capitalize(position)

  defp option_value(options, key, default), do: map_get(options, key, default)

  defp option_checked(options, key, default) do
    case option_value(options, key, default) do
      value when value in [true, "true", "on", 1, "1"] -> true
      value when value in [false, "false", 0, "0"] -> false
      _ -> default
    end
  end

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp map_get(_map, _key, default), do: default
end
