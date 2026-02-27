defmodule SelectoComponents.Views.Document.Form do
  use Phoenix.LiveComponent

  alias SelectoComponents.Views.Document.Options
  alias SelectoComponents.Views.Document.Template

  def render(assigns) do
    document_config =
      assigns.view_config
      |> Map.get(:views, %{})
      |> Map.get(:document, %{})

    selected_items =
      document_config
      |> Map.get(:selected, Map.get(document_config, "selected", []))
      |> to_tuple_items()

    subtable_items =
      document_config
      |> Map.get(:subtable_fields, Map.get(document_config, "subtable_fields", []))
      |> to_tuple_items()

    template =
      document_config
      |> Map.get(:template, Map.get(document_config, "template", %{"blocks" => []}))
      |> Template.normalize()

    template_blocks = Template.blocks(template)

    title_block =
      find_block(template_blocks, "title", %{"type" => "title", "text" => "Document {{id}}"})

    fields_block =
      find_block(template_blocks, "fields", %{"type" => "fields", "title" => "Details", "fields" => []})

    table_block =
      find_block(template_blocks, "table", %{"type" => "table", "title" => "Related", "table" => ""})

    per_page =
      document_config
      |> Map.get(:per_page, Map.get(document_config, "per_page", Options.default_per_page()))
      |> Options.normalize_per_page_param()

    max_rows =
      document_config
      |> Map.get(:max_rows, Map.get(document_config, "max_rows", Options.default_max_rows()))
      |> Options.normalize_max_rows_param()

    related_columns = Enum.filter(assigns.columns, &related_column?/1)

    assigns =
      assign(assigns,
        document_selected_items: selected_items,
        document_subtable_items: subtable_items,
        document_root_available: assigns.columns,
        document_subtable_available: if(related_columns == [], do: assigns.columns, else: related_columns),
        document_per_page: per_page,
        document_max_rows: max_rows,
        document_per_page_options: Options.per_page_options(),
        document_max_rows_options: Options.max_rows_options(),
        title_block: title_block,
        fields_block: fields_block,
        table_block: table_block,
        fields_csv: fields_block_fields_csv(fields_block)
      )

    ~H"""
    <div class="space-y-6">
      <div>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">Document Fields</h3>

        <.live_component
          module={SelectoComponents.Components.ListPicker}
          id="document_selected"
          fieldname="selected"
          available={@document_root_available}
          view={@view}
          selected_items={@document_selected_items}
        >
          <:item_form :let={{id, item, config, index}}>
            <input name={"document_selected[#{id}][field]"} type="hidden" value={item} />
            <input name={"document_selected[#{id}][index]"} type="hidden" value={index} />
            <input name={"document_selected[#{id}][uuid]"} type="hidden" value={id} />

            <label class="mb-1 block text-xs font-medium text-gray-600">Alias</label>
            <input
              type="text"
              name={"document_selected[#{id}][alias]"}
              value={config_value(config, "alias")}
              class="input input-bordered input-sm w-full"
              placeholder="Leave blank to use field name"
            />
          </:item_form>
        </.live_component>
      </div>

      <div>
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">Subtables</h3>
        <p class="mb-2 text-xs text-gray-500">
          Add related fields (for example <code>posts.title</code>) to render nested tables.
        </p>

        <.live_component
          module={SelectoComponents.Components.ListPicker}
          id="document_subtable_fields"
          fieldname="subtable_fields"
          available={@document_subtable_available}
          view={@view}
          selected_items={@document_subtable_items}
        >
          <:item_form :let={{id, item, _config, index}}>
            <input name={"document_subtable_fields[#{id}][field]"} type="hidden" value={item} />
            <input name={"document_subtable_fields[#{id}][index]"} type="hidden" value={index} />
            <input name={"document_subtable_fields[#{id}][uuid]"} type="hidden" value={id} />
            <div class="text-xs text-gray-600">{item}</div>
          </:item_form>
        </.live_component>
      </div>

      <div class="rounded-md border border-gray-200 bg-gray-50 px-3 py-2">
        <h3 class="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">Template Blocks</h3>

        <div class="grid gap-3 md:grid-cols-2">
          <div>
            <input name="document_template[blocks][0][type]" type="hidden" value="title" />
            <label class="mb-1 block text-xs font-medium text-gray-700">Title</label>
            <input
              type="text"
              name="document_template[blocks][0][text]"
              value={Template.block_text(@title_block)}
              class="input input-bordered input-sm w-full"
              placeholder="Invoice for {{customer_name}}"
            />
          </div>

          <div>
            <input name="document_template[blocks][1][type]" type="hidden" value="fields" />
            <label class="mb-1 block text-xs font-medium text-gray-700">Fields Section Title</label>
            <input
              type="text"
              name="document_template[blocks][1][title]"
              value={Template.block_title(@fields_block, "Details")}
              class="input input-bordered input-sm w-full"
            />
            <label class="mb-1 mt-2 block text-xs font-medium text-gray-700">Fields (comma separated)</label>
            <input
              type="text"
              name="document_template[blocks][1][fields]"
              value={@fields_csv}
              class="input input-bordered input-sm w-full"
              placeholder="name,email,phone"
            />
          </div>

          <div>
            <input name="document_template[blocks][2][type]" type="hidden" value="table" />
            <label class="mb-1 block text-xs font-medium text-gray-700">Table Section Title</label>
            <input
              type="text"
              name="document_template[blocks][2][title]"
              value={Template.block_title(@table_block, "Related")}
              class="input input-bordered input-sm w-full"
            />
            <label class="mb-1 mt-2 block text-xs font-medium text-gray-700">Table Source</label>
            <input
              type="text"
              name="document_template[blocks][2][table]"
              value={Template.block_table(@table_block)}
              class="input input-bordered input-sm w-full"
              placeholder="posts"
            />
          </div>
        </div>
      </div>

      <div class="rounded-md border border-gray-200 bg-gray-50 px-3 py-2">
        <div class="grid gap-3 md:grid-cols-2">
          <label class="block text-sm">
            <span class="text-xs font-medium text-gray-700">Documents Per Page</span>
            <select
              name="document_per_page"
              class="mt-1 select select-bordered select-sm w-full bg-white"
            >
              <option
                :for={option <- @document_per_page_options}
                selected={@document_per_page == to_string(option)}
                value={option}
              >
                {option}
              </option>
            </select>
          </label>

          <label class="block text-sm">
            <span class="text-xs font-medium text-gray-700">Max Documents Returned</span>
            <select
              name="document_max_rows"
              class="mt-1 select select-bordered select-sm w-full bg-white"
            >
              <option
                :for={option <- @document_max_rows_options}
                selected={@document_max_rows == to_string(option)}
                value={to_string(option)}
              >
                {if option == "all", do: "All", else: option}
              </option>
            </select>
          </label>
        </div>
      </div>
    </div>
    """
  end

  defp to_tuple_items(items) when is_list(items) do
    Enum.map(items, fn
      [uuid, field, config] -> {uuid, field, config}
      {uuid, field, config} -> {uuid, field, config}
      other -> other
    end)
  end

  defp to_tuple_items(_items), do: []

  defp find_block(blocks, type, default) do
    Enum.find(blocks, default, fn block -> Template.block_type(block) == type end)
  end

  defp fields_block_fields_csv(block) do
    block
    |> Template.block_fields()
    |> Enum.join(",")
  end

  defp related_column?({field, _name, _format}) when is_binary(field) do
    String.contains?(field, ".") or String.contains?(field, "[")
  end

  defp related_column?({field, _name, _format}) when is_atom(field) do
    field
    |> Atom.to_string()
    |> related_field_string?()
  end

  defp related_column?(_), do: false

  defp related_field_string?(field) do
    String.contains?(field, ".") or String.contains?(field, "[")
  end

  defp config_value(config, key) when is_map(config) do
    atom_key =
      case key do
        "alias" -> :alias
        _ -> nil
      end

    Map.get(config, key, Map.get(config, atom_key, ""))
  end

  defp config_value(_config, _key), do: ""
end
