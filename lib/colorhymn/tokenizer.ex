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

  # CIDR notation (IP/prefix)
  @cidr_pattern ~r/\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/(?:3[0-2]|[12]?[0-9])\b/

  # Network protocols
  @protocol_pattern ~r/\b(TCP|UDP|ICMP|ICMPv6|SCTP|GRE|ESP|AH|IGMP|OSPF|BGP|RIP|EIGRP|VRRP|HSRP|L2TP|PPTP)\b/i

  # Network interfaces (Linux/BSD style)
  @interface_pattern ~r/\b(eth|enp|ens|eno|wlan|wlp|virbr|veth|docker|br|bond|lo|tap|tun|ppp|vnet)[0-9]+[a-z]?[0-9]*\b/

  # HTTP methods
  @http_method_pattern ~r/\b(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|CONNECT|TRACE)\b/

  # HTTP status codes (3 digits, common patterns)
  @http_status_pattern ~r/\b[1-5][0-9]{2}\b/

  # VPN/IPSec keywords - pre-compiled as single alternation pattern
  @vpn_keywords_list [
    "ipsec", "ikev1", "ikev2", "ike", "isakmp", "l2tp", "openvpn", "wireguard",
    "phase1", "phase2", "sa", "esp", "ah", "tunnel", "transport", "psk",
    "certificate", "dh", "diffie-hellman", "proposal", "policy", "selector",
    "spi", "nonce", "initiator", "responder", "rekey", "lifetime",
    "encryption", "integrity", "prf", "aes", "3des", "sha", "md5", "hmac"
  ]
  @vpn_keywords_pattern Regex.compile!(
    "\\b(" <> Enum.join(@vpn_keywords_list, "|") <> ")\\b",
    [:caseless]
  )

  # SPI (Security Parameter Index) - typically 8 hex digits
  @spi_pattern ~r/\bSPI[=:\s]+(?:0x)?([0-9a-fA-F]{8})\b/i

  # Windows Event IDs
  @event_id_pattern ~r/\b(?:Event\s*ID|EventID)[=:\s]+(\d{1,5})\b/i

  # Windows Security Identifiers (SID)
  @sid_pattern ~r/\bS-1-(?:\d+-)+\d+\b/

  # Windows Registry keys
  @registry_pattern ~r/\b(?:HKEY_(?:LOCAL_MACHINE|CURRENT_USER|CLASSES_ROOT|USERS|CURRENT_CONFIG)|HK(?:LM|CU|CR|U|CC))\\[^\s]+/

  # HRESULT codes (Windows error codes)
  @hresult_pattern ~r/\b0x8[0-9a-fA-F]{7}\b/

  # Hex numbers (0x prefix or standalone hex)
  @hex_pattern ~r/\b0x[0-9a-fA-F]+\b/

  # Regular numbers (integers and floats)
  @number_pattern ~r/\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/

  # Quoted strings
  @string_pattern ~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/

  # Key=value pairs (capture the key part)
  @key_pattern ~r/\b([a-zA-Z_][a-zA-Z0-9_]*)\s*=/

  # Common keywords in logs - pre-compiled as single alternation pattern
  @keywords_list [
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
  @keywords_pattern Regex.compile!(
    "\\b(" <> Enum.join(@keywords_list, "|") <> ")\\b",
    [:caseless]
  )

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
    # Use prepending (O(1)) instead of appending (O(n))
    # Order is reversed here since we prepend; final sort handles priority
    []
    |> prepend_matches(line, @identifier_pattern, :identifier)
    |> prepend_matches(line, @operator_pattern, :operator)
    |> prepend_matches(line, @bracket_chars, :bracket)
    |> prepend_matches(line, @number_pattern, :number)
    |> prepend_matches(line, @http_status_pattern, :http_status)
    |> prepend_matches(line, @keywords_pattern, :keyword)
    |> prepend_matches(line, @vpn_keywords_pattern, :vpn_keyword)
    |> prepend_matches(line, @interface_pattern, :interface)
    |> prepend_matches(line, @protocol_pattern, :protocol)
    |> prepend_matches(line, @http_method_pattern, :http_method)
    |> prepend_keys(line)
    |> prepend_matches(line, @string_pattern, :string)
    |> prepend_matches(line, @hex_pattern, :hex_number)
    |> prepend_matches(line, @hresult_pattern, :hresult)
    |> prepend_spis(line)
    |> prepend_event_ids(line)
    |> prepend_matches(line, @sid_pattern, :sid)
    |> prepend_ports(line)
    |> prepend_matches(line, @domain_pattern, :domain)
    |> prepend_matches(line, @registry_pattern, :registry_key)
    |> prepend_matches(line, @path_pattern, :path)
    |> prepend_matches(line, @ipv4_pattern, :ip_address)
    |> prepend_matches(line, @cidr_pattern, :cidr)
    |> prepend_matches(line, @ipv6_pattern, :ipv6_address)
    |> prepend_matches(line, @mac_pattern, :mac_address)
    |> prepend_matches(line, @email_pattern, :email)
    |> prepend_matches(line, @url_pattern, :url)
    |> prepend_matches(line, @uuid_pattern, :uuid)
    |> prepend_matches(line, @log_level_pattern, :log_level)
    |> prepend_timestamps(line)
  end

  # Efficient prepending helpers
  defp prepend_matches(tokens, line, pattern, type) do
    case Regex.scan(pattern, line, return: :index) do
      [] -> tokens
      matches ->
        Enum.reduce(matches, tokens, fn match, acc ->
          {start, len} = case match do
            [{s, l}] -> {s, l}
            [{s, l} | _] -> {s, l}
          end
          [Token.new(type, binary_part(line, start, len), start) | acc]
        end)
    end
  end

  defp prepend_timestamps(tokens, line) do
    Enum.reduce(@timestamp_patterns, tokens, fn pattern, acc ->
      prepend_matches(acc, line, pattern, :timestamp)
    end)
  end

  defp prepend_keys(tokens, line) do
    case Regex.scan(@key_pattern, line, return: :index) do
      [] -> tokens
      matches ->
        Enum.reduce(matches, tokens, fn [{_full_start, _full_len}, {key_start, key_len}], acc ->
          [Token.new(:key, binary_part(line, key_start, key_len), key_start) | acc]
        end)
    end
  end

  defp prepend_ports(tokens, line) do
    case Regex.scan(@port_pattern, line, return: :index) do
      [] -> tokens
      matches ->
        Enum.reduce(matches, tokens, fn [{_full_start, _full_len}, {port_start, port_len}], acc ->
          port_value = binary_part(line, port_start, port_len)
          port_num = String.to_integer(port_value)
          if port_num >= 1 and port_num <= 65535 do
            [Token.new(:port, port_value, port_start) | acc]
          else
            acc
          end
        end)
    end
  end

  defp prepend_event_ids(tokens, line) do
    case Regex.scan(@event_id_pattern, line, return: :index) do
      [] -> tokens
      matches ->
        Enum.reduce(matches, tokens, fn [{full_start, full_len} | _], acc ->
          [Token.new(:event_id, binary_part(line, full_start, full_len), full_start) | acc]
        end)
    end
  end

  defp prepend_spis(tokens, line) do
    case Regex.scan(@spi_pattern, line, return: :index) do
      [] -> tokens
      matches ->
        Enum.reduce(matches, tokens, fn [{full_start, full_len} | _], acc ->
          [Token.new(:spi, binary_part(line, full_start, full_len), full_start) | acc]
        end)
    end
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
