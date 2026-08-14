defmodule SelectoComponents.TestAdapter do
  @moduledoc false
  @behaviour Selecto.DB.Adapter

  @impl true
  def name, do: :test

  @impl true
  def connect(connection), do: {:ok, connection}

  @impl true
  def execute(_connection, _query, _params, _opts),
    do: {:ok, %{rows: [], columns: []}}

  @impl true
  def execute_raw(_connection, _query, _params),
    do: {:ok, %{rows: [], columns: []}}

  @impl true
  def placeholder(index), do: ["$", Integer.to_string(index)]

  @impl true
  def quote_identifier(identifier) do
    escaped = identifier |> to_string() |> String.replace("\"", "\"\"")
    "\"#{escaped}\""
  end

  @impl true
  def supports?(feature) do
    feature in [
      :cte,
      :jsonb,
      :array_ops,
      :array_any_comparison,
      :native_null_ordering,
      :rollup,
      :returning,
      :text_search,
      :window_functions,
      :lateral_join,
      :prefix
    ]
  end

  @impl true
  def capability(:text_search) do
    %{
      feature: :text_search,
      supported?: true,
      modes: [:websearch, :plain, :phrase, :boolean, :natural],
      default_mode: :websearch,
      help: "Portable text search test capability."
    }
  end

  def capability(feature), do: %{feature: feature, supported?: supports?(feature)}

  @impl true
  def type_family(:tsvector), do: :text_search
  def type_family(:jsonb), do: :json
  def type_family(type), do: Selecto.TypeFamily.of(type)
end

Application.put_env(:selecto, :default_adapter, SelectoComponents.TestAdapter)

ExUnit.start()
