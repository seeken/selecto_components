defmodule SelectoComponents.Helpers.BucketParserTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Helpers.BucketParser

  describe "bucket_selector/4" do
    test "does not treat */step as a date bucket format" do
      assert BucketParser.bucket_selector(:inserted_at, "*/10", :date) == :inserted_at
    end

    test "maps custom date buckets to portable relative-date intent" do
      assert {:bucket, :inserted_at,
              %{
                kind: :date_relative_ranges,
                ranges: [
                  {"today", "today", "today"},
                  {"yesterday", "yesterday", "yesterday"},
                  {2, 7, "2-7"},
                  {8, :infinity, "8+"}
                ],
                temporal_options: %{}
              }} =
               BucketParser.bucket_selector(
                 :inserted_at,
                 "today, yesterday, 2-7, 8+",
                 :date
               )
    end

    test "maps year increments to portable year-bucket intent" do
      assert {:bucket, :inserted_at,
              %{
                kind: :year_increment,
                increment: 5,
                temporal_options: %{timezone: "America/Denver"}
              }} =
               BucketParser.bucket_selector(:inserted_at, "*/5", :year, %{
                 temporal_options: %{timezone: "America/Denver"}
               })
    end

    test "rejects invalid increment shorthand values" do
      assert BucketParser.bucket_selector(:price, "*/0", :integer) == :price
      assert BucketParser.bucket_selector(:price, "*/-5", :integer) == :price
    end
  end

  describe "option parsing" do
    test "exposes year bucket datetime option label" do
      assert {"year_buckets", "Year Buckets"} in SelectoComponents.Helpers.datetime_grouping_format_options()
      assert SelectoComponents.Helpers.datetime_bucket_placeholder("year_buckets") =~ "*/5"
    end

    test "parses and clamps prefix length" do
      assert BucketParser.parse_prefix_length("2") == 2
      assert BucketParser.parse_prefix_length(4) == 4
      assert BucketParser.parse_prefix_length("99") == 10
      assert BucketParser.parse_prefix_length("0", 2) == 2
      assert BucketParser.parse_prefix_length("bad", 2) == 2
    end

    test "parses exclude_articles option" do
      assert BucketParser.exclude_articles?("true")
      assert BucketParser.exclude_articles?("on")
      refute BucketParser.exclude_articles?("false")
      refute BucketParser.exclude_articles?("0")
      assert BucketParser.exclude_articles?(nil, true)
      refute BucketParser.exclude_articles?(nil, false)
    end
  end
end
