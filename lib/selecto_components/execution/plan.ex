defmodule SelectoComponents.Execution.Plan do
  @moduledoc """
  Non-I/O execution planning for SelectoComponents.

  This module turns runtime params plus socket state into an execution-ready
  plan that can be inspected and tested independently from query execution.
  """

  import SelectoComponents.Helpers.Filters, only: [filter_recurse_strict: 3]

  alias SelectoComponents.Form.ColumnCatalog
  alias SelectoComponents.Execution.CTEs
  alias SelectoComponents.Form.ParamsState
  alias SelectoComponents.Presentation
  alias SelectoComponents.QueryContract
  alias SelectoComponents.QueryLibrary
  alias SelectoComponents.SafeAtom
  alias SelectoComponents.SubselectBuilder
  alias SelectoComponents.EnhancedTable.Sorting
  alias SelectoComponents.Views.Runtime, as: ViewRuntime

  defstruct [
    :params,
    :presentation_context,
    :selecto,
    :columns_list,
    :columns_map,
    :filtered,
    :selected_view,
    :view_tuple,
    :view_set,
    :view_meta,
    :validation_errors,
    :scope_baseline
  ]

  @type t :: %__MODULE__{}

  @scope_baseline_assign :selecto_scope_baseline

  @spec build(map(), Phoenix.LiveView.Socket.t()) :: t()
  def build(params, socket) when is_map(params) do
    presentation_context =
      socket.assigns
      |> Map.get(:presentation_context, %{})
      |> Presentation.resolve_context()

    params =
      params
      |> ParamsState.canonicalize_form_params(socket.assigns[:selecto], presentation_context)
      |> put_runtime_presentation_context(presentation_context)

    scope_baseline = scope_baseline(socket.assigns)

    selecto =
      scope_baseline
      |> rebuild_selecto()
      |> CTEs.apply_for_params(params)
      |> QueryLibrary.apply_segments(get_map_value(params, :query_library, %{}))

    raw_columns = Selecto.columns(selecto)
    columns_list = ColumnCatalog.picker_columns(selecto)
    columns_map = build_columns_map(raw_columns)
    filters_by_section = build_filters_by_section(params)
    intent_validation = validate_intent(params, socket, selecto)

    {filtered, filter_errors} =
      case filter_recurse_strict(selecto, filters_by_section, "filters") do
        {:ok, filters} -> {filters, []}
        {:error, error} -> {[], [filter_build_error(error)]}
      end

    selected_view = SafeAtom.to_view_mode(get_map_value(params, :view_mode))
    params = maybe_put_detail_page(params, selected_view, socket)
    view_tuple = Enum.find(socket.assigns.views, fn {id, _, _, _} -> id == selected_view end)

    {view_set, view_meta} =
      case view_tuple do
        {_id, _module, _name, _opt} = tuple ->
          ViewRuntime.view(tuple, params, columns_map, filtered, selecto)

        nil ->
          raise "View mode '#{selected_view}' not found in configured views"
      end

    view_set = merge_library_filters(view_set, Map.get(selecto.set, :filtered, []))

    selecto =
      selecto
      |> Map.put(:set, Map.merge(Map.get(selecto, :set, %{}), view_set))
      |> maybe_apply_denorm_groups()
      |> maybe_apply_sort(socket.assigns[:sort_by])

    %__MODULE__{
      params: params,
      presentation_context: presentation_context,
      selecto: selecto,
      columns_list: columns_list,
      columns_map: columns_map,
      filtered: filtered,
      selected_view: selected_view,
      view_tuple: view_tuple,
      view_set: view_set,
      view_meta: view_meta,
      validation_errors: intent_validation.errors ++ filter_errors,
      scope_baseline: scope_baseline
    }
  end

  @doc """
  Records the host scope a plan was built from on the socket that now holds
  the plan's Selecto, so the next plan starts from the same host scope.
  """
  @spec put_scope_baseline(Phoenix.LiveView.Socket.t(), t()) :: Phoenix.LiveView.Socket.t()
  def put_scope_baseline(socket, %__MODULE__{scope_baseline: baseline, selecto: planned}) do
    Phoenix.Component.assign(socket, @scope_baseline_assign, %{
      baseline: baseline,
      planned: planned
    })
  end

  @doc """
  Identifies the row scope of a planned Selecto: its filters, required
  filters and tenant. Result page caches include it so rows cached under one
  scope are never served after the host narrows or changes the scope.
  """
  @spec scope_signature(Selecto.t() | term()) :: non_neg_integer() | nil
  def scope_signature(%Selecto{} = selecto) do
    :erlang.phash2(
      {Map.get(selecto.set, :filtered, []), Selecto.required_filters(selecto),
       Selecto.tenant(selecto)}
    )
  end

  def scope_signature(_selecto), do: nil

  # After a run the socket holds the planned Selecto, whose set carries the
  # previous query. Plans start from the Selecto the host assigned instead,
  # with its filters, required filters, tenant, policy and runtime intact. A
  # Selecto that is not the last planned one was assigned or changed by the
  # host and becomes the new baseline.
  defp scope_baseline(assigns) do
    current = Map.get(assigns, :selecto)

    case Map.get(assigns, @scope_baseline_assign) do
      %{planned: planned, baseline: baseline} when planned === current -> baseline
      _other -> current
    end
  end

  defp rebuild_selecto(host_selecto) do
    case Selecto.tenant(host_selecto) do
      nil -> host_selecto
      _tenant -> Selecto.apply_tenant_scope(host_selecto)
    end
  end

  defp put_runtime_presentation_context(params, presentation_context) when is_map(params) do
    Map.put(params, "_presentation_context", presentation_context || %{})
  end

  defp put_runtime_presentation_context(params, _presentation_context), do: params

  defp build_columns_map(raw_columns) do
    raw_columns
    |> Enum.into(%{}, fn {key, col} ->
      col_with_metadata =
        col
        |> Map.put(:field, col.name)
        |> Map.put(:colid, key)

      {key, col_with_metadata}
    end)
    |> then(fn cols ->
      Enum.reduce(cols, cols, fn {_colid, col}, acc ->
        Map.put(acc, col.name, col)
      end)
    end)
  end

  defp build_filters_by_section(params) do
    params
    |> Map.get("filters", %{})
    |> Map.values()
    |> Enum.filter(fn f ->
      is_map(f) and Map.has_key?(f, "section") and
        (Map.has_key?(f, "filter") or Map.get(f, "is_section") in ["Y", true, "true"])
    end)
    |> Enum.reduce(%{}, fn f, acc ->
      Map.put(acc, Map.get(f, "section"), Map.get(acc, Map.get(f, "section"), []) ++ [f])
    end)
  end

  defp validate_intent(params, socket, selecto) do
    contract = Map.get(socket.assigns, :query_contract, selecto)
    opts = Map.get(socket.assigns, :query_contract_opts, [])
    intent = execution_intent(params, socket.assigns[:sort_by])
    QueryContract.validate_intent(contract, intent, opts)
  end

  defp execution_intent(params, sort_by) do
    filters =
      params
      |> Map.get("filters", %{})
      |> Map.values()
      |> Enum.filter(&(is_map(&1) and Map.get(&1, "is_section") not in ["Y", true, "true"]))

    params
    |> Map.put("filters", filters)
    |> put_sort_intent(sort_by)
  end

  # Column sorting replaces the query's order_by in every view mode.
  defp put_sort_intent(intent, [_ | _] = sort_by),
    do: Map.put(intent, "sort_by", Enum.map(sort_by, &sort_intent/1))

  defp put_sort_intent(intent, _sort_by), do: Map.delete(intent, "sort_by")

  defp sort_intent({column, direction}),
    do: %{"field" => to_string(column), "direction" => to_string(direction)}

  defp sort_intent(other), do: other

  defp filter_build_error(error) do
    %{
      code: :filter_build_failed,
      path: "filters",
      message: "submitted filter could not be compiled",
      reason: inspect(error)
    }
  end

  defp maybe_put_detail_page(params, :detail, socket) do
    if Map.has_key?(socket.assigns, :current_detail_page) do
      Map.put(params, "detail_page", to_string(socket.assigns.current_detail_page))
    else
      params
    end
  end

  defp maybe_put_detail_page(params, _selected_view, _socket), do: params

  defp maybe_apply_denorm_groups(selecto) do
    if Map.has_key?(selecto.set, :denorm_groups) and is_map(selecto.set.denorm_groups) and
         map_size(selecto.set.denorm_groups) > 0 do
      denorm_groups = selecto.set.denorm_groups

      try do
        selecto
        |> SubselectBuilder.generate_subselect_configs(denorm_groups)
        |> Enum.reduce(selecto, fn config, acc ->
          SubselectBuilder.add_subselect_tree(acc, config)
        end)
      rescue
        _e -> selecto
      end
    else
      selecto
    end
  end

  defp maybe_apply_sort(selecto, nil), do: selecto
  defp maybe_apply_sort(selecto, sort_by), do: Sorting.apply_sort_to_query(selecto, sort_by)

  defp merge_library_filters(view_set, []), do: view_set

  defp merge_library_filters(view_set, library_filters) do
    interactive_filters = Map.get(view_set, :filtered, [])
    Map.put(view_set, :filtered, Enum.uniq(library_filters ++ interactive_filters))
  end

  defp get_map_value(map, key, default \\ nil)

  defp get_map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp get_map_value(_map, _key, default), do: default
end
