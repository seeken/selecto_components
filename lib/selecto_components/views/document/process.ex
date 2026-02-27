defmodule SelectoComponents.Views.Document.Process do
  @moduledoc false

  def param_to_state(_params, _view) do
    %{
      selected: [],
      subtable_fields: [],
      template: %{blocks: []},
      per_page: "30",
      max_rows: "1000"
    }
  end

  def initial_state(_selecto, _view) do
    %{
      selected: [],
      subtable_fields: [],
      template: %{blocks: []},
      per_page: "30",
      max_rows: "1000"
    }
  end

  def view(_opt, _params, _columns, filtered, _selecto) do
    view_set = %{
      columns: [],
      selected: [],
      order_by: [],
      filtered: filtered,
      group_by: [],
      groups: [],
      subselects: [],
      denorm_groups: %{}
    }

    {view_set, %{page: 0, per_page: 30, max_rows: "1000", total_rows: 0}}
  end
end
