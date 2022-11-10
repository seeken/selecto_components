defmodule SelectoComponents.ViewSelector do
  use Phoenix.LiveComponent

  # use Phoenix.Component
  import SelectoComponents.Components.Common

  def render(assigns) do
    assigns =
      assign(assigns,
        columns:
          Map.values(assigns.selecto.config.columns)
          |> Enum.filter(fn c -> c.type != :custom_filter end)
          |> Enum.sort(fn a, b -> a.name <= b.name end)
          |> Enum.map(fn c -> {c.colid, c.name} end),
        available_filters:
          Map.values(assigns.selecto.config.columns)
          |> Enum.filter(fn c -> c.type != :custom_column end)
          |> Enum.sort(fn a, b -> a.name <= b.name end)
          |> Enum.map(fn c -> {c.colid, c.name} end),


      )

    ~H"""
      <div class="border-solid border rounded-md border-grey dark:border-black h-100 overflow-auto p-1">

        <.form for={:view} phx-change="view-validate" phx-submit="view-apply">
          <!--TODO use LiveView.JS? --> <!-- Make tabs component?-->
          <.button type="button" phx-click="set_active_tab" phx-value-tab="view" phx-target={@myself}>View Tab</.button>
          <.button type="button" phx-click="set_active_tab" phx-value-tab="filter" phx-target={@myself}>Filter Tab</.button>
          <.button type="button" phx-click="set_active_tab" phx-value-tab="export" phx-target={@myself}>Export Tab</.button>

          <div class={if @active_tab == "view" or @active_tab == nil do "border-solid border rounded-md border-grey dark:border-black h-90 p-1" else "hidden" end}>

      View Type
            <.live_component
              module={SelectoComponents.Components.RadioTabs}
              id="view_mode"
              fieldname="view_mode"
              view_mode={@view_mode}>
              <:section id="aggregate" label="Aggregate View">

      Group By
                <.live_component
                  module={SelectoComponents.Components.ListPicker}
                  id="group_by"
                  fieldname="group_by"
                  available={@columns}
                  selected_items={@group_by}>
                  <:item_form :let={{id, item, config, index} }>
                    <input name={"group_by[#{id}][field]"} type="hidden" value={item}/>
                    <input name={"group_by[#{id}][index]"} type="hidden" value={index}/>
                    <.live_component
                      module={SelectoComponents.Components.GroupByConfig}
                      id={id}
                      col={@selecto.config.columns[item]}
                      uuid={id}
                      item={item}
                      fieldname="group_by"
                      config={config}/>
                  </:item_form>
                </.live_component>

      Aggregates:
                  <.live_component
                    module={SelectoComponents.Components.ListPicker}
                    id="aggregate"
                    fieldname="aggregate"
                    available={@columns}
                    selected_items={@aggregate}>
                  <:item_form :let={{id, item, config, index}}>
                    <input name={"aggregate[#{id}][field]"} type="hidden" value={item}/>
                    <input name={"aggregate[#{id}][index]"} type="hidden" value={index}/>
                    <.live_component
                      module={SelectoComponents.Components.AggregateConfig}
                      id={id}
                      col={@selecto.config.columns[item]}
                      uuid={id}
                      item={item}
                      fieldname="aggregate"
                      config={config}/>
                  </:item_form>
                </.live_component>
              </:section>
              <:section id="detail" label="Detail View">

      Columns
                <.live_component
                    module={SelectoComponents.Components.ListPicker}
                    id="selected"
                    fieldname="selected"
                    available={@columns}
                    selected_items={@selected}>
                  <:item_form :let={{id, item, config, index} }>
                    <input name={"selected[#{id}][field]"} type="hidden" value={item}/>
                    <input name={"selected[#{id}][index]"} type="hidden" value={index}/>
                    <.live_component
                      module={SelectoComponents.Components.ColumnConfig}
                      id={id}
                      col={@selecto.config.columns[item]}
                      uuid={id}
                      item={item}
                      fieldname="selected"
                      config={config}/>
                  </:item_form>
                </.live_component>


      Order by
                <.live_component
                    module={SelectoComponents.Components.ListPicker}
                    id="order_by"
                    fieldname="order_by"
                    available={@columns}
                    selected_items={@order_by}>
                  <:item_form :let={{id, item, config, index} }>
                    <%!-- MAKE THIS INTO COMPOENT SO IT DOESN"T REDRAW ALL THE TIME and lose its form! --%>
                    <input name={"order_by[#{id}][field]"} type="hidden" value={item}/>
                    <input name={"order_by[#{id}][index]"} type="hidden" value={index}/>
                    <%= item %>
                    <label><input name={"order_by[#{id}][dir]"} type="radio" value="asc" checked={Map.get(config, "dir")=="asc"}/>Ascending</label>
                    <label><input name={"order_by[#{id}][dir]"} type="radio" value="desc" checked={Map.get(config, "dir")=="desc"}/>Descending</label>
                  </:item_form>
                </.live_component>
      Pagination
                Per Page:
                <select name="per_page">
                  <option :for={i <- [30]} selected={@per_page == i} value={i}><%= i %></option>
                </select>

              </:section>
            </.live_component>
          </div>

          <div class={if @active_tab == "filter" do "border-solid border rounded-md border-grey dark:border-black h-90  p-1" else "hidden" end}>

      FILTER SECTION
            <.live_component
                    module={SelectoComponents.Components.TreeBuilder}
                    id="filter_tree"
                    available={@available_filters}
                    filters={@filters}
                    >

              <:filter_form :let={{uuid, index, section, fv}}>
                <.live_component
                    module={SelectoComponents.Components.FilterForms}
                    id={uuid}
                    uuid={uuid}
                    section={section}
                    index={index}
                    filter={fv}
                    columns={@selecto.config.columns}
                    filters_available={@selecto.config.filters}
                    >
                </.live_component>
              </:filter_form>

            </.live_component>



          </div>

          <div class={if @active_tab == "export" do "border-solid border rounded-md border-grey dark:border-black h-90 overflow-auto p-1" else "hidden" end}>
            EXPORT SECTION PLANNED
            export format: spreadsheet, text, csv, PDF?, JSON, XML

            download / send via email (add note)

            collate and send to an email address in a column
          </div>

          <.button>Submit</.button>


        </.form>
      </div>

    """
  end

  def handle_event("set_active_tab", params, socket) do
    send(self(), {:set_active_tab, params["tab"]})
    {:noreply, socket}
  end

  defmacro __using__(_opts \\ []) do
    quote do
      ### These run in the 'use'ing liveview's context

      @impl true
      def handle_params(params, _uri, socket) do

        socket =
          assign(socket,
            ### required for selecto components

            executed: false,
            applied_view: nil,

            view_mode: params["view_mode"] || "detail",
            active_tab: params["active_tab"] || "view",
            per_page: if params["per_page"] do String.to_integer(params["per_page"]) else 30 end,
            page: if params["page"] do String.to_integer(params["page"]) else 0 end,

            aggregate: [],
            group_by: [],
            order_by: [],
            selected: [],
            filters: []
          )

        {:noreply, socket}
      end



      defp _make_num_filter(filter) do
        comp = filter["comp"]
        ## TODO
        value = String.to_integer(filter["value"])

        case comp do
          "=" ->
            value

          "between" ->
            {:between, value, String.to_integer(filter["value2"])}

          x when x in ~w( != <= >= < >) ->
            {x, value}
        end
      end

      defp _make_string_filter(filter) do
        comp = filter["comp"]
        ## TODO
        ignore_case = filter["ignore_case"]
        value = filter["value"]

        case comp do
          "=" ->
            value

          x when x in ~w( != <= >= < >) ->
            {x, value}

          "starts" ->
            {:like, value <> "%"}

          "ends" ->
            {:like, "%" <> value}

          "contains" ->
            {:like, "%" <> value <> "%"}
        end
      end

      defp _make_date_filter(filter) do
        comp = filter["comp"]
        ## TODO handle time zones...
        {:ok, value, _} = DateTime.from_iso8601(filter["value"] <> ":00Z")
        {:ok, value2, _} = DateTime.from_iso8601(filter["value2"] <> ":00Z")
        ### Add more options

        {:between, value, value2}
      end

      ## Build filters that can be sent to the selecto
      def filter_recurse(selecto, filters, section) do
        #### TODO handle errors
        Enum.reduce(Map.get(filters, section, []), [], fn
          %{"is_section" => "Y", "uuid" => uuid, "conjunction" => conj} = f, acc ->
            acc ++ [{case conj do
              "AND" -> :and
              "OR" -> :or
            end, filter_recurse(selecto, filters, uuid)}]

          f, acc ->
            if selecto.config.filters[f["filter"]] do
              selecto.config.filters[f["filter"]]
            else
              case selecto.config.columns[f["filter"]].type do
                x when x in [:id, :integer, :float, :decimal] ->
                  acc ++ [{f["filter"], _make_num_filter(f)}]

                :boolean ->
                  acc ++ [{f["filter"], case f["value"] do
                    "true" -> true
                    _ -> false
                  end
                  }]

                :string ->
                  acc ++ [{f["filter"], _make_string_filter(f)}]

                x when x in [:naive_datetime, :utc_datetime] ->
                  acc ++ [{f["filter"], _make_date_filter(f)}]

                {:parameterized, _, enum_conf} ->
                  acc ++ [{f["filter"], f["selected"]}]
              end
            end
        end)
      end

      ## TODO validate form entry, display errors to user, keep order stable
      ## On Change
      @impl true
      def handle_event("view-validate", params, socket) do
        filters = Map.get(params, "filters", %{})
        |> Map.values()
        |> Enum.sort(fn a, b -> a <= b end)
        |> Enum.reduce(
          [],
          fn f, acc ->
            acc ++ [{f["uuid"], f["section"], case Map.get(f, "conjunction", nil) do
              nil -> f
              a -> a
            end}]
          end
        )

        socket = assign(socket, :per_page, String.to_integer(params["per_page"]))

        {:noreply, assign( socket, filters: filters ) }
      end

      def do_view(selecto) do
      end

      # on submit
      @impl true
      def handle_event("view-apply", params, socket) do
        try do

          IO.inspect(params, label: "Params")
          # move this somewhere shared
          date_formats = %{
            "MM-DD-YYYY HH:MM" => "MM-DD-YYYY HH:MM",
            "YYYY-MM-DD HH:MM" => "YYYY-MM-DD HH:MM"
          }

          selecto = socket.assigns.selecto
          columns = selecto.config.columns

          selected = params["selected"]
          order_by = Map.get(params, "order_by", %{})
          aggregate = params["aggregate"]
          group_by = Map.get(params, "group_by", %{})

          filters_by_section =
            Map.values(Map.get(params, "filters", %{}))
            |> Enum.reduce(
              %{},
              fn f, acc ->
                ## Custom Form Processor?

                Map.put(acc, f["section"], Map.get(acc, f["section"], []) ++ [f])
              end
            )

          ## Build filters walking the filters_by_section
          socket =
           assign(socket,
             filters: Map.values(Map.get(params, "filters", %{}))
              |> Enum.map( fn
                %{"is_section"=>"Y"} = f -> {f["uuid"], f["section"], f["conjunction"]}
                f -> {f["uuid"], f["section"], f}
              end
              )

           )

          ## THIS CAN FAIL...
          filtered = filter_recurse(selecto, filters_by_section, "filters")

          selecto =
            Map.put(
              selecto,
              :set,
              case params["view_mode"] do
                "detail" ->
                  detail_columns = selected
                  |> Map.values()
                  |> Enum.sort(fn a, b ->
                    String.to_integer(a["index"]) <= String.to_integer(b["index"])
                  end)
                  selected =
                    detail_columns

                    |> Enum.map(fn e ->
                      col = columns[e["field"]]
                      # move to a validation lib
                      case col.type do
                        x when x in [:naive_datetime, :utc_datetime] ->
                          {:to_char, {col.colid, date_formats[e["format"]]}, col.colid}

                        :custom_column ->
                          case col.requires_select do
                            x when is_list(x) -> col.requires_select
                            x when is_function(x) -> col.requires_select.(e)
                          end

                        _ ->
                          col.colid
                      end
                    end)
                    |> List.flatten
                    |> IO.inspect

                  order_by =
                    order_by
                    |> Map.values()
                    |> Enum.sort(fn a, b -> a["index"] <= b["index"] end)
                    |> Enum.map(fn e ->
                      case e["dir"] do
                        "desc" -> {:desc, e["field"]}
                        _ -> e["field"]
                      end
                    end)

                  ### TODO add config
                  %{
                    columns: detail_columns,  ### Columns will be used be
                    selected: selected,
                    order_by: order_by,
                    filtered: filtered,
                    group_by: []
                  }

                "aggregate" ->
                  aggregate =
                    aggregate
                    |> Map.values()
                    |> Enum.sort(fn a, b -> a["index"] <= b["index"] end)
                    ### TODO apply config
                    |> Enum.map(fn
                      ### Make sure e["format"] is a valid field name!
                      e ->
                        {String.to_atom(
                          case e["format"] do
                            nil -> "count"
                            _ -> e["format"]
                          end
                        ), e["field"]}
                    end)

                  group_by =
                    group_by
                    |> Map.values()
                    |> Enum.sort(fn a, b -> a["index"] <= b["index"] end)
                    ### TODO apply config
                    |> Enum.map(fn e ->
                      col = columns[e["field"]]

                      case col.type do
                        x when x in [:naive_datetime, :utc_datetime] ->
                          {:extract, col.colid, e["format"]}

                        ### add support for YYYY-MM-DD also..

                        _ ->
                          col.colid
                      end
                    end)

                  ### todo add config
                  %{
                    selected: group_by ++ aggregate,
                    filtered: filtered,
                    group_by: [{:rollup, group_by}],
                    order_by: group_by
                  }
              end
            )

          ### Set these assigns to reset the view!
          {:noreply, assign(socket,
            selecto: selecto,
            applied_view: socket.assigns.view_mode,
            executed: true,
            page: 0,
            per_page: String.to_integer(params["per_page"])
          )}

        rescue
          e -> IO.inspect(e)
            {:noreply, socket}
        end
      end

      @impl true
      def handle_event("filter_from_aggregate", par, socket) do

      end

      @impl true
      def handle_event("treedrop", par, socket) do
        new_filter = par["element"]
        target = par["target"]

        socket =
          assign(socket,
            filters:
              socket.assigns.filters ++
                case new_filter do
                  "__AND__" -> [{UUID.uuid4(), target, "AND"}]
                  "__OR__" ->  [{UUID.uuid4(), target, "OR"}]
                  _ ->         [{UUID.uuid4(), target, %{"filter" => new_filter, "value" => nil}}]
                end
          )

        {:noreply, socket}
      end

      @impl true
      def handle_info({:set_active_tab, tab}, socket) do
        {:noreply, assign(socket, active_tab: tab)}
      end

      @impl true
      def handle_info({:view_set, view}, socket) do
        {:noreply, assign(socket, view_mode: view)}
      end

      @impl true
      def handle_info({:set_detail_page, page}, socket) do
        {:noreply, assign(socket, page: String.to_integer(page))}
      end

      @impl true
      def handle_info({:list_picker_remove, list, item}, socket) do
        list = String.to_atom(list)

        socket =
          assign(socket, list, Enum.filter(socket.assigns[list], fn {id, _, _} -> id != item end))

        {:noreply, socket}
      end

      ### TODO fix this up

      @impl true
      def handle_info({:list_picker_move, list, uuid, direction}, socket) do
        list = String.to_atom(list)
        item_list = socket.assigns[list]
        item_index = Enum.find_index(item_list, fn {i, _, _} -> i == uuid end)
        {item, item_list} = List.pop_at(item_list, item_index)

        item_list =
          List.insert_at(
            item_list,
            case direction do
              "up" -> item_index - 1
              "down" -> item_index + 1
            end,
            item
          )

        socket = assign(socket, list, item_list)
        {:noreply, socket}
      end

      @impl true
      def handle_info({:list_picker_add, list, item}, socket) do
        list = String.to_atom(list)
        id = UUID.uuid4()
        socket = assign(socket, list, Enum.uniq(socket.assigns[list] ++ [{id, item, %{}}]))
        {:noreply, socket}
      end

      # :list_picker_config_item, list, uuid, newconf
    end
  end
end
