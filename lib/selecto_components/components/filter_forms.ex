defmodule SelectoComponents.Components.FilterForms do
  use Phoenix.LiveComponent
  import SelectoComponents.Components.Common

  def render(assigns) do
    filter_def =
      Map.get(assigns.custom_filters, assigns.filter["filter"]) ||
        Map.get(assigns.columns, assigns.filter["filter"])

    #  Map.get(assigns.filters(filter))

    type = Map.get(filter_def, :filter_type, filter_def.type)
    assigns = assign(assigns, type: type, def: filter_def)

    ~H"""
      <div>
        <input name={"filters[#{@uuid}][filter]"} type="hidden" value={@filter["filter"]}/>
        <input name={"filters[#{@uuid}][section]"} type="hidden" value={@section}/>
        <input name={"filters[#{@uuid}][index]"} type="hidden" value={@index}/>
        <input name={"filters[#{@uuid}][uuid]"} type="hidden" value={@uuid}/>

        <%= render_form(%{type: @type, uuid: @uuid, id: @id, filter: @filter, def: @def} ) %>
        <%!-- TODO: SHOW ERRORS --%>

      </div>
    """
  end

  def render_form(%{type: :string} = assigns) do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    ~H"""
      <div>
        <label>
          <%= @def.name %>
          <.sc_select_with_slot name={"filters[#{@uuid}][comp]"}>
            <option value="=" selected={Map.get(@valmap, "comp") == "="}>Equals</option>
            <option value="!=" selected={Map.get(@valmap, "comp") == "!="}>Not Equals</option>
            <option value="starts" selected={Map.get(@valmap, "comp") == "starts"}>Starts With</option>
            <option value="ends" selected={Map.get(@valmap, "comp") == "ends"}>Ends With</option>
            <option value="contains" selected={Map.get(@valmap, "comp") == "contains"}>Contains</option>
            <option value="null" selected={Map.get(@valmap, "comp") == "null"}>Null</option>
            <option value="not_null" selected={Map.get(@valmap, "comp") == "not_null"}>Not Null</option>
          </.sc_select_with_slot>
          <.sc_input name={"filters[#{@uuid}][value]"} value={@valmap["value"]}/>
          <!-- <label><input type="checkbox" name={"filters[#{@uuid}][ignore_case]"} value="Y"/>Ignore Case</label> -->
        </label>
      </div>
    """
  end

  def render_form(%{type: t} = assigns) when t in [:id, :integer] do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    ~H"""
      <div>

        <label>
          <%= @def.name %>
          <.sc_select_with_slot name={"filters[#{@uuid}][comp]"}>
            <option value="=" selected={Map.get(@valmap, "comp") == "="}>Equals</option>
            <option value="!=" selected={Map.get(@valmap, "comp") == "!="}>Not Equals</option>
            <option value="<" selected={Map.get(@valmap, "comp") == "<"}>Less Than</option>
            <option value=">" selected={Map.get(@valmap, "comp") == ">"}>Greater Than</option>
            <option value="<=" selected={Map.get(@valmap, "comp") == "<="}>Less Than/Equal</option>
            <option value=">=" selected={Map.get(@valmap, "comp") == ">="}>Greater Than/Equal</option>
            <option value="between" selected={Map.get(@valmap, "comp") == "between"}>Between</option>
            <option value="null" selected={Map.get(@valmap, "comp") == "null"}>Null</option>
            <option value="not_null" selected={Map.get(@valmap, "comp") == "not_null"}>Not Null</option>

          </.sc_select_with_slot>
          <.sc_input name={"filters[#{@uuid}][value]"} value={@valmap["value"]}/>
          <.sc_input name={"filters[#{@uuid}][value2]"} value={@valmap["value2"]}/>

        </label>
      </div>
    """
  end

  def render_form(%{type: t} = assigns) when t in [:decimal, :float] do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    ~H"""
      <div>
        <label>
          <%= @def.name %>
          <.sc_select_with_slot name={"filters[#{@uuid}][comp]"}>
            <option value="=" selected={Map.get(@valmap, "comp") == "="}>Equals</option>
            <option value="!=" selected={Map.get(@valmap, "comp") == "!="}>Not Equals</option>
            <option value="<" selected={Map.get(@valmap, "comp") == "<"}>Less Than</option>
            <option value=">" selected={Map.get(@valmap, "comp") == ">"}>Greater Than</option>
            <option value="<=" selected={Map.get(@valmap, "comp") == "<="}>Less Than/Equal</option>
            <option value=">=" selected={Map.get(@valmap, "comp") == ">="}>Greater Than/Equal</option>
            <option value="between" selected={Map.get(@valmap, "comp") == "between"}>Between</option>
            <option value="null" selected={Map.get(@valmap, "comp") == "null"}>Null</option>
            <option value="not_null" selected={Map.get(@valmap, "comp") == "not_null"}>Not Null</option>

          </.sc_select_with_slot>
          <.sc_input name={"filters[#{@uuid}][value]"} value={@valmap["value"]}/>
          <.sc_input name={"filters[#{@uuid}][value2]"} value={@valmap["value2"]}/>
          <%!--
          <label>Round to for Comparison
          <select name={"filters[#{@uuid}][precision]]"}>

            <option :for={p <- Enum.to_list(0..5)} value={p} selected={Map.get(@valmap, "precision") == p}><%= p %></option>
          </select>
          </label>
          --%>

        </label>
      </div>
    """
  end

  def render_form(%{type: :boolean} = assigns) do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    ~H"""
      <div>
        <%= @type %> <%= @def.name %>
        <label>Y
          <.sc_input type="radio" name={"filters[#{@uuid}][value]"} checked={@valmap["value"] == "true"} value="true"/>
        </label>
        <label>N
          <.sc_input type="radio" name={"filters[#{@uuid}][value]"} checked={@valmap["value"] != "true"} value="false"/>
        </label>
      </div>
    """
  end

  defp reformat_date(date) when is_binary(date) do
    date = String.replace(date, ~r/Z/, "")
  end

  defp reformat_date(date) do
    date
  end


  def render_form(%{type: type} = assigns) when type in [:naive_datetime, :utc_datetime] do
    def = assigns.def
    valmap = assigns.filter
    #|> IO.inspect(label: "Create Date Form")
    assigns = Map.put(assigns, :valmap, valmap)

    ### TODO
    # Support shortcuts: today, tomorrow, yesterday, this week, last week, next week, this cal month, last cal month, next cal month,
    # this year, last year, trailing twelve cal months
    # last 7 days, last 30 days, last 90 days,
    # next 7 days, next 30 days, next 90 days,
    # this quarter, next quarter, this quarter last year, last quarter last year
    # YTD, YTD Last year
    # ### How to configure default time zones?

    ~H"""
    <div>
      <label>
        <%= @def.name %>
        After:
        <.sc_input type="datetime-local" step="1" name={"filters[#{@uuid}][value]"} value={reformat_date( @valmap["value"] )}/>
      </label>
      <label>
        Before:
        <.sc_input type="datetime-local" step="1" name={"filters[#{@uuid}][value2]"} value={reformat_date( @valmap["value2"] )}/>
      </label>
    </div>
    """
  end

  def render_form(%{type: :component} = assigns) do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    def.component.(assigns)
  end

  def render_form(%{type: :custom} = assigns) do
    def = assigns.def
    valmap = assigns.filter
    assigns = Map.put(assigns, :valmap, valmap) |> Map.put(:def, def)

    ~H"""
      H: <%= @type %> <%= @filter %>
    """
  end

  def render_form(%{type: {:parameterized, Ecto.Enum, typemap}} = assigns) do
    assigns = Map.put(assigns, :values, typemap.mappings)
    valmap = assigns.filter

    assigns = Map.put(assigns, :valmap, valmap)

    ~H"""
      <div>
        <%= @def.name %>
        <label :for={{_a, v} <- @values}>
          <input name={"filters[#{@uuid}][selected][]"}
            id={"filters_#{@uuid}_selected_#{v}"}
            type="checkbox"
            value={v}
            checked={ Enum.member?(Map.get(@valmap, "selected", []), v) }/>
          <%= v %>
        </label>

      </div>
    """
  end
end
