defmodule SelectoComponents.Views.Document do
  @moduledoc """
  Document view for Selecto Components.

  This view mode renders one formatted document per returned detail row.
  """

  use SelectoComponents.Views.System,
    process: SelectoComponents.Views.Document.Process,
    form: SelectoComponents.Views.Document.Form,
    component: SelectoComponents.Views.Document.Component
end
