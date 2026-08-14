defmodule SelectoComponents.DBSupport do
  @moduledoc false

  alias Selecto.Executor

  def adapter(selecto) when is_map(selecto) do
    Selecto.Runtime.Context.adapter(selecto)
  end

  def supports_feature?(selecto, feature) when is_atom(feature) do
    Selecto.AdapterSupport.supports_feature?(adapter(selecto), feature)
  end

  def bounded_count_uses_top?(selecto) do
    supports_feature?(selecto, :bounded_count_top) or adapter_name(selecto) == :mssql
  end

  def requires_derived_table_column_aliases?(selecto) do
    supports_feature?(selecto, :derived_table_column_aliases) or adapter_name(selecto) == :mssql
  end

  def execute_raw_query(selecto, query, params, aliases \\ []) do
    current_adapter = adapter(selecto)
    connection = Selecto.Runtime.Context.connection(selecto)

    cond do
      Selecto.AdapterSupport.callback_available?(current_adapter, :execute_raw, 3) ->
        execute_with_adapter_raw(current_adapter, connection, query, params, aliases)

      Selecto.AdapterSupport.callback_available?(current_adapter, :execute, 4) ->
        Executor.execute_with_adapter(current_adapter, connection, query, params, aliases)

      true ->
        {:error,
         Selecto.Error.configuration_error("Configured adapter cannot execute queries", %{
           adapter: current_adapter
         })}
    end
  end

  def database_error?(%Selecto.Error{type: type})
      when type in [:connection_error, :query_error, :constraint_error],
      do: true

  def database_error?(_error), do: false

  def database_error_details(%Selecto.Error{} = error), do: error.details || %{}
  def database_error_details(_error), do: nil

  def database_error_recoverable?(%Selecto.Error{details: details}) when is_map(details),
    do: Map.get(details, :recoverable?, false)

  def database_error_recoverable?(_error), do: false

  def format_database_error(%Selecto.Error{} = error) do
    details = database_error_details(error)

    case {details[:category], details[:constraint], details[:column]} do
      {:unique_violation, constraint, _column} when is_binary(constraint) ->
        "Duplicate value violates uniqueness constraint: #{constraint}"

      {:foreign_key_violation, constraint, _column} when is_binary(constraint) ->
        "Foreign key constraint violation: #{constraint}"

      {:not_null_violation, _constraint, column} when is_binary(column) ->
        "Required field '#{column}' cannot be empty"

      _category_and_fields ->
        if is_binary(error.message),
          do: "Database error: #{error.message}",
          else: "Database error"
    end
  end

  def format_database_error(_error), do: "Database error"

  defp adapter_name(selecto) do
    selecto
    |> adapter()
    |> Selecto.AdapterSupport.adapter_name()
  end

  defp execute_with_adapter_raw(adapter, connection, query, params, aliases) do
    case adapter.execute_raw(connection, query, params) do
      {:ok, result} ->
        case Selecto.AdapterSupport.normalize_result(adapter, result) do
          {:ok, normalized} ->
            {:ok, {Map.get(normalized, :rows, []), Map.get(normalized, :columns, []), aliases}}

          {:error, reason} ->
            {:error, Selecto.AdapterSupport.normalize_error(adapter, reason)}
        end

      {:error, %Selecto.Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, Selecto.AdapterSupport.normalize_error(adapter, reason)}
    end
  rescue
    error ->
      {:error,
       Selecto.Error.connection_error("Adapter raw execution failed", %{
         adapter: adapter,
         connection: inspect(connection),
         error: inspect(error)
       })}
  catch
    :exit, reason ->
      {:error,
       Selecto.Error.connection_error("Adapter raw connection failed", %{
         adapter: adapter,
         exit_reason: reason
       })}
  end
end
