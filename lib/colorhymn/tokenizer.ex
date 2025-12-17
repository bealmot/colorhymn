defmodule Colorhymn.Tokenizer do
  @moduledoc """
  Log line tokenizer - breaks text into semantically tagged spans.

  Tokens are identified in priority order (most specific first).
  Overlapping matches are resolved by first-match-wins at each position.
  """

  alias Colorhymn.Tokenizer.Token

  # ============================================================================
  # Pattern Definitions (ordered by priority)
  # ============================================================================

  # Timestamps - various formats
  @timestamp_patterns [
    # ISO 8601 with optional milliseconds and timezone
    ~r/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/,
    # Syslog format: Mon DD HH:MM:SS
    ~r/(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/,
    # Windows format: MM/DD/YYYY HH:MM:SS
    ~r/\d{1,2}\/\d{1,2}\/\d{4}\s+\d{1,2}:\d{2}:\d{2}(?:\s*(?:AM|PM))?/i,
    # Unix epoch (10 or 13 digits)
    ~r/\b1[4-9]\d{8,11}\b/,
    # Time only HH:MM:SS.mmm
    ~r/\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b/
  ]

  # Log levels
  @log_level_pattern ~r/\b(TRACE|DEBUG|INFO|NOTICE|WARN(?:ING)?|ERROR|CRIT(?:ICAL)?|FATAL|EMERG(?:ENCY)?|ALERT|SEVERE)\b/i

  # UUIDs
  @uuid_pattern ~r/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/

  # URLs
  @url_pattern ~r/https?:\/\/[^\s<>"{}|\\^`\[\]]+/

  # Email addresses
  @email_pattern ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/

  # MAC addresses
  @mac_pattern ~r/\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b/

  # IPv6 addresses (simplified - catches most common formats)
  @ipv6_pattern ~r/\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,7}:\b|\b::(?:[0-9a-fA-F]{1,4}:){0,6}[0-9a-fA-F]{1,4}\b/

  # IPv4 addresses
  @ipv4_pattern ~r/\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/

  # File paths (Unix and Windows)
  @path_pattern ~r/(?:\/[\w.-]+)+\/?|[A-Za-z]:\\(?:[\w.-]+\\)*[\w.-]+/

  # Domain names (must have at least one dot, TLD-like ending)
  @domain_pattern ~r/\b(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}\b/

  # Port numbers (after colon, 1-65535)
  @port_pattern ~r/:(\d{1,5})\b/

  # Hex numbers (0x prefix or standalone hex)
  @hex_pattern ~r/\b0x[0-9a-fA-F]+\b/

  # Regular numbers (integers and floats)
  @number_pattern ~r/\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/

  # Quoted strings
  @string_pattern ~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/

  # Key=value pairs (capture the key part)
  @key_pattern ~r/\b([a-zA-Z_][a-zA-Z0-9_]*)\s*=/

  # Common keywords in logs
  @keywords [
    "true", "false", "null", "nil", "none", "yes", "no",
    "success", "failed", "failure", "error", "ok", "err",
    "start", "stop", "begin", "end", "init", "shutdown",
    "connect", "disconnect", "connected", "disconnected",
    "open", "close", "opened", "closed",
    "send", "receive", "sent", "received",
    "request", "response", "req", "res",
    "read", "write", "get", "set", "put", "post", "delete",
    "allow", "deny", "accept", "reject", "block", "permit",
    "enable", "disable", "enabled", "disabled",
    "active", "inactive", "up", "down",
    "timeout", "retry", "retrying"
  ]

  # Brackets and operators
  @bracket_chars ~r/[\[\]{}()]/
  @operator_pattern ~r/[=<>!&|+\-*\/%^~]+/

  # Identifiers (catch-all for word-like tokens)
  @identifier_pattern ~r/\b[a-zA-Z_][a-zA-Z0-9_]*\b/

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Tokenize a single line of text.
  Returns a list of tokens covering the entire line.
  """
  def tokenize(line) when is_binary(line) do
    # Find all semantic tokens
    tokens = find_all_tokens(line)

    # Sort by position and resolve overlaps
    tokens
    |> Enum.sort_by(& &1.start)
    |> resolve_overlaps()
    |> fill_gaps(line)
  end

  @doc """
  Tokenize multiple lines, returning a list of token lists.
  """
  def tokenize_lines(lines) when is_list(lines) do
    Enum.map(lines, &tokenize/1)
  end

  # ============================================================================
  # Token Finding
  # ============================================================================

  defp find_all_tokens(line) do
    # Process patterns in priority order
    []
    |> find_timestamps(line)
    |> find_log_levels(line)
    |> find_uuids(line)
    |> find_urls(line)
    |> find_emails(line)
    |> find_macs(line)
    |> find_ipv6(line)
    |> find_ipv4(line)
    |> find_paths(line)
    |> find_domains(line)
    |> find_ports(line)
    |> find_hex_numbers(line)
    |> find_strings(line)
    |> find_keys(line)
    |> find_keywords(line)
    |> find_numbers(line)
    |> find_brackets(line)
    |> find_operators(line)
    |> find_identifiers(line)
  end

  defp find_timestamps(tokens, line) do
    matches = Enum.flat_map(@timestamp_patterns, fn pattern ->
      find_pattern_matches(line, pattern, :timestamp)
    end)
    tokens ++ matches
  end

  defp find_log_levels(tokens, line) do
    tokens ++ find_pattern_matches(line, @log_level_pattern, :log_level)
  end

  defp find_uuids(tokens, line) do
    tokens ++ find_pattern_matches(line, @uuid_pattern, :uuid)
  end

  defp find_urls(tokens, line) do
    tokens ++ find_pattern_matches(line, @url_pattern, :url)
  end

  defp find_emails(tokens, line) do
    tokens ++ find_pattern_matches(line, @email_pattern, :email)
  end

  defp find_macs(tokens, line) do
    tokens ++ find_pattern_matches(line, @mac_pattern, :mac_address)
  end

  defp find_ipv6(tokens, line) do
    tokens ++ find_pattern_matches(line, @ipv6_pattern, :ipv6_address)
  end

  defp find_ipv4(tokens, line) do
    tokens ++ find_pattern_matches(line, @ipv4_pattern, :ip_address)
  end

  defp find_paths(tokens, line) do
    tokens ++ find_pattern_matches(line, @path_pattern, :path)
  end

  defp find_domains(tokens, line) do
    tokens ++ find_pattern_matches(line, @domain_pattern, :domain)
  end

  defp find_ports(tokens, line) do
    # Special handling - capture group after colon
    Regex.scan(@port_pattern, line, return: :index)
    |> Enum.map(fn [{_full_start, _full_len}, {port_start, port_len}] ->
      port_value = binary_part(line, port_start, port_len)
      port_num = String.to_integer(port_value)
      if port_num >= 1 and port_num <= 65535 do
        Token.new(:port, port_value, port_start)
      else
        nil
      end
    end)
    |> Enum.filter(& &1)
    |> then(&(tokens ++ &1))
  end

  defp find_hex_numbers(tokens, line) do
    tokens ++ find_pattern_matches(line, @hex_pattern, :hex_number)
  end

  defp find_strings(tokens, line) do
    tokens ++ find_pattern_matches(line, @string_pattern, :string)
  end

  defp find_keys(tokens, line) do
    # Special handling - capture group for key name
    Regex.scan(@key_pattern, line, return: :index)
    |> Enum.map(fn [{_full_start, _full_len}, {key_start, key_len}] ->
      key_value = binary_part(line, key_start, key_len)
      Token.new(:key, key_value, key_start)
    end)
    |> then(&(tokens ++ &1))
  end

  defp find_keywords(tokens, line) do
    lower_line = String.downcase(line)

    keyword_tokens = @keywords
    |> Enum.flat_map(fn kw ->
      find_word_positions(lower_line, line, kw, :keyword)
    end)

    tokens ++ keyword_tokens
  end

  defp find_word_positions(lower_line, original_line, word, type) do
    pattern = ~r/\b#{Regex.escape(word)}\b/i

    Regex.scan(pattern, lower_line, return: :index)
    |> Enum.map(fn [{start, len}] ->
      value = binary_part(original_line, start, len)
      Token.new(type, value, start)
    end)
  end

  defp find_numbers(tokens, line) do
    tokens ++ find_pattern_matches(line, @number_pattern, :number)
  end

  defp find_brackets(tokens, line) do
    tokens ++ find_pattern_matches(line, @bracket_chars, :bracket)
  end

  defp find_operators(tokens, line) do
    tokens ++ find_pattern_matches(line, @operator_pattern, :operator)
  end

  defp find_identifiers(tokens, line) do
    tokens ++ find_pattern_matches(line, @identifier_pattern, :identifier)
  end

  defp find_pattern_matches(line, pattern, type) do
    Regex.scan(pattern, line, return: :index)
    |> Enum.map(fn
      [{start, len}] ->
        value = binary_part(line, start, len)
        Token.new(type, value, start)
      [{start, len} | _groups] ->
        value = binary_part(line, start, len)
        Token.new(type, value, start)
    end)
  end

  # ============================================================================
  # Overlap Resolution
  # ============================================================================

  defp resolve_overlaps(tokens) do
    # First-match-wins: earlier tokens in the sorted list take priority
    # because they were found by higher-priority patterns
    Enum.reduce(tokens, [], fn token, acc ->
      if overlaps_any?(token, acc) do
        acc
      else
        [token | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp overlaps_any?(token, existing_tokens) do
    Enum.any?(existing_tokens, fn existing ->
      overlaps?(token, existing)
    end)
  end

  defp overlaps?(t1, t2) do
    t1_end = Token.end_pos(t1)
    t2_end = Token.end_pos(t2)

    # Overlaps if ranges intersect
    t1.start < t2_end and t2.start < t1_end
  end

  # ============================================================================
  # Gap Filling
  # ============================================================================

  defp fill_gaps(tokens, line) do
    line_length = byte_size(line)

    {result, last_end} = Enum.reduce(tokens, {[], 0}, fn token, {acc, pos} ->
      # Fill gap before this token
      gap_tokens = if token.start > pos do
        gap_text = binary_part(line, pos, token.start - pos)
        [Token.new(:text, gap_text, pos)]
      else
        []
      end

      {acc ++ gap_tokens ++ [token], Token.end_pos(token)}
    end)

    # Fill any remaining gap at the end
    if last_end < line_length do
      remaining = binary_part(line, last_end, line_length - last_end)
      result ++ [Token.new(:text, remaining, last_end)]
    else
      result
    end
  end
end
