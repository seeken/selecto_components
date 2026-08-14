defmodule SelectoComponents.Debug.DebugDisplayTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Debug.DebugDisplay

  test "debug details are hidden by default" do
    {:ok, socket} = DebugDisplay.mount(%Phoenix.LiveView.Socket{})

    assert socket.assigns.expanded == false
  end

  test "toggle_debug_details flips the expanded state" do
    {:ok, socket} = DebugDisplay.mount(%Phoenix.LiveView.Socket{})

    {:noreply, socket} = DebugDisplay.handle_event("toggle_debug_details", %{}, socket)

    assert socket.assigns.expanded == true
  end

  test "debug state does not offer dialect-specific SQL interpolation" do
    {:ok, socket} = DebugDisplay.mount(%Phoenix.LiveView.Socket{})

    refute Map.has_key?(socket.assigns, :show_interpolated)
  end
end
