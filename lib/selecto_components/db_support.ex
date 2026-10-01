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

  @database_failure_categories [
    :database_error,
    :unique_violation,
    :foreign_key_violation,
    :not_null_violation,
    :check_violation,
    :query_canceled,
    :serialization_failure,
    :deadlock_detected
  ]
  @database_failure_detail_keys [:constraint, :column, :table, :sqlstate]

  @doc false
  # A failure the database reported. Its message and details can name
  # constraints, columns and values, so user-facing text comes only from
  # `format_database_error/1`.
  def database_failure?(%Selecto.Error{type: :constraint_error}), do: true

  def database_failure?(%Selecto.Error{details: details}) when is_map(details) do
    Map.get(details, :category) in @database_failure_categories or
      Enum.any?(@database_failure_detail_keys, &Map.has_key?(details, &1))
  end

  def database_failure?(_error), do: false

  # A fixed sentence per failure kind. Constraint, column and table names and
  # the database's own message are never rendered to users.
  def format_database_error(%Selecto.Error{} = error) do
    case {error.type, database_error_details(error)[:category]} do
      {_type, :unique_violation} ->
        "A record with the same unique value already exists."

      {_type, :foreign_key_violation} ->
        "The change refers to a related record that is missing or still in use."

      {_type, :not_null_violation} ->
        "A required value is missing."

      {_type, :check_violation} ->
        "A value is not allowed by a database rule."

      {_type, :query_canceled} ->
        "The database canceled the query."

      {_type, category} when category in [:serialization_failure, :deadlock_detected] ->
        "The database could not complete the query because of a concurrent change. Try again."

      {:connection_error, _category} ->
        "The database connection failed."

      {:timeout_error, _category} ->
        "The database query timed out."

      _type_and_category ->
        "The database could not complete the query."
    end
  end

  def format_database_error(_error), do: "The database could not complete the query."

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
            {:error, driver_error(adapter, reason)}
        end

      {:error, reason} ->
        {:error, driver_error(adapter, reason)}
    end
  rescue
    error ->
      {:error,
       Selecto.Error.connection_error("Adapter raw execution failed", %{
         adapter: adapter,
         reason: Selecto.Error.reason_kind(error)
       })}
  catch
    :exit, reason ->
      {:error,
       Selecto.Error.connection_error(
         "Adapter raw connection failed",
         Map.put(Selecto.Error.exit_details(reason), :adapter, adapter)
       )}
  end

  # Matches Selecto's own execution path: the result never carries SQL,
  # parameters, the connection, or the database's message and detail.
  defp driver_error(adapter, reason),
    do: Selecto.Error.from_driver(reason, Selecto.AdapterSupport.normalize_error(adapter, reason))
end
