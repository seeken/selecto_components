defmodule SelectoComponents.Views.Document.Component do
  use Phoenix.LiveComponent

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-gray-200 bg-white p-4">
      <%= cond do %>
        <% assigns[:execution_error] -> %>
          <div class="text-sm text-red-700">{inspect(assigns.execution_error)}</div>
        <% assigns[:executed] == false -> %>
          <div class="text-sm text-blue-600 italic">Loading documents...</div>
        <% true -> %>
          <div class="text-sm text-gray-600">No document template configured yet.</div>
      <% end %>
    </div>
    """
  end
end
