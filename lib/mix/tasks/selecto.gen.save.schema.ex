defmodule Mix.Tasks.Selecto.Gen.Save.Schema do
  @moduledoc "The hello mix task: `mix help hello`"
  use Mix.Task

  @doc """
  params:
    tablename
    modulename
    contextfield1:type contextfield2:type ...

  """

  # mix selecto.gen.save.schema SavedView saved_view

  # .repo
  # .module
  # .schema
  # .talename

  ### Generate schema file priv/templates/save.schema.ex
  ### Generate context file priv/templates/save.context.ex

  @shortdoc "Generate Schema to save Selecto Views."
  def run(args) do
    # calling our Hello.say() function from earlier

    schema = build(args)
    IO.inspect(schema)



  end

  defp build(args) do
    {_parsed, [modname, plural_mod, tabname, repo] = _rest} = OptionParser.parse!(args, [])
    %{
        modname: modname,
        plural_mod: plural_mod,
        tablename: tabname,
        repo: repo
    }
  end


end
