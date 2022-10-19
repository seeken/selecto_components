defmodule ListableComponentsPetal.Components.ListPicker do
  @doc """
    Given a list of items, allow user to select items, put them in order, configure the order

    To be used by view builder

    TODO
      add a little x button to remove
      up, down arrows on hover in selected section
      ability to add tooltips or descriptions to available {id, name, descr}?

  """
  use Phoenix.LiveComponent

  attr(:avail, :list, required: true)
  attr(:selected_items, :list, required: true)
  attr(:fieldname, :string, required: true)

  slot(:item_form)

  def render(assigns) do
    ~H"""
      <div class="grid grid-cols-2 gap-1">
        <div>Avialable (search)</div>

        <div>Selected</div>

        <!-- Change to accept {id, name} here -->
        <div class="border-solid border rounded-md border-grey dark:border-white max-h-60 overflow-auto p-2">
          <div :for={{id, name} <- @available} phx-click="add" phx-target={@myself} phx-value-list-id={@fieldname} phx-value-item={id}>
            <%= name %>
          </div>
        </div>

        <div class="border-solid border rounded-md border-grey dark:border-white max-h-60 overflow-auto p-2">
          <div :for={{id, item, conf} <- @selected_items} phx-click="remove" phx-target={@myself} phx-value-list-id={@fieldname} phx-value-item={id}>
            <%= render_slot(@item_form, {id, item, conf}) %>
            <button phx-click="move" phx-target={@myself} phx-value-list-id={@fieldname} phx-value-item={id} phx-value-direction="up">^</button>
            <button phx-click="move" phx-target={@myself} phx-value-list-id={@fieldname} phx-value-item={id} phx-value-direction="down">v</button>
          </div>
        </div>
      </div>
    """
  end

  def handle_event("remove", params, socket) do
    send(self(), {:list_picker_remove, params["list-id"], params["item"]})
    {:noreply, socket}
  end

  def handle_event("add", params, socket) do
    send(self(), {:list_picker_add, params["list-id"], params["item"]})
    {:noreply, socket}
  end

  def handle_event("move", params, socket) do
    send(self(), {:list_picker_move, params["list-id"], params["item"], params["direction"]})
    {:noreply, socket}
  end

end
