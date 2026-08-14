defmodule SelectoComponents.Helpers.BucketParser do
  @moduledoc """
  Parser for bucket range specifications like "1, 2-5, 6-14, 15+"
  and numeric increment shorthand like "*/10"
  """

  @numeric_bucket_types [:int, :integer, :id, :decimal, :float]
  @default_prefix_length 2
  @max_prefix_length 10
  @common_articles ~w(a an the)

  def parse_bucket_ranges(ranges_string) when is_binary(ranges_string) do
    ranges_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_single_range/1)
    |> Enum.reject(&is_nil/1)
  end

  def parse_bucket_ranges(_), do: []

  defp parse_single_range(range) do
    cond do
      # Single value like "1"
      String.match?(range, ~r/^\d+$/) ->
        val = String.to_integer(range)
        {val, val, "#{val}"}

      # Range like "2-5"
      String.match?(range, ~r/^\d+-\d+$/) ->
        [min_str, max_str] = String.split(range, "-")
        min = String.to_integer(min_str)
        max = String.to_integer(max_str)
        {min, max, "#{min}-#{max}"}

      # Open-ended range like "15+"
      String.match?(range, ~r/^\d+\+$/) ->
        min = range |> String.replace("+", "") |> String.to_integer()
        {min, :infinity, "#{min}+"}

      # Open-ended range like "-5" (up to 5)
      String.match?(range, ~r/^-\d+$/) ->
        max = range |> String.replace("-", "") |> String.to_integer()
        {:negative_infinity, max, "≤#{max}"}

      # Special keywords for date buckets
      range in ["today", "yesterday", "tomorrow"] ->
        {range, range, range}

      true ->
        nil
    end
  end

  @doc """
  Build portable bucket intent for a Selecto field.
  """
  def bucket_selector(field, bucket_ranges, field_type \\ :integer, opts \\ %{}) do
    increment = parse_increment_shorthand(bucket_ranges)

    if (field_type in @numeric_bucket_types or field_type == :year) and is_integer(increment) do
      {:bucket, field,
       %{
         kind: if(field_type == :year, do: :year_increment, else: :numeric_increment),
         increment: increment,
         temporal_options: Map.get(opts, :temporal_options, %{})
       }}
    else
      ranges = parse_bucket_ranges(bucket_ranges)

      if Enum.empty?(ranges) do
        field
      else
        {:bucket, field,
         %{
           kind: bucket_kind(field_type),
           ranges: ranges,
           temporal_options: Map.get(opts, :temporal_options, %{})
         }}
      end
    end
  end

  @doc """
  Build portable text-prefix bucket intent.

  Example buckets with default options:

  - "The Office" -> "OF"
  - "A Team" -> "TE"
  - nil/blank/article-only -> "Other"
  """
  def text_prefix_selector(field, opts \\ %{}) do
    prefix_length =
      parse_prefix_length(
        Map.get(opts, :prefix_length) || Map.get(opts, "prefix_length"),
        @default_prefix_length
      )

    {:bucket, field,
     %{
       kind: :text_prefix,
       prefix_length: prefix_length,
       exclude_articles: normalized_articles(opts),
       ignore_case:
         ignore_case?(Map.get(opts, :ignore_case) || Map.get(opts, "ignore_case"), true)
     }}
  end

  @doc """
  Build portable normalized-text selector intent for filtering.
  """
  def normalized_text_selector(field, opts \\ %{}) do
    {:text_normalize, field,
     %{
       exclude_articles: normalized_articles(opts),
       ignore_case:
         ignore_case?(Map.get(opts, :ignore_case) || Map.get(opts, "ignore_case"), true)
     }}
  end

  def parse_prefix_length(value, default \\ @default_prefix_length)

  def parse_prefix_length(value, _default) when is_integer(value) and value > 0 do
    min(value, @max_prefix_length)
  end

  def parse_prefix_length(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> min(parsed, @max_prefix_length)
      _ -> default
    end
  end

  def parse_prefix_length(_value, default), do: default

  def exclude_articles?(value, default \\ true)

  def exclude_articles?(nil, default), do: default

  def exclude_articles?(value, _default) when value in [true, "true", "TRUE", "on", "1", 1],
    do: true

  def exclude_articles?(value, _default) when value in [false, "false", "FALSE", "off", "0", 0],
    do: false

  def exclude_articles?(_value, default), do: default

  def ignore_case?(value, default \\ true)

  def ignore_case?(nil, default), do: default

  def ignore_case?(value, _default) when value in [true, "true", "TRUE", "on", "1", 1],
    do: true

  def ignore_case?(value, _default) when value in [false, "false", "FALSE", "off", "0", 0],
    do: false

  def ignore_case?(_value, default), do: default

  defp parse_increment_shorthand(ranges_string) when is_binary(ranges_string) do
    trimmed = String.trim(ranges_string)

    case Regex.run(~r{^\*/(\d+)$}, trimmed, capture: :all_but_first) do
      [step_str] ->
        case Integer.parse(step_str) do
          {step, ""} when step > 0 -> step
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_increment_shorthand(_), do: nil

  defp bucket_kind(type) when type in [:date, :datetime], do: :date_relative_ranges
  defp bucket_kind(:elapsed_days), do: :elapsed_days_ranges
  defp bucket_kind(:year), do: :year_ranges
  defp bucket_kind(_type), do: :numeric_ranges

  defp normalized_articles(opts) do
    if exclude_articles?(
         Map.get(opts, :exclude_articles) || Map.get(opts, "exclude_articles"),
         true
       ) do
      @common_articles
    else
      []
    end
  end

  @doc """
  Get bucket labels in order for column headers
  """
  def get_bucket_labels(bucket_ranges) do
    ranges = parse_bucket_ranges(bucket_ranges)
    Enum.map(ranges, fn {_, _, label} -> label end) ++ ["Other"]
  end

  @doc """
  Generate filter for a specific bucket
  """
  def generate_bucket_filter(_field_name, bucket_label, bucket_ranges) do
    ranges = parse_bucket_ranges(bucket_ranges)

    case Enum.find(ranges, fn {_, _, label} -> label == bucket_label end) do
      {min, max, _} when is_integer(min) and is_integer(max) ->
        if min == max do
          %{"comp" => "=", "value" => min}
        else
          %{"comp" => "BETWEEN", "value" => "#{min},#{max}"}
        end

      {min, :infinity, _} ->
        %{"comp" => ">=", "value" => min}

      {:negative_infinity, max, _} ->
        %{"comp" => "<=", "value" => max}

      {"today", "today", _} ->
        %{"comp" => "SHORTCUT", "value" => "today"}

      {"yesterday", "yesterday", _} ->
        %{"comp" => "SHORTCUT", "value" => "yesterday"}

      {"tomorrow", "tomorrow", _} ->
        %{"comp" => "SHORTCUT", "value" => "tomorrow"}

      _ ->
        nil
    end
  end
end
