defmodule SelectoComponents.Views.Analytic.Defaults do
  @moduledoc """
  Resolves the shared query defaults used by Aggregate and Graph.

  Explicit domain-level `default_group_by` and `default_aggregate` lists remain
  authoritative. When either list is absent or empty, the resolver falls back
  to opt-in `default_grouping` and `default_aggregate` hints on source columns.
  """

  def group_by(selecto) do
    domain = Selecto.domain(selecto)

    case map_get(domain, :default_group_by, []) do
      defaults when is_list(defaults) and defaults != [] -> normalize_explicit(defaults)
      _ -> column_defaults(domain, :default_grouping, "format")
    end
  end

  def aggregate(selecto) do
    domain = Selecto.domain(selecto)

    case map_get(domain, :default_aggregate, []) do
      defaults when is_list(defaults) and defaults != [] -> normalize_explicit(defaults)
      _ -> column_defaults(domain, :default_aggregate, "format")
    end
  end

  defp column_defaults(domain, key, config_key) do
    source = map_get(domain, :source, %{})
    columns = map_get(source, :columns, %{})
    fields = map_get(source, :fields, Map.keys(columns))

    fields
    |> Enum.flat_map(fn field ->
      column = map_get(columns, field, %{})

      case map_get(column, key) do
        value when value in [nil, false, ""] -> []
        value -> [{to_string(field), default_config(value, config_key)}]
      end
    end)
  end

  defp default_config(value, config_key) when is_atom(value) or is_binary(value),
    do: %{config_key => to_string(value)}

  defp default_config(value, _config_key) when is_map(value), do: stringify_keys(value)
  defp default_config(_value, _config_key), do: %{}

  defp normalize_explicit(defaults) do
    Enum.map(defaults, fn
      field when is_atom(field) or is_binary(field) -> to_string(field)
      {field, config} when is_map(config) -> {to_string(field), stringify_keys(config)}
      other -> other
    end)
  end

  defp stringify_keys(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp map_get(map, key, default \\ nil)

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_get(_map, _key, default), do: default
end
