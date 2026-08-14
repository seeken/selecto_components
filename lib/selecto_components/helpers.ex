defmodule SelectoComponents.Helpers do
  def text_search_mode_options(adapter) do
    adapter
    |> Selecto.AdapterSupport.capability(:text_search)
    |> Map.get(:modes, [])
    |> Enum.map(fn mode -> {to_string(mode), text_search_mode_label(mode)} end)
  end

  def default_text_search_mode(adapter) do
    adapter
    |> Selecto.AdapterSupport.capability(:text_search)
    |> Map.get(:default_mode, :websearch)
    |> to_string()
  end

  def text_search_help_text(adapter) do
    adapter
    |> Selecto.AdapterSupport.capability(:text_search)
    |> Map.get(
      :help,
      "Text search behavior is adapter-specific. Supported modes depend on the active database adapter."
    )
  end

  defp text_search_mode_label(:natural), do: "Natural Language"
  defp text_search_mode_label(:websearch), do: "Web Style"
  defp text_search_mode_label(:plain), do: "Plain Tokens"
  defp text_search_mode_label(:boolean), do: "Boolean"
  defp text_search_mode_label(:phrase), do: "Phrase"
  defp text_search_mode_label(:query_expansion), do: "Query Expansion"

  defp text_search_mode_label(mode) do
    mode
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  def datetime_grouping_format_options() do
    [
      {"YYYY-MM-DD", "Day"},
      {"YYYY-MM-DD HH24", "Day + Hour"},
      {"YYYY-WW", "Week"},
      {"YYYY-MM", "Month"},
      {"YYYY-Q", "Quarter"},
      {"YYYY", "Year"},
      {"year_buckets", "Year Buckets"},
      {"MM", "Month of Year"},
      {"DD", "Day of Month"},
      {"D", "Day of Week"},
      {"HH24", "Hour of Day"},
      {"age_buckets", "Age Buckets"},
      {"custom_buckets", "Custom Date Buckets"}
    ]
  end

  def aggregate_datetime_format_options, do: datetime_grouping_format_options()

  def date_formats() do
    %{
      "YYYY-MM-DD" => "YYYY-MM-DD",
      "YYYY-MM-DD HH24" => "YYYY-MM-DD HH24",
      "YYYY-WW" => "YYYY-WW",
      "YYYY-MM" => "YYYY-MM",
      "YYYY-Q" => "YYYY-Q",
      "YYYY" => "YYYY",
      "MM" => "MM",
      "DD" => "DD",
      "D" => "D",
      "HH24" => "HH24",
      "MM-DD-YYYY HH:MM" => "MM-DD-YYYY HH:MM",
      "YYYY-MM-DD HH:MM" => "YYYY-MM-DD HH:MM"
    }
  end

  def datetime_grouping_format_label(format) when is_atom(format) do
    format
    |> Atom.to_string()
    |> datetime_grouping_format_label()
  end

  def datetime_grouping_format_label(format) when is_binary(format) do
    Enum.find_value(datetime_grouping_format_options(), format, fn
      {^format, label} -> label
      _ -> nil
    end)
  end

  def aggregate_datetime_format_label(format) do
    datetime_grouping_format_label(format) || to_string(format)
  end

  def datetime_bucket_placeholder("age_buckets"), do: "e.g., 0, 1-7, 8-30, 31-90, 91+"
  def datetime_bucket_placeholder("year_buckets"), do: "e.g., */5 or 2020-2024, 2025-2029"
  def datetime_bucket_placeholder(_), do: "e.g., today, yesterday, 2-7, 8+"

  def build_initial_state(list) do
    list
    |> Enum.map(fn
      i when is_bitstring(i) -> {UUID.uuid4(), i, %{}}
      {i, conf} -> {UUID.uuid4(), i, conf}
    end)
  end
end
