defmodule ListableComponentsPetal.Components.TreeBuilder do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
      <div>
        <div phx-hook="PushEventHook" id="relay">

          <div> Fitler tree builder</div>
          <div> List Of Filters
            <div draggable="true"
            x-on:drag="dragging = event.srcElement.id"
            id="DRAG">Drag me</div>
          </div>
          <div> Build Area
            <div x-on:drop="
              source = event.srcElement.id;
              tar = event.target.id;
              console.log(`${dragging} -> ${tar}`)
              console.log(event)
              PushEventHook.pushEvent('treedrop', {target: tar, element: dragging})
            " id="TAR">HERE</div>
          </div>
        </div>
      </div>
    """
  end



end
