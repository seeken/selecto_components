defmodule SelectoComponents.Views.Document.Form do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <div class="rounded-md border border-gray-200 bg-gray-50 p-3 text-sm text-gray-700">
      Document template configuration will be available in this view mode.
    </div>
    """
  end
end
