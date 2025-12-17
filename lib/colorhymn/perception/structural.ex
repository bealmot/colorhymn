defmodule Colorhymn.Perception.Structural do
  @moduledoc """
  Structural dimension analysis - the shape of lines and blocks.
  """

  def analyze(lines) when length(lines) < 2 do
    %{
      line_length_variance: 0.5,
      structure_consistency: 0.5,
      nesting_depth: 0.0,
      whitespace_ratio: 0.5,
      block_regularity: 0.5
    }
  end

  def analyze(lines) do
    %{
      line_length_variance: compute_length_variance(lines),
      structure_consistency: compute_structure_consistency(lines),
      nesting_depth: compute_nesting_depth(lines),
      whitespace_ratio: compute_whitespace_ratio(lines),
      block_regularity: compute_block_regularity(lines)
    }
  end

  defp compute_length_variance(lines) do
    lengths = Enum.map(lines, &String.length/1)
    mean = Enum.sum(lengths) / length(lengths)

    if mean == 0 do
      0.5
    else
      variance = Enum.sum(Enum.map(lengths, fn l -> :math.pow(l - mean, 2) end)) / length(lengths)
      cv = :math.sqrt(variance) / mean

      # CV of 0 = no variance (0.0), CV > 1 = high variance (approaching 1.0)
      clamp(cv / (1 + cv), 0.0, 1.0)
    end
  end

  defp compute_structure_consistency(lines) do
    # Check if lines follow consistent patterns
    patterns = lines
    |> Enum.map(&extract_structure_pattern/1)
    |> Enum.frequencies()

    if map_size(patterns) == 0 do
      0.5
    else
      # Most common pattern's frequency
      max_freq = patterns |> Map.values() |> Enum.max()
      dominance = max_freq / length(lines)

      # High dominance = consistent structure
      clamp(dominance, 0.0, 1.0)
    end
  end

  defp extract_structure_pattern(line) do
    # Convert line to abstract pattern
    line
    |> String.replace(~r/\d+/, "N")           # Numbers -> N
    |> String.replace(~r/[a-zA-Z]+/, "W")     # Words -> W
    |> String.replace(~r/\s+/, "_")           # Whitespace -> _
    |> String.replace(~r/[^\w_NWPS\[\]{}()=:,.\-]/, "S")  # Symbols -> S
    |> String.slice(0, 30)  # Truncate for comparison
  end

  defp compute_nesting_depth(lines) do
    depths = Enum.map(lines, &line_nesting_depth/1)

    if length(depths) == 0 do
      0.0
    else
      max_depth = Enum.max(depths)
      # Normalize: depth 0 = 0.0, depth 5+ = 1.0
      clamp(max_depth / 5, 0.0, 1.0)
    end
  end

  defp line_nesting_depth(line) do
    # Count bracket depth
    openers = ~r/[\[{(]/
    closers = ~r/[\]})]/

    chars = String.graphemes(line)

    {max_depth, _} = Enum.reduce(chars, {0, 0}, fn char, {max_d, current_d} ->
      cond do
        Regex.match?(openers, char) ->
          new_d = current_d + 1
          {max(max_d, new_d), new_d}
        Regex.match?(closers, char) ->
          {max_d, max(0, current_d - 1)}
        true ->
          {max_d, current_d}
      end
    end)

    max_depth
  end

  defp compute_whitespace_ratio(lines) do
    total_chars = lines |> Enum.map(&String.length/1) |> Enum.sum()

    if total_chars == 0 do
      0.5
    else
      whitespace_chars = lines
      |> Enum.map(fn line ->
        line |> String.graphemes() |> Enum.count(&(&1 =~ ~r/\s/))
      end)
      |> Enum.sum()

      clamp(whitespace_chars / total_chars, 0.0, 1.0)
    end
  end

  defp compute_block_regularity(lines) do
    # Detect if there are clear "blocks" separated by blank-ish lines or patterns
    # Look for repeating structural units

    # Simple heuristic: check for consistent indentation patterns
    indents = Enum.map(lines, fn line ->
      case Regex.run(~r/^(\s*)/, line) do
        [_, spaces] -> String.length(spaces)
        _ -> 0
      end
    end)

    indent_changes = indents
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [a, b] -> a != b end)

    if length(lines) <= 1 do
      0.5
    else
      # Few changes = block structure, many changes = irregular
      change_ratio = indent_changes / (length(lines) - 1)
      # Invert: low change ratio = high regularity
      clamp(1.0 - change_ratio, 0.0, 1.0)
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
