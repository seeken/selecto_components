defmodule SelectoComponents.Views.Detail.Process do

  def param_to_state(params, _v) do
    %{  ## state is used to draw the form
      selected: SelectoComponents.Helpers.view_param_process(params, "selected", "field"),
      order_by: SelectoComponents.Helpers.view_param_process(params, "order_by", "field"),
      per_page: params["per_page"]
    }
  end

  def initial_state(selecto, v) do
    %{
      order_by: Map.get(selecto.domain, :default_order_by, []) |> SelectoComponents.Helpers.build_initial_state(),
      selected: Map.get(selecto.domain, :default_selected, []) |> SelectoComponents.Helpers.build_initial_state(),
      per_page: "30"
    }
  end

  ### Process incoming params to build Selecto.set for view
  def view(opt, params, columns, filtered, selecto) do
    detail_columns =
      Map.get(params, "selected", %{})
      |> Map.values()
      |> Enum.sort(fn a, b ->
        String.to_integer(a["index"]) <= String.to_integer(b["index"])
      end)

    ### Selecto Set for Detail View, view_meta for view data
    {%{
      columns: detail_columns,
      selected: detail_columns |> selected(columns),
      order_by:
        Map.get(params, "order_by", %{})
        |> order_by(columns),
      filtered: filtered,
      group_by: [],
      groups: []
    }, %{ page: 0, per_page: String.to_integer(params["per_page"]) }}

  end

  def order_by(order_by, _columns) do
    order_by
    |> Map.values()
    |> Enum.sort(fn a, b -> String.to_integer(a["index"]) <= String.to_integer(b["index"]) end)
    |> Enum.map(fn e ->
      case e["dir"] do
        "desc" -> {:desc, e["field"]}
        _ -> e["field"]
      end
    end)
  end

  def selected(detail_selected, columns) do
    date_formats = SelectoComponents.Helpers.date_formats()

    detail_selected
    |> Enum.map(fn e ->
      col = columns[e["field"]]
      uuid = e["uuid"]
      # move to a validation lib
      case col.type do
        x when x in [:naive_datetime, :utc_datetime] ->
          {:field, {:to_char, {col.colid, date_formats[e["format"]]}}, uuid}

        :custom_column ->
          case Map.get(col, :requires_select) do
            x when is_list(x) -> {:row, col.requires_select, uuid}
            x when is_function(x) -> {:row, col.requires_select.(e), uuid}
            nil -> {:field, col.colid, uuid}
          end

        _ ->
          {:field, col.colid, uuid}
      end
    end)
    |> List.flatten()
  end

end
