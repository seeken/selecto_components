defmodule SelectoComponents.Views.Document.Component do
  use Phoenix.LiveComponent

  alias SelectoComponents.Components.NestedTable
  alias SelectoComponents.Views.Document.Template

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    if Map.get(assigns, :execution_error) do
      ~H"""
      <div class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700">
        {inspect(@execution_error)}
      </div>
      """
    else
      case {assigns[:executed], assigns[:query_results]} do
        {false, _} ->
          ~H"""
          <div class="rounded-lg border border-blue-200 bg-blue-50 p-4 text-sm text-blue-600 italic">
            Loading documents...
          </div>
          """

        {true, {_rows, _fields, _aliases}} ->
          render_documents(assigns)

        _ ->
          ~H"""
          <div class="rounded-lg border border-gray-200 bg-white p-4 text-sm text-gray-600">
            No document data available.
          </div>
          """
      end
    end
  end

  defp render_documents(assigns) do
    {rows, columns, _aliases} = assigns.query_results

    normalized_rows =
      if rows != [] and (is_list(hd(rows)) or is_tuple(hd(rows))) do
        Enum.map(rows, fn row ->
          row_values = if is_tuple(row), do: Tuple.to_list(row), else: row
          Enum.zip(columns, row_values) |> Map.new()
        end)
      else
        rows
      end

    template =
      assigns
      |> Map.get(:view_meta, %{})
      |> Map.get(:template, %{"blocks" => []})
      |> Template.normalize()

    blocks = Template.blocks(template)

    subselect_config_map =
      assigns
      |> Map.get(:view_meta, %{})
      |> Map.get(:subselect_configs, [])
      |> Enum.reduce(%{}, fn config, acc ->
        case Map.get(config, :key) do
          key when is_binary(key) -> Map.put(acc, key, config)
          _ -> acc
        end
      end)

    assigns =
      assign(assigns,
        rows: normalized_rows,
        blocks: blocks,
        subselect_config_map: subselect_config_map
      )

    ~H"""
    <div class="space-y-4">
      <%= if @rows == [] do %>
        <div class="rounded-lg border border-gray-200 bg-white p-4 text-sm text-gray-600">
          No documents returned for this query.
        </div>
      <% else %>
        <article
          :for={{row, doc_index} <- Enum.with_index(@rows)}
          class="break-after-page rounded-lg border border-gray-200 bg-white p-6 shadow-sm"
        >
          <div class="mb-4 flex items-center justify-between border-b border-gray-100 pb-3">
            <h2 class="text-base font-semibold text-gray-900">Document {doc_index + 1}</h2>
          </div>

          <div class="space-y-4">
            <div :for={block <- @blocks}>
              <%= case Template.block_type(block) do %>
                <% "title" -> %>
                  <h3 class="text-xl font-semibold text-gray-900">
                    {Template.interpolate(Template.block_text(block), row)}
                  </h3>

                <% "text" -> %>
                  <p class="text-sm leading-6 text-gray-700">
                    {Template.interpolate(Template.block_text(block), row)}
                  </p>

                <% "fields" -> %>
                  <% fields = Template.block_fields(block) %>
                  <section>
                    <h4 class="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">
                      {Template.block_title(block, "Details")}
                    </h4>
                    <dl class="grid gap-2 sm:grid-cols-2">
                      <div :for={field_name <- fields} class="rounded-md border border-gray-100 bg-gray-50 p-2">
                        <dt class="text-xs font-medium uppercase tracking-wide text-gray-500">
                          {NestedTable.humanize_key(field_name)}
                        </dt>
                        <dd class="mt-1 text-sm text-gray-900">
                          {Template.printable_value(Template.row_value(row, field_name))}
                        </dd>
                      </div>
                    </dl>
                  </section>

                <% "table" -> %>
                  <% table_name = Template.block_table(block) %>
                  <% config = Map.get(@subselect_config_map, table_name, %{key: table_name, columns: []}) %>
                  <% parsed_data = Template.subtable_rows(row, table_name, config) %>
                  <section>
                    <h4 class="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-700">
                      {Template.block_title(block, NestedTable.humanize_key(table_name))}
                    </h4>

                    <%= if parsed_data == [] do %>
                      <div class="rounded-md border border-gray-100 bg-gray-50 px-3 py-2 text-sm text-gray-500 italic">
                        No related data
                      </div>
                    <% else %>
                      <div class="overflow-x-auto rounded-md border border-gray-200">
                        <table class="min-w-full divide-y divide-gray-200">
                          <thead class="bg-gray-50">
                            <tr>
                              <th
                                :for={key <- NestedTable.get_data_keys(parsed_data)}
                                class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-gray-600"
                              >
                                {NestedTable.humanize_key(key)}
                              </th>
                            </tr>
                          </thead>
                          <tbody class="divide-y divide-gray-100 bg-white">
                            <tr :for={item <- parsed_data}>
                              <td
                                :for={key <- NestedTable.get_data_keys(parsed_data)}
                                class="px-3 py-2 text-sm text-gray-800"
                              >
                                {NestedTable.format_value(Map.get(item, key, ""))}
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                    <% end %>
                  </section>

                <% _ -> %>
                  <div class="hidden"></div>
              <% end %>
            </div>
          </div>
        </article>
      <% end %>
    </div>
    """
  end
end
