defmodule SelectoComponents.Components.DetailTable do
  @doc """
    Display results of a detail view

  """

  use Phoenix.LiveComponent

  def render(assigns) do
    {results, aliases} = Selecto.execute(assigns.selecto)

    selected = assigns.selecto.set.selected

    selected =
      Enum.map(selected, fn
        {a, f} = sel ->
          {sel, assigns.selecto.config.columns[f]}

        f ->
          {f, assigns.selecto.config.columns[f]}
      end)

    fmap = Enum.zip(aliases, selected) |> Enum.into(%{})


    page = assigns.page;
    per_page = assigns.per_page
    IO.inspect(per_page)

    show_start = page * per_page
    show_end = show_start + per_page

    page_count = Float.ceil(Enum.count(results) / per_page)

    assigns = assign(assigns, fmap: fmap, results: results, aliases: aliases, max_pages: page_count)

    ~H"""
    <div>


      <button :if={@page > 0} type="button" phx-click="set_page" phx-value-page={@page - 1} phx-target={@myself}>Prev Page</button>
      <span><%= Enum.count(@results) %> Rows Found</span>
      <button :if={@page < @max_pages} type="button" phx-click="set_page" phx-value-page={@page + 1} phx-target={@myself}>Next Page</button>


      <table class="min-w-full overflow-hidden divide-y ring-1 ring-gray-200 dark:ring-0 divide-gray-200 rounded-sm table-auto dark:divide-y-0 dark:divide-gray-800 sm:rounded">
        <tr>
          <th class="px-6 py-3 text-xs font-medium tracking-wider text-left text-gray-700 uppercase bg-gray-50 dark:bg-gray-600 dark:text-gray-300">#</th>
          <th :for={r <- @aliases} class="px-6 py-3 text-xs font-medium tracking-wider text-left text-gray-700 uppercase bg-gray-50 dark:bg-gray-600 dark:text-gray-300">
            <%= r %>
          </th>
        </tr>
        <tr :for={{r, i} <- Enum.slice(Enum.with_index(@results), show_start, per_page)} class="border-b dark:border-gray-700 bg-white even:bg-white dark:bg-gray-700 dark:even:bg-gray-800 last:border-none">
          <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
            <%= i + 1 %>
          </td>
          <td :for={c <- @aliases} class="px-6 py-4 text-sm text-gray-500 dark:text-gray-400">
            <%= with {sel, def} <- @fmap[c] do %>
              <%= case def do %>
                <% %{link: fmt_fun} = def when is_function(fmt_fun) -> %>

                <% %{format: fmt_fun} = def when is_function(fmt_fun) -> %>
                  <%= fmt_fun.(r[c]) %>
                <% _ -> %>
                  <%= r[c] %>
              <%= end %>
            <%= end %>
          </td>
        </tr>
      </table>
    </div>
    """
  end

  def handle_event("set_page", params, socket) do
    send(self(), {:set_detail_page, params["page"]})

    {:noreply, socket}
  end



end
