defmodule SelectoComponents.Components.Common do
  use Phoenix.Component

  alias SelectoComponents.Theme

  def sc_button(assigns) do
    attrs = assigns_to_attributes(assigns, [:label, :class, :variant, :theme])
    custom_class = assigns[:class] || ""
    variant = assigns[:variant] || :secondary
    theme = helper_theme(assigns)

    assigns =
      assign(assigns,
        attrs: attrs,
        custom_class: custom_class,
        variant_class: button_variant_class(theme, variant),
        theme: theme
      )

    ~H"""
      <button {@attrs} class={[@variant_class, @custom_class]}>
        <%= render_slot(@inner_block) %>
      </button>
    """
  end

  def sc_up_button(assigns) do
    attrs = assigns_to_attributes(assigns, [:class, :theme])
    custom_class = assigns[:class] || ""
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, custom_class: custom_class, theme: theme)

    ~H"""
      <button type="button" class={[Theme.slot(@theme, :button_icon), "h-7 w-7", @custom_class]} title="Move up" {@attrs}>
        <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="m15 11.25-3-3-3 3" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 8.25v7.5" />
        </svg>
      </button>
    """
  end

  def sc_down_button(assigns) do
    attrs = assigns_to_attributes(assigns, [:class, :theme])
    custom_class = assigns[:class] || ""
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, custom_class: custom_class, theme: theme)

    ~H"""
      <button type="button" class={[Theme.slot(@theme, :button_icon), "h-7 w-7", @custom_class]} title="Move down" {@attrs}>
        <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="m9 12.75 3 3 3-3" />
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 8.25v7.5" />
        </svg>
      </button>
    """
  end

  def sc_x_button(assigns) do
    attrs = assigns_to_attributes(assigns, [:class, :theme])
    custom_class = assigns[:class] || ""
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, custom_class: custom_class, theme: theme)

    ~H"""
      <button type="button" class={[Theme.slot(@theme, :button_danger), "h-7 w-7", @custom_class]} title="Remove item" {@attrs}>
        <span aria-hidden="true" class="text-base leading-none">×</span>
      </button>
    """
  end

  def sc_x_button_small(assigns) do
    attrs = assigns_to_attributes(assigns, [:theme])
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, theme: theme)

    ~H"""
      <svg
        class="h-4 w-4 cursor-pointer transition-colors"
        style="color: var(--sc-text-muted);"
        {@attrs}
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="2"
        stroke="currentColor"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
      </svg>
    """
  end

  def sc_input(assigns) do
    attrs = assigns_to_attributes(assigns, [:label, :class, :theme])
    custom_class = assigns[:class] || ""
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, custom_class: custom_class, theme: theme)

    ~H"""
      <input {@attrs} class={[Theme.slot(@theme, :input), @custom_class]}/>
    """
  end

  def sc_select_with_slot(assigns) do
    attrs = assigns_to_attributes(assigns, [:label, :options, :value, :theme])
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, theme: theme)

    ~H"""
      <select {@attrs} class={Theme.slot(@theme, :select)} >
        <%= render_slot(@inner_block) %>
      </select>
    """
  end

  def sc_select(assigns) do
    attrs = assigns_to_attributes(assigns, [:label, :options, :value, :theme])
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, theme: theme)

    ~H"""
      <select {@attrs} class={Theme.slot(@theme, :select)} >
        <option :for={{val, lab} <- @options} value={val} selected={val == @value}><%= lab %></option>
      </select>
    """
  end

  def sc_checkbox(assigns) do
    attrs = assigns_to_attributes(assigns, [:label, :options, :value, :theme])
    theme = helper_theme(assigns)
    assigns = assign(assigns, attrs: attrs, theme: theme)

    ~H"""
      <label class={Theme.slot(@theme, :checkbox_label)}>
        <input type="checkbox" {@attrs}/>
        <%= render_slot(@inner_block) %>
      </label>
    """
  end

  attr(:theme, :map, required: true)
  attr(:title, :string, required: true)
  attr(:summary, :string, default: nil)
  attr(:open, :boolean, default: false)
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def sc_collapsible_section(assigns) do
    ~H"""
    <details
      class={[Theme.slot(@theme, :panel) <> " group overflow-hidden", @class]}
      style="background: var(--sc-surface-bg);"
      open={@open}
    >
      <summary class="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3">
        <div class="min-w-0">
          <div class="text-sm font-semibold" style="color: var(--sc-text-primary);">{@title}</div>
          <div :if={@summary not in [nil, ""]} class="truncate text-xs" style="color: var(--sc-text-muted);">
            {@summary}
          </div>
        </div>
        <span class="shrink-0 text-sm transition group-open:rotate-90" style="color: var(--sc-text-muted);">&gt;</span>
      </summary>
      <div class="border-t p-4" style="border-color: var(--sc-surface-border);">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  def field_count_summary(items, empty_summary) do
    case length(items || []) do
      0 -> empty_summary
      1 -> "1 field"
      count -> "#{count} fields"
    end
  end

  def selected_fields_summary(items, columns, empty_summary, opts \\ []) do
    selecto = Keyword.get(opts, :selecto)

    labels =
      (items || [])
      |> Enum.map(&selected_field_label(&1, columns, selecto))
      |> Enum.reject(&(&1 in [nil, ""]))

    case labels do
      [] -> empty_summary
      names -> Enum.join(names, ", ")
    end
  end

  defp selected_field_label({_id, item, config}, columns, selecto),
    do: selected_field_label(item, config, columns, selecto)

  defp selected_field_label([_id, item, config], columns, selecto),
    do: selected_field_label(item, config, columns, selecto)

  defp selected_field_label(_entry, _columns, _selecto), do: nil

  defp selected_field_label(item, config, columns, selecto) do
    item_key = field_item_key(item)

    field_name =
      case Enum.find(columns || [], fn
             {id, _name, _type} -> to_string(id) == item_key
             {id, _name, _type, _metadata} -> to_string(id) == item_key
             _ -> false
           end) do
        {_id, name, _type} -> name
        {_id, name, _type, _metadata} -> name
        _ -> selecto_field_name(selecto, item, item_key)
      end

    case Map.get(config || %{}, "alias", Map.get(config || %{}, :alias, "")) do
      value when value in [nil, ""] -> field_name
      value -> value
    end
  end

  defp selecto_field_name(selecto, item, item_key)
       when is_map(selecto) and is_map_key(selecto, :domain) do
    case Selecto.field(selecto, item) do
      %{name: name} when is_binary(name) -> name
      _ -> item_key
    end
  rescue
    _ -> item_key
  end

  defp selecto_field_name(_selecto, _item, item_key), do: item_key

  defp field_item_key(item) do
    case item do
      {:to_char, {field, _format}} -> to_string(field)
      {_func, field} when is_binary(field) -> field
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp helper_theme(assigns), do: Map.get(assigns, :theme, Theme.default_theme(:light))

  defp button_variant_class(theme, :primary), do: Theme.slot(theme, :button_primary)
  defp button_variant_class(theme, "primary"), do: Theme.slot(theme, :button_primary)

  defp button_variant_class(theme, _), do: Theme.slot(theme, :button_secondary)
end
