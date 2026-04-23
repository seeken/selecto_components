defmodule SelectoComponents.AI.IntentPreview do
  @moduledoc """
  Builds preview/diff packaging for AI intent application.

  This first slice is structural: it compares the current runtime state with the
  AI-derived params/view_config and returns a compact diff summary that can be
  shown before apply.
  """

  alias SelectoComponents.AI.IntentApplier
  alias SelectoComponents.Form.ParamsState

  @tracked_sections [
    :view_mode,
    :filters,
    :selected,
    :order_by,
    :group_by,
    :aggregate,
    :graph,
    :options
  ]

  @spec build(map(), Phoenix.LiveView.Socket.t()) :: map()
  def build(intent, socket) when is_map(intent) do
    apply_result = IntentApplier.apply(intent, socket)
    current_view_config = Map.get(socket.assigns, :view_config, %{})
    current_params = ParamsState.view_config_to_params(current_view_config)
    next_params = apply_result.params
    next_view_config = apply_result.view_config

    diff = %{
      "changed_sections" => changed_sections(current_view_config, next_view_config),
      "view_mode" => %{
        "from" =>
          Map.get(current_view_config, :view_mode, Map.get(current_view_config, "view_mode")),
        "to" => Map.get(next_view_config, :view_mode, Map.get(next_view_config, "view_mode"))
      },
      "counts" => %{
        "filters" => section_count_diff(current_view_config, next_view_config, :filters),
        "selected" =>
          view_section_count_diff(current_view_config, next_view_config, :detail, :selected),
        "order_by" =>
          view_section_count_diff(current_view_config, next_view_config, :detail, :order_by),
        "group_by" =>
          view_section_count_diff(current_view_config, next_view_config, :aggregate, :group_by),
        "aggregate" =>
          view_section_count_diff(current_view_config, next_view_config, :aggregate, :aggregate),
        "graph_x_axis" =>
          view_section_count_diff(current_view_config, next_view_config, :graph, :x_axis),
        "graph_y_axis" =>
          view_section_count_diff(current_view_config, next_view_config, :graph, :y_axis),
        "graph_series" =>
          view_section_count_diff(current_view_config, next_view_config, :graph, :series)
      }
    }

    %{
      "mode" => apply_result.mode,
      "intent" => apply_result.intent,
      "preview" => %{
        "current_params" => current_params,
        "next_params" => next_params,
        "current_view_config" => current_view_config,
        "next_view_config" => next_view_config,
        "diff" => diff
      }
    }
  end

  def build(_intent, socket), do: build(%{}, socket)

  defp changed_sections(current_view_config, next_view_config) do
    @tracked_sections
    |> Enum.filter(fn section ->
      section_changed?(current_view_config, next_view_config, section)
    end)
    |> Enum.map(&Atom.to_string/1)
  end

  defp section_changed?(current_view_config, next_view_config, :view_mode) do
    get_map_value(current_view_config, :view_mode) != get_map_value(next_view_config, :view_mode)
  end

  defp section_changed?(current_view_config, next_view_config, :filters) do
    get_map_value(current_view_config, :filters, []) !=
      get_map_value(next_view_config, :filters, [])
  end

  defp section_changed?(current_view_config, next_view_config, :selected) do
    view_section(current_view_config, :detail, :selected) !=
      view_section(next_view_config, :detail, :selected)
  end

  defp section_changed?(current_view_config, next_view_config, :order_by) do
    view_section(current_view_config, :detail, :order_by) !=
      view_section(next_view_config, :detail, :order_by)
  end

  defp section_changed?(current_view_config, next_view_config, :group_by) do
    view_section(current_view_config, :aggregate, :group_by) !=
      view_section(next_view_config, :aggregate, :group_by)
  end

  defp section_changed?(current_view_config, next_view_config, :aggregate) do
    view_section(current_view_config, :aggregate, :aggregate) !=
      view_section(next_view_config, :aggregate, :aggregate)
  end

  defp section_changed?(current_view_config, next_view_config, :graph) do
    view_state(current_view_config, :graph) != view_state(next_view_config, :graph)
  end

  defp section_changed?(current_view_config, next_view_config, :options) do
    options_view_modes = [:detail, :aggregate]

    Enum.any?(options_view_modes, fn view_mode ->
      view_state(current_view_config, view_mode) != view_state(next_view_config, view_mode)
    end)
  end

  defp section_count_diff(current_view_config, next_view_config, key) do
    %{
      "from" => get_map_value(current_view_config, key, []) |> safe_count(),
      "to" => get_map_value(next_view_config, key, []) |> safe_count()
    }
  end

  defp view_section_count_diff(current_view_config, view_config, view_mode, key) do
    %{
      "from" => view_section(current_view_config, view_mode, key) |> safe_count(),
      "to" => view_section(view_config, view_mode, key) |> safe_count()
    }
  end

  defp view_section(view_config, view_mode, key) do
    view_config
    |> view_state(view_mode)
    |> get_map_value(key, [])
  end

  defp view_state(view_config, view_mode) do
    view_config
    |> get_map_value(:views, %{})
    |> get_map_value(view_mode, %{})
  end

  defp safe_count(list) when is_list(list), do: length(list)
  defp safe_count(map) when is_map(map), do: map_size(map)
  defp safe_count(_), do: 0

  defp get_map_value(map, key, default \\ nil)

  defp get_map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp get_map_value(_map, _key, default), do: default
end
