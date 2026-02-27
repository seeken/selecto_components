defmodule SelectoComponents.Views.Document.Options do
  @moduledoc false

  @per_page_options [10, 20, 30, 50, 100]
  @default_per_page "30"

  @max_rows_options ~w(100 1000 10000 all)
  @default_max_rows "1000"

  def per_page_options, do: @per_page_options
  def default_per_page, do: @default_per_page

  def max_rows_options, do: @max_rows_options
  def default_max_rows, do: @default_max_rows

  def normalize_per_page_param(value) when is_binary(value) do
    normalized = String.trim(value)
    allowed = Enum.map(@per_page_options, &Integer.to_string/1)

    if normalized in allowed do
      normalized
    else
      @default_per_page
    end
  end

  def normalize_per_page_param(value) when is_integer(value) and value > 0,
    do: normalize_per_page_param(Integer.to_string(value))

  def normalize_per_page_param(_value), do: @default_per_page

  def per_page_to_int(value, fallback \\ 30)

  def per_page_to_int(value, _fallback) when is_integer(value) and value > 0, do: value

  def per_page_to_int(value, fallback) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  def per_page_to_int(_value, fallback), do: fallback

  def normalize_max_rows_param(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if normalized in @max_rows_options do
      normalized
    else
      @default_max_rows
    end
  end

  def normalize_max_rows_param(value) when is_integer(value) and value > 0,
    do: normalize_max_rows_param(Integer.to_string(value))

  def normalize_max_rows_param(_value), do: @default_max_rows

  def normalize_max_rows_limit(value) do
    case normalize_max_rows_param(value) do
      "all" ->
        nil

      normalized ->
        case Integer.parse(normalized) do
          {limit, ""} when limit > 0 -> limit
          _ -> String.to_integer(@default_max_rows)
        end
    end
  end

  def document_view_mode?(params) when is_map(params) do
    case Map.get(params, :view_mode, Map.get(params, "view_mode")) do
      :document -> true
      "document" -> true
      mode when is_atom(mode) -> Atom.to_string(mode) == "document"
      _ -> false
    end
  end

  def document_view_mode?(_params), do: false
end
