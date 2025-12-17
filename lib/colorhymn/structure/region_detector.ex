defmodule Colorhymn.Structure.RegionDetector do
  @moduledoc """
  Detects semantic region boundaries within a single log line.

  Regions are higher-level groupings of tokens:
  - Timestamp region: Date/time at line start
  - Log level region: Severity indicator (ERROR, WARN, etc.)
  - Component region: Module/service name in brackets [db-pool]
  - Key-value region: key=value or key:value pairs
  - Message region: Everything after structured parts
  """

  alias Colorhymn.Structure.Region
  alias Colorhymn.Tokenizer
  alias Colorhymn.Tokenizer.Token

  @doc """
  Detect all regions in a line given its tokens.
  Returns a list of Region structs sorted by start position.
  """
  def detect(line, tokens \\ nil) do
    tokens = tokens || Tokenizer.tokenize(line)

    # Detect each region type
    timestamp = detect_timestamp_region(tokens)
    log_level = detect_log_level_region(line, tokens)
    components = detect_component_regions(line, tokens)
    key_values = detect_key_value_regions(tokens)
    brackets = detect_bracket_regions(line, tokens, components)

    # Collect all detected regions
    structured_regions =
      [timestamp, log_level | components ++ key_values ++ brackets]
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.start)

    # Detect message region (everything after structured parts)
    message = detect_message_region(line, tokens, structured_regions)

    # Combine and sort all regions
    all_regions =
      (structured_regions ++ List.wrap(message))
      |> Enum.sort_by(& &1.start)
      |> resolve_overlaps()

    all_regions
  end

  # ============================================================================
  # Timestamp Detection
  # ============================================================================

  defp detect_timestamp_region(tokens) do
    # Find the first timestamp token (usually at line start)
    case Enum.find(tokens, &(&1.type == :timestamp)) do
      nil -> nil
      ts_token -> Region.from_token(ts_token, :timestamp)
    end
  end

  # ============================================================================
  # Log Level Detection
  # ============================================================================

  defp detect_log_level_region(line, tokens) do
    case Enum.find(tokens, &(&1.type == :log_level)) do
      nil ->
        nil

      ll_token ->
        # Check if wrapped in brackets
        {start, length, included_tokens} =
          maybe_include_surrounding_brackets(ll_token, tokens, line)

        level_name = normalize_level(ll_token.value)

        %Region{
          type: :log_level,
          start: start,
          length: length,
          value: binary_part(line, start, min(length, byte_size(line) - start)),
          tokens: included_tokens,
          metadata: %{level: level_name}
        }
    end
  end

  defp maybe_include_surrounding_brackets(%Token{} = token, tokens, line) do
    # Look for bracket immediately before
    prev_bracket =
      tokens
      |> Enum.filter(&(&1.type == :bracket and &1.start + &1.length == token.start))
      |> List.first()

    # Look for bracket immediately after
    token_end = token.start + token.length
    next_bracket =
      tokens
      |> Enum.filter(&(&1.type == :bracket and &1.start == token_end))
      |> List.first()

    cond do
      # Wrapped in brackets [ERROR]
      prev_bracket && next_bracket &&
        prev_bracket.value in ["[", "("] &&
          next_bracket.value in ["]", ")"] ->
        start = prev_bracket.start
        length = next_bracket.start + next_bracket.length - start
        {start, length, [prev_bracket, token, next_bracket]}

      # Just the token itself
      true ->
        {token.start, token.length, [token]}
    end
  end

  defp normalize_level(value) do
    value
    |> String.upcase()
    |> String.trim()
    |> case do
      "FATAL" -> :fatal
      "CRITICAL" -> :critical
      "CRIT" -> :critical
      "ERROR" -> :error
      "ERR" -> :error
      "WARN" -> :warning
      "WARNING" -> :warning
      "INFO" -> :info
      "DEBUG" -> :debug
      "TRACE" -> :trace
      _ -> :unknown
    end
  end

  # ============================================================================
  # Component Detection (bracketed module names like [db-pool])
  # ============================================================================

  defp detect_component_regions(line, tokens) do
    # Find bracket pairs that contain simple identifier-like content
    bracket_pairs = find_bracket_pairs(tokens)

    bracket_pairs
    |> Enum.filter(&is_component_bracket?(&1, line))
    |> Enum.map(fn {open, close, inner} ->
      all_tokens = [open | inner] ++ [close]
      content = extract_bracket_content(line, open, close)

      %Region{
        type: :component,
        start: open.start,
        length: close.start + close.length - open.start,
        value: binary_part(line, open.start, close.start + close.length - open.start),
        tokens: all_tokens,
        metadata: %{name: content}
      }
    end)
  end

  defp is_component_bracket?({open, _close, inner}, _line) do
    # Component brackets: [identifier] or [identifier-identifier]
    # Not too many tokens, no complex content
    open.value == "[" and
      length(inner) <= 5 and
      Enum.all?(inner, fn t ->
        t.type in [:identifier, :text, :operator, :keyword] and
          (t.type != :operator or t.value in ["-", "_", "."])
      end)
  end

  defp extract_bracket_content(line, open, close) do
    start = open.start + open.length
    length = close.start - start
    if length > 0, do: binary_part(line, start, length), else: ""
  end

  # ============================================================================
  # Key-Value Detection (key=value, key:value patterns)
  # ============================================================================

  defp detect_key_value_regions(tokens) do
    tokens
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.flat_map(fn
      [key, sep, value] ->
        if is_kv_pattern?(key, sep, value) do
          [build_kv_region(key, sep, value)]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp is_kv_pattern?(key, sep, value) do
    key.type in [:key, :identifier, :keyword] and
      sep.type in [:operator, :text] and
      sep.value in ["=", ":"] and
      value.type not in [:text, :bracket] and
      # Ensure key ends right before separator
      key.start + key.length == sep.start and
      # Ensure separator ends right before value
      sep.start + sep.length == value.start
  end

  defp build_kv_region(key, sep, value) do
    %Region{
      type: :key_value,
      start: key.start,
      length: value.start + value.length - key.start,
      value: "#{key.value}#{sep.value}#{value.value}",
      tokens: [key, sep, value],
      metadata: %{
        key: key.value,
        separator: sep.value,
        value: value.value
      }
    }
  end

  # ============================================================================
  # Bracket Detection (other bracketed content)
  # ============================================================================

  defp detect_bracket_regions(line, tokens, component_regions) do
    bracket_pairs = find_bracket_pairs(tokens)

    # Filter out brackets that are already part of component regions
    component_starts = MapSet.new(Enum.map(component_regions, & &1.start))

    bracket_pairs
    |> Enum.reject(fn {open, _close, _inner} ->
      MapSet.member?(component_starts, open.start)
    end)
    |> Enum.map(fn {open, close, inner} ->
      all_tokens = [open | inner] ++ [close]

      %Region{
        type: :bracket,
        start: open.start,
        length: close.start + close.length - open.start,
        value: binary_part(line, open.start, close.start + close.length - open.start),
        tokens: all_tokens,
        metadata: %{bracket_type: open.value}
      }
    end)
  end

  defp find_bracket_pairs(tokens) do
    # Extract bracket tokens
    brackets = Enum.filter(tokens, &(&1.type == :bracket))

    # Match opening/closing pairs using a stack
    match_brackets(brackets, tokens, [], [])
  end

  defp match_brackets([], _all_tokens, _stack, pairs), do: Enum.reverse(pairs)

  defp match_brackets([bracket | rest], all_tokens, stack, pairs) do
    cond do
      bracket.value in ["[", "(", "{"] ->
        match_brackets(rest, all_tokens, [bracket | stack], pairs)

      bracket.value in ["]", ")", "}"] and stack != [] ->
        [open | remaining_stack] = stack

        if matches?(open.value, bracket.value) do
          inner = tokens_between(all_tokens, open, bracket)
          pair = {open, bracket, inner}
          match_brackets(rest, all_tokens, remaining_stack, [pair | pairs])
        else
          # Mismatched - skip
          match_brackets(rest, all_tokens, remaining_stack, pairs)
        end

      true ->
        match_brackets(rest, all_tokens, stack, pairs)
    end
  end

  defp matches?("[", "]"), do: true
  defp matches?("(", ")"), do: true
  defp matches?("{", "}"), do: true
  defp matches?(_, _), do: false

  defp tokens_between(tokens, open, close) do
    open_end = open.start + open.length
    close_start = close.start

    Enum.filter(tokens, fn t ->
      t.start >= open_end and t.start + t.length <= close_start
    end)
  end

  # ============================================================================
  # Message Detection (everything after structured regions)
  # ============================================================================

  defp detect_message_region(line, tokens, structured_regions) do
    line_length = byte_size(line)

    if line_length == 0 do
      nil
    else
      # Find the rightmost end of structured regions
      last_structured_end =
        structured_regions
        |> Enum.map(&Region.end_pos/1)
        |> Enum.max(fn -> 0 end)

      # Skip whitespace after last structured region
      message_start = skip_whitespace(line, last_structured_end)

      if message_start < line_length do
        # Get tokens in the message region
        message_tokens = Enum.filter(tokens, &(&1.start >= message_start))

        %Region{
          type: :message,
          start: message_start,
          length: line_length - message_start,
          value: binary_part(line, message_start, line_length - message_start),
          tokens: message_tokens,
          metadata: %{}
        }
      else
        nil
      end
    end
  end

  defp skip_whitespace(line, pos) do
    line_length = byte_size(line)

    if pos >= line_length do
      line_length
    else
      case binary_part(line, pos, 1) do
        " " -> skip_whitespace(line, pos + 1)
        "\t" -> skip_whitespace(line, pos + 1)
        _ -> pos
      end
    end
  end

  # ============================================================================
  # Overlap Resolution
  # ============================================================================

  defp resolve_overlaps(regions) do
    # Sort by start position, then by length (prefer longer regions)
    sorted = Enum.sort_by(regions, fn r -> {r.start, -r.length} end)

    # Keep non-overlapping regions (first-wins)
    {kept, _} =
      Enum.reduce(sorted, {[], 0}, fn region, {acc, last_end} ->
        if region.start >= last_end do
          {[region | acc], Region.end_pos(region)}
        else
          {acc, last_end}
        end
      end)

    Enum.reverse(kept)
  end
end
