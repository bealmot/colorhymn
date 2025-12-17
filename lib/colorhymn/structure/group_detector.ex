defmodule Colorhymn.Structure.GroupDetector do
  @moduledoc """
  Detects multi-line groups within log content.

  Groups are sequences of related lines that should be analyzed as a unit:
  - Continuation lines: Indented, starting with |, [-, etc.
  - Table data: Routing tables, formatted columnar output
  - Stack traces: Exception message + "at" frames
  - Block: Generic multi-line groupings
  """

  alias Colorhymn.Structure.{Group, RegionDetector}

  @doc """
  Detect groups in a list of lines.
  Returns a list of Group structs covering all lines.
  """
  def detect(lines) when is_list(lines) do
    lines
    |> Enum.with_index()
    |> detect_groups([])
    |> Enum.reverse()
  end

  # ============================================================================
  # Main Detection Loop
  # ============================================================================

  defp detect_groups([], acc), do: acc

  defp detect_groups([{line, idx} | rest], acc) do
    cond do
      # Try to detect a stack trace starting here
      stack_trace = try_detect_stack_trace([{line, idx} | rest]) ->
        remaining = Enum.drop(rest, length(stack_trace.lines) - 1)
        detect_groups(remaining, [stack_trace | acc])

      # Try to detect a table starting here
      table = try_detect_table([{line, idx} | rest]) ->
        remaining = Enum.drop(rest, length(table.lines) - 1)
        detect_groups(remaining, [table | acc])

      # Try to detect continuation lines
      continuation = try_detect_continuation([{line, idx} | rest]) ->
        remaining = Enum.drop(rest, length(continuation.lines) - 1)
        detect_groups(remaining, [continuation | acc])

      # Single line (no grouping)
      true ->
        regions = RegionDetector.detect(line)
        group = Group.single(line, idx, regions)
        detect_groups(rest, [group | acc])
    end
  end

  # ============================================================================
  # Stack Trace Detection
  # ============================================================================

  @stack_trace_starters [
    ~r/^(Exception|Error|Traceback|panic|FATAL|Caused by):/i,
    ~r/^(java\.|org\.|com\.)\S+Exception/,
    ~r/^\*\*\s*\(/,  # Elixir exceptions
    ~r/^raise\s+/i,
    ~r/^\s*File\s+"[^"]+",\s+line\s+\d+/i  # Python tracebacks
  ]

  @stack_frame_patterns [
    ~r/^\s+at\s+/,                           # Java/JS "at" frames
    ~r/^\s+from\s+/,                         # Ruby "from" frames
    ~r/^\s+\(.*:\d+:\d+\)/,                 # JS/Node frames
    ~r/^\s+File\s+"[^"]+",\s+line\s+\d+/i, # Python frames
    ~r/^\s+\d+:\s+/,                         # Numbered frames
    ~r/^\s+│/,                               # Elixir fancy frames
    ~r/^\s+\|/,                              # Pipe-style frames
    ~r/^\s+\*\*/                             # Elixir exception details
  ]

  defp try_detect_stack_trace([{line, idx} | rest]) do
    if is_stack_trace_start?(line) do
      # Collect all following stack frames
      {frames, _remaining} = collect_stack_frames(rest, [line])

      if length(frames) > 1 do
        regions_list = Enum.map(frames, &RegionDetector.detect/1)

        %Group{
          type: :stack_trace,
          start_line: idx,
          end_line: idx + length(frames) - 1,
          lines: frames,
          regions: regions_list,
          metadata: %{
            exception_line: line,
            frame_count: length(frames) - 1
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp is_stack_trace_start?(line) do
    Enum.any?(@stack_trace_starters, &Regex.match?(&1, line))
  end

  defp collect_stack_frames([], acc), do: {Enum.reverse(acc), []}

  defp collect_stack_frames([{line, _idx} | rest] = remaining, acc) do
    if is_stack_frame?(line) or is_continuation_of_stack?(line, acc) do
      collect_stack_frames(rest, [line | acc])
    else
      {Enum.reverse(acc), remaining}
    end
  end

  defp is_stack_frame?(line) do
    Enum.any?(@stack_frame_patterns, &Regex.match?(&1, line))
  end

  defp is_continuation_of_stack?(line, acc) when length(acc) > 0 do
    # Lines that continue an exception (Caused by, nested exceptions)
    String.match?(line, ~r/^Caused by:/i) or
      String.match?(line, ~r/^\s+\.\.\.\s+\d+\s+more/i) or
      (String.match?(line, ~r/^\s{2,}/) and String.trim(line) != "")
  end

  defp is_continuation_of_stack?(_line, _acc), do: false

  # ============================================================================
  # Table Detection
  # ============================================================================

  @table_indicators [
    ~r/^[\+\-]{3,}/,           # +--- or ---- borders
    ~r/^[\|│]\s.*[\|│]$/,      # | col | col |
    ~r/^\s*\d+\.\d+\.\d+\.\d+.*\s+\d+\.\d+\.\d+\.\d+/,  # Routing tables
    ~r/^[A-Z_]+\s{2,}[A-Z_]+\s{2,}/  # Column headers
  ]

  defp try_detect_table([{line, idx} | rest]) do
    if is_table_row?(line) do
      # Collect similar rows
      {rows, _remaining} = collect_table_rows(rest, [line], line)

      if length(rows) >= 2 do
        regions_list = Enum.map(rows, &RegionDetector.detect/1)

        %Group{
          type: :table,
          start_line: idx,
          end_line: idx + length(rows) - 1,
          lines: rows,
          regions: regions_list,
          metadata: %{
            row_count: length(rows),
            has_border: has_table_border?(rows)
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp is_table_row?(line) do
    Enum.any?(@table_indicators, &Regex.match?(&1, line)) or
      has_consistent_columns?(line)
  end

  defp has_consistent_columns?(line) do
    # Check for multiple whitespace-separated columns
    parts = String.split(line, ~r/\s{2,}/, trim: true)
    length(parts) >= 3 and String.length(line) > 20
  end

  defp collect_table_rows([], acc, _first), do: {Enum.reverse(acc), []}

  defp collect_table_rows([{line, _idx} | rest] = remaining, acc, first) do
    if is_similar_table_row?(line, first, acc) do
      collect_table_rows(rest, [line | acc], first)
    else
      {Enum.reverse(acc), remaining}
    end
  end

  defp is_similar_table_row?(line, first, acc) do
    # Check if this line looks like it belongs to the same table
    cond do
      # Border rows
      String.match?(line, ~r/^[\+\-│|]+$/) ->
        true

      # Same structure as first row
      similar_column_structure?(line, first) ->
        true

      # Empty line ends table
      String.trim(line) == "" ->
        false

      # Continue if we're in a bordered table
      has_table_border?(acc) and String.match?(line, ~r/[\|│]/) ->
        true

      true ->
        false
    end
  end

  defp similar_column_structure?(line1, line2) do
    cols1 = String.split(line1, ~r/\s{2,}/, trim: true) |> length()
    cols2 = String.split(line2, ~r/\s{2,}/, trim: true) |> length()
    abs(cols1 - cols2) <= 1 and cols1 >= 2
  end

  defp has_table_border?(rows) do
    Enum.any?(rows, &String.match?(&1, ~r/^[\+\-]{3,}/))
  end

  # ============================================================================
  # Continuation Detection
  # ============================================================================

  @continuation_patterns [
    ~r/^\s{2,}\S/,         # Indented content (2+ spaces)
    ~r/^\t+\S/,            # Tab-indented
    ~r/^\s*\|/,            # Pipe continuation
    ~r/^\s*\[-/,           # Bracket-dash lists [- item
    ~r/^\s*•/,             # Bullet points
    ~r/^\s*-\s+/,          # Dash lists
    ~r/^\s*\d+\.\s+/,      # Numbered lists
    ~r/^\s*>\s*/,          # Quoted/nested content
    ~r/^\s*\.\.\./         # Ellipsis continuation
  ]

  defp try_detect_continuation([{_line, _idx}]), do: nil

  defp try_detect_continuation([{line, idx}, {next_line, _next_idx} | rest]) do
    # The first line is the "header", check if next line is a continuation
    if is_continuation_line?(next_line) and not is_continuation_line?(line) do
      # Collect all continuation lines
      {continuations, _remaining} = collect_continuations([{next_line, nil} | rest], [])

      if length(continuations) > 0 do
        all_lines = [line | continuations]
        regions_list = Enum.map(all_lines, &RegionDetector.detect/1)

        %Group{
          type: :continuation,
          start_line: idx,
          end_line: idx + length(all_lines) - 1,
          lines: all_lines,
          regions: regions_list,
          metadata: %{
            header_line: line,
            continuation_count: length(continuations)
          }
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp is_continuation_line?(line) do
    Enum.any?(@continuation_patterns, &Regex.match?(&1, line))
  end

  defp collect_continuations([], acc), do: {Enum.reverse(acc), []}

  defp collect_continuations([{line, _idx} | rest] = remaining, acc) do
    if is_continuation_line?(line) do
      collect_continuations(rest, [line | acc])
    else
      {Enum.reverse(acc), remaining}
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Check if a group spans multiple lines.
  """
  def multi_line?(%Group{type: :single}), do: false
  def multi_line?(%Group{}), do: true

  @doc """
  Get the combined content of a group for analysis.
  """
  def combined_content(%Group{lines: lines}) do
    Enum.join(lines, "\n")
  end
end
