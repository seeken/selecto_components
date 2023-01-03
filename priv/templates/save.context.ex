defmodule <%= inspect savecontext.module %> do


  @behaviour SelectoComponents.SavedViews

  ### TODO - fix agg filter appluy for film ratings
  import Ecto.Query

  def get_view(name, context) do
    q = from v in <%= inspect savecontext.schema %>,
      where: ^context == v.context,
      where:  ^name == v.name
    <%= inspect savecontext.repo %>.one( q )
  end

  def save_view(name, context, params) do
    case get_view(name, context) do
      nil -> <%= inspect savecontext.repo %>.insert!(%<%= inspect savecontext.schema %>{name: name, context: context, params: params})
      view -> update_view(view, params)
    end
  end

  def update_view(view, params) do
    {:ok, view} = <%= inspect savecontext.schema %>.changeset(view, %{params: params})
      |> <%= inspect savecontext.repo %>.update()
    view
  end

  def get_view_names(context) do
    q = from v in <%= inspect savecontext.schema %>,
      select: v.name,
      where: ^context == v.context

    <%= inspect savecontext.repo %>.all( q )
  end

  def decode_view(view) do
    ### give params to use for view
    view.params
  end

end
