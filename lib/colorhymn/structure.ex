defmodule Colorhymn.Structure do
  @moduledoc """
  Structural analysis of log content.

  Parses log content into semantic regions within lines and groups across lines.
  This module provides the bridge between raw tokenization and higher-level
  understanding of log structure.

  ## Regions (within a line)

  Each line is divided into semantic regions:
  - `:timestamp` - Date/time at line start
  - `:log_level` - Severity indicator (ERROR, WARN, etc.)
  - `:component` - Module/service name in brackets [db-pool]
  - `:key_value` - key=value or key:value pairs
  - `:bracket` - Other bracketed content
  - `:message` - Everything after structured parts

  ## Groups (across lines)

  Related lines are grouped for collective analysis:
  - `:single` - Standalone line (no grouping)
  - `:continuation` - Indented/prefixed follow-on lines
  - `:table` - Columnar data, routing tables
  - `:stack_trace` - Exception + stack frames

  ## Example

      lines = ["2024-01-15 10:30:45 [ERROR] Database connection failed",
               "  at db_pool:connect/2 (db_pool.ex:45)",
               "  at app:start/1 (app.ex:12)"]

      groups = Structure.analyze(lines)
      # Returns one :stack_trace group containing all 3 lines
  """

  alias Colorhymn.Structure.{Group, RegionDetector, GroupDetector}

  # ============================================================================
  # Main API
  # ============================================================================

  @doc """
  Analyze log content and return structured groups.

  Accepts either a single string (split by newlines) or a list of lines.
  Returns a list of Group structs, each containing its lines and regions.
  """
  def analyze(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> analyze()
  end

  def analyze(lines) when is_list(lines) do
    GroupDetector.detect(lines)
  end

  @doc """
  Analyze a single line and return its regions.

  This is a convenience function for single-line analysis when you
  don't need group detection.
  """
  def analyze_line(line) when is_binary(line) do
    RegionDetector.detect(line)
  end

  @doc """
  Analyze a single line with pre-computed tokens.

  Use this when you already have tokenizer output to avoid re-tokenizing.
  """
  def analyze_line(line, tokens) when is_binary(line) and is_list(tokens) do
    RegionDetector.detect(line, tokens)
  end

  # ============================================================================
  # Region Queries
  # ============================================================================

  @doc """
  Find a specific region type in a list of regions.
  """
  def find_region(regions, type) when is_list(regions) and is_atom(type) do
    Enum.find(regions, &(&1.type == type))
  end

  @doc """
  Find all regions of a specific type.
  """
  def filter_regions(regions, type) when is_list(regions) and is_atom(type) do
    Enum.filter(regions, &(&1.type == type))
  end

  @doc """
  Check if a line has a specific region type.
  """
  def has_region?(regions, type) when is_list(regions) and is_atom(type) do
    Enum.any?(regions, &(&1.type == type))
  end

  @doc """
  Get the log level from regions if present.
  Returns the level atom (:error, :warning, :info, etc.) or nil.
  """
  def get_log_level(regions) when is_list(regions) do
    case find_region(regions, :log_level) do
      nil -> nil
      region -> Map.get(region.metadata, :level)
    end
  end

  @doc """
  Get all key-value pairs from regions.
  Returns a map of key => value.
  """
  def get_key_values(regions) when is_list(regions) do
    regions
    |> filter_regions(:key_value)
    |> Enum.map(fn r -> {r.metadata.key, r.metadata.value} end)
    |> Map.new()
  end

  @doc """
  Get the message content from regions.
  """
  def get_message(regions) when is_list(regions) do
    case find_region(regions, :message) do
      nil -> nil
      region -> region.value
    end
  end

  @doc """
  Get the timestamp value from regions.
  """
  def get_timestamp(regions) when is_list(regions) do
    case find_region(regions, :timestamp) do
      nil -> nil
      region -> region.value
    end
  end

  # ============================================================================
  # Group Queries
  # ============================================================================

  @doc """
  Get all regions from all lines in a group, flattened.
  """
  def all_regions(%Group{regions: regions_list}) do
    List.flatten(regions_list)
  end

  @doc """
  Check if any line in a group has a specific log level.
  """
  def group_has_level?(%Group{} = group, level) when is_atom(level) do
    group
    |> all_regions()
    |> filter_regions(:log_level)
    |> Enum.any?(fn r -> Map.get(r.metadata, :level) == level end)
  end

  @doc """
  Get the highest severity log level in a group.
  Returns the most severe level found, or nil.
  """
  def highest_severity(%Group{} = group) do
    levels =
      group
      |> all_regions()
      |> filter_regions(:log_level)
      |> Enum.map(fn r -> Map.get(r.metadata, :level) end)
      |> Enum.reject(&is_nil/1)

    case levels do
      [] -> nil
      levels -> Enum.min_by(levels, &severity_rank/1)
    end
  end

  defp severity_rank(:fatal), do: 1
  defp severity_rank(:critical), do: 2
  defp severity_rank(:error), do: 3
  defp severity_rank(:warning), do: 4
  defp severity_rank(:info), do: 5
  defp severity_rank(:debug), do: 6
  defp severity_rank(:trace), do: 7
  defp severity_rank(_), do: 10

  # ============================================================================
  # Iteration Helpers
  # ============================================================================

  @doc """
  Iterate over groups with their line numbers.
  Yields {group, line_index} for each group.
  """
  def with_line_numbers(groups) when is_list(groups) do
    Enum.map(groups, fn group -> {group, group.start_line} end)
  end

  @doc """
  Expand groups back into individual lines with their regions.
  Returns [{line, regions, group_type, line_number}, ...]
  """
  def expand_to_lines(groups) when is_list(groups) do
    groups
    |> Enum.flat_map(fn group ->
      group.lines
      |> Enum.zip(group.regions)
      |> Enum.with_index(group.start_line)
      |> Enum.map(fn {{line, regions}, idx} ->
        {line, regions, group.type, idx}
      end)
    end)
  end

  @doc """
  Map a function over each line in each group.
  The function receives {line, regions, group, line_index}.
  """
  def map_lines(groups, fun) when is_list(groups) and is_function(fun, 1) do
    groups
    |> Enum.flat_map(fn group ->
      group.lines
      |> Enum.zip(group.regions)
      |> Enum.with_index(group.start_line)
      |> Enum.map(fn {{line, regions}, idx} ->
        fun.({line, regions, group, idx})
      end)
    end)
  end

  # ============================================================================
  # Statistics
  # ============================================================================

  @doc """
  Get statistics about the structure of analyzed content.
  """
  def stats(groups) when is_list(groups) do
    total_lines = Enum.sum(Enum.map(groups, &length(&1.lines)))

    group_type_counts =
      groups
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, gs} -> {type, length(gs)} end)
      |> Map.new()

    all_regions = Enum.flat_map(groups, &List.flatten(&1.regions))

    region_type_counts =
      all_regions
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, rs} -> {type, length(rs)} end)
      |> Map.new()

    %{
      total_lines: total_lines,
      total_groups: length(groups),
      group_types: group_type_counts,
      region_types: region_type_counts,
      multi_line_groups: Enum.count(groups, &(&1.type != :single))
    }
  end
end
