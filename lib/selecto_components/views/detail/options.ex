defmodule SelectoComponents.Views.Detail.Options do
  @moduledoc false

  @max_rows_options ~w(100 1000 10000 all)
  @default_max_rows "1000"
  @default_max_per_page 1_000
  @default_max_rows_cap 100_000
  @count_mode_options ~w(exact bounded none)
  @default_count_mode "bounded"

  def max_rows_options, do: @max_rows_options
  def default_max_rows, do: @default_max_rows
  def count_mode_options, do: @count_mode_options
  def default_count_mode, do: @default_count_mode

  @doc """
  Largest detail page size a request may ask for.

  Configure with `config :selecto_components, :detail_max_per_page, 1_000`.
  """
  def max_per_page, do: positive_config(:detail_max_per_page, @default_max_per_page)

  @doc """
  Largest number of detail rows a query may reach, including `max_rows: "all"`.

  Configure with `config :selecto_components, :detail_max_rows_cap, 100_000`.
  """
  def max_rows_cap, do: positive_config(:detail_max_rows_cap, @default_max_rows_cap)

  def cap_per_page(per_page) when is_integer(per_page),
    do: per_page |> max(1) |> min(max_per_page())

  def cap_per_page(_per_page), do: min(30, max_per_page())

  def normalize_max_rows_param(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in @max_rows_options do
      normalized
    else
      @default_max_rows
    end
  end

  def normalize_max_rows_param(value) when is_integer(value),
    do: normalize_max_rows_param(Integer.to_string(value))

  def normalize_max_rows_param(value) when is_atom(value),
    do: normalize_max_rows_param(Atom.to_string(value))

  def normalize_max_rows_param(_value), do: @default_max_rows

  def normalize_count_mode_param(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in @count_mode_options do
      normalized
    else
      @default_count_mode
    end
  end

  def normalize_count_mode_param(value) when is_atom(value),
    do: normalize_count_mode_param(Atom.to_string(value))

  def normalize_count_mode_param(_value), do: @default_count_mode

  def normalize_row_click_action_param(nil), do: ""

  def normalize_row_click_action_param(value) when is_binary(value) do
    value
    |> String.trim()
  end

  def normalize_row_click_action_param(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_row_click_action_param()

  def normalize_row_click_action_param(value) when is_integer(value), do: Integer.to_string(value)
  def normalize_row_click_action_param(_value), do: ""

  def normalize_max_rows_limit(value) do
    case normalize_max_rows_param(value) do
      "all" ->
        max_rows_cap()

      normalized ->
        case Integer.parse(normalized) do
          {limit, ""} when limit > 0 -> min(limit, max_rows_cap())
          _ -> min(String.to_integer(@default_max_rows), max_rows_cap())
        end
    end
  end

  def detail_view_mode?(params) when is_map(params) do
    case Map.get(params, :view_mode, Map.get(params, "view_mode")) do
      :detail -> true
      "detail" -> true
      mode when is_atom(mode) -> Atom.to_string(mode) == "detail"
      _ -> false
    end
  end

  def detail_view_mode?(_params), do: false

  defp positive_config(key, default) do
    case Application.get_env(:selecto_components, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end
end
