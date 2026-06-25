defmodule SelectoComponents.Form.ViewPanel do
  use Phoenix.Component

  alias SelectoComponents.Theme
  alias SelectoComponents.Views.Runtime, as: ViewRuntime

  attr(:active_tab, :string, default: nil)
  attr(:theme, :map, required: true)
  attr(:saved_view_config_module, :any, default: nil)
  attr(:view_config, :map, required: true)
  attr(:saved_view_context, :any, default: nil)
  attr(:current_user_id, :any, default: nil)
  attr(:parent_id, :any, required: true)
  attr(:views, :list, required: true)
  attr(:columns, :list, required: true)
  attr(:selecto, :any, required: true)

  def panel(assigns) do
    assigns =
      assigns
      |> assign(
        :aggregate_to_graph_available?,
        view_available?(assigns.views, :aggregate) and view_available?(assigns.views, :graph)
      )

    ~H"""
    <div
      role="tabpanel"
      id="main-tabpanel-view"
      aria-labelledby="main-tab-view"
      class={if @active_tab == "view" or @active_tab == nil, do: Theme.slot(@theme, :panel) <> " p-3", else: "hidden"}
    >
      <.live_component
        :if={@saved_view_config_module}
        module={SelectoComponents.ViewConfigManager}
        id="view_config_manager"
        view_config={@view_config}
        saved_view_config_module={@saved_view_config_module}
        saved_view_context={@saved_view_context}
        theme={@theme}
        current_user_id={@current_user_id}
        parent_id={@parent_id}
      />

      <.live_component
        module={SelectoComponents.Components.Tabs}
        id="view_mode"
        fieldname="view_mode"
        view_mode={@view_config.view_mode}
        options={@views}
      >
        <:section :let={{id, _mod, _, _} = view}>
          <.live_component
            module={ViewRuntime.form_component(view)}
            id={"view_#{id}_form"}
            theme={@theme}
            columns={@columns}
            view_config={@view_config}
            view={view}
            selecto={@selecto}
            graph_view_available?={id == :aggregate and @aggregate_to_graph_available?}
          />
        </:section>
      </.live_component>
    </div>
    """
  end

  defp view_available?(views, view_id) when is_list(views) do
    Enum.any?(views, fn
      {^view_id, _module, _name, _opts} -> true
      _ -> false
    end)
  end

  defp view_available?(_views, _view_id), do: false
end
