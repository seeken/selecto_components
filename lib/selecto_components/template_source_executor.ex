defmodule SelectoComponents.TemplateSourceExecutor do
  @moduledoc """
  Executes a template source through fresh authority supplied by the host.

  The compiled manifest may describe query intent, but it cannot provide a
  connection, tenant, actor, or authorization scope. The host authorization
  callback is invoked for every effect and must return an already scoped
  `%Selecto{}`. Lowering can only add the compiled source constraints.
  """

  @type authorize :: (map(), map() -> {:ok, Selecto.t()} | {:error, term()})

  @spec execute(map(), map(), authorize(), keyword()) :: {:ok, [map()]} | {:error, map()}
  def execute(manifest, effect, authorize, opts \\ [])

  def execute(%{"sources" => sources}, effect, authorize, opts)
      when is_list(sources) and is_map(effect) and is_function(authorize, 2) and is_list(opts) do
    with :ok <- valid_effect(effect),
         {:ok, source} <- find_source(sources, effect["source"]),
         {:ok, authorized} <- authorize(source, effect, authorize),
         {:ok, lowered} <-
           SelectoTemplates.lower_query(source, authorized, effect["bindings"]),
         {:ok, rows} <- execute_query(lowered.query, opts),
         {:ok, projected} <- project(lowered.result_shape, rows) do
      {:ok, projected}
    end
  rescue
    _exception ->
      {:error, diagnostic("source_execution_failed", "template source execution failed")}
  catch
    _kind, _reason ->
      {:error, diagnostic("source_execution_failed", "template source execution failed")}
  end

  def execute(_manifest, _effect, _authorize, _opts),
    do: {:error, diagnostic("invalid_source_effect", "template source effect is invalid")}

  defp valid_effect(%{
         "schema" => "selecto.template.runtime-effect.v1",
         "kind" => "load_source",
         "effect_id" => effect_id,
         "source" => source,
         "generation" => generation,
         "bindings" => %{"input" => inputs, "state" => state}
       })
       when is_binary(effect_id) and effect_id != "" and is_binary(source) and source != "" and
              is_integer(generation) and generation > 0 and is_map(inputs) and is_map(state),
       do: :ok

  defp valid_effect(_effect),
    do: {:error, diagnostic("invalid_source_effect", "template source effect is invalid")}

  defp find_source(sources, source_id) do
    case Enum.find(sources, &source_named?(&1, source_id)) do
      nil -> {:error, diagnostic("unknown_source", "template source is not declared")}
      source -> {:ok, source}
    end
  end

  defp source_named?(%{"id" => id}, expected), do: id == expected
  defp source_named?(_source, _expected), do: false

  defp authorize(source, effect, callback) do
    case callback.(source, effect) do
      {:ok, %Selecto{} = selecto} ->
        {:ok, selecto}

      _other ->
        {:error,
         diagnostic("source_authorization_failed", "template source authorization failed")}
    end
  end

  defp execute_query(query, opts) do
    execute = Keyword.get(opts, :execute, &Selecto.execute/2)
    execute_opts = Keyword.get(opts, :execute_options, [])

    if is_function(execute, 2) and is_list(execute_opts) do
      case execute.(query, execute_opts) do
        {:ok, {rows, _columns, _aliases}} when is_list(rows) ->
          {:ok, rows}

        _other ->
          {:error, diagnostic("source_execution_failed", "template source execution failed")}
      end
    else
      {:error, diagnostic("invalid_source_executor", "template source executor is invalid")}
    end
  end

  defp project(result_shape, rows) do
    case SelectoTemplates.project_rows(result_shape, rows) do
      {:ok, projected} ->
        {:ok, projected}

      {:error, _reason} ->
        {:error, diagnostic("invalid_source_result", "template source result is invalid")}
    end
  end

  defp diagnostic(code, message) do
    %{
      "schema" => "selecto.template.diagnostic.v1",
      "severity" => "error",
      "code" => code,
      "message" => message,
      "path" => []
    }
  end
end
