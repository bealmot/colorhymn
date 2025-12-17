defmodule Colorhymn.FirstSight do
  @moduledoc """
  First Sight - rapid perception of log identity, shape, and temperature.

  Answers: What am I looking at? What's its shape? What's its mood?
  """

  alias Colorhymn.Perception

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Perceive a log file and return a first impression.

  ## Parameters
    - content: The raw log text
    - filename: Optional filename for hints

  ## Returns
    A map containing:
    - :type - The detected log type (e.g., {:vpn_log, :session})
    - :format - The structural format (e.g., :key_value, :json, :tabular)
    - :perception - A %Perception{} struct with continuous scores across all dimensions
    - :temperature - Overall mood (:calm, :troubled, :critical)
    - :confidence - How sure we are (0.0 to 1.0)
  """
  def perceive(content, filename \\ nil) do
    lines = String.split(content, ~r/\r?\n/, trim: true)
    sample = Enum.take(lines, 50)
    timestamps = extract_timestamps(lines)

    {temperature, temperature_score} = detect_temperature(lines)

    %{
      type: detect_type(filename, sample, content),
      format: detect_format(sample),
      perception: Perception.perceive(content, lines, timestamps),
      temperature: temperature,
      temperature_score: temperature_score,  # Continuous 0.0 (cool) → 1.0 (critical)
      confidence: 0.8  # TODO: calculate based on signal strength
    }
  end

  # ============================================================================
  # Type Detection - What am I looking at?
  # ============================================================================

  defp detect_type(filename, sample, content) do
    # Filename is the strongest signal
    filename_type = detect_from_filename(filename)

    # Content patterns as backup
    content_type = detect_from_content(sample, content)

    # Prefer filename if it gave us something specific
    case filename_type do
      {:unknown, _} -> content_type
      type -> type
    end
  end

  # Filename-based detection
  defp detect_from_filename(nil), do: {:unknown, :no_filename}

  defp detect_from_filename(filename) do
    fname = String.downcase(filename)

    cond do
      # VPN logs
      String.contains?(fname, "vpn") -> {:vpn_log, :generic}
      String.contains?(fname, "ipsec") -> {:vpn_log, :ipsec}
      String.contains?(fname, "openvpn") -> {:vpn_log, :openvpn}
      String.contains?(fname, "wireguard") -> {:vpn_log, :wireguard}

      # Network captures
      String.ends_with?(fname, ".pcap") -> {:capture, :pcap}
      String.ends_with?(fname, ".pcapng") -> {:capture, :pcapng}
      String.contains?(fname, "wireshark") -> {:capture, :wireshark_export}

      # Windows
      String.ends_with?(fname, ".evtx") -> {:os_log, :windows_evtx}
      String.contains?(fname, "ipconfig") -> {:snapshot, :ipconfig}
      String.contains?(fname, "netstat") -> {:snapshot, :netstat}
      String.contains?(fname, "tasklist") -> {:snapshot, :tasklist}
      String.contains?(fname, "route") -> {:snapshot, :routing_table}

      # Auth/SSO
      String.contains?(fname, "auth") -> {:auth_log, :generic}
      String.contains?(fname, "sso") -> {:auth_log, :sso}
      String.contains?(fname, "saml") -> {:auth_log, :saml}
      String.contains?(fname, "oauth") -> {:auth_log, :oauth}

      # Browser
      String.ends_with?(fname, ".har") -> {:browser, :har}

      # DNS
      String.contains?(fname, "dns") -> {:network, :dns}

      # Firewall
      String.contains?(fname, "firewall") -> {:security, :firewall}
      String.contains?(fname, "fw") -> {:security, :firewall}

      # Generic app logs
      String.ends_with?(fname, ".log") -> {:application_log, :generic}
      String.ends_with?(fname, ".txt") -> {:unknown, :text_file}

      true -> {:unknown, :unrecognized}
    end
  end

  # Content-based detection (spray and pray)
  defp detect_from_content(sample, full_content) do
    first_lines = Enum.take(sample, 10) |> Enum.join("\n")

    cond do
      # Structured formats first
      json_log?(first_lines) -> {:structured, :json}

      # Wireshark CSV export
      wireshark_csv?(first_lines) -> {:capture, :wireshark_csv}

      # Windows snapshots
      ipconfig?(first_lines) -> {:snapshot, :ipconfig}
      netstat?(first_lines) -> {:snapshot, :netstat}
      routing_table?(first_lines) -> {:snapshot, :routing_table}
      tasklist?(first_lines) -> {:snapshot, :tasklist}
      dns_cache?(first_lines) -> {:snapshot, :dns_cache}

      # VPN patterns
      vpn_session_log?(full_content) -> {:vpn_log, :session}

      # Auth patterns
      auth_log?(full_content) -> {:auth_log, :generic}

      # Has timestamps = probably an event log
      has_timestamps?(sample) -> {:application_log, :timestamped}

      # Fallback
      true -> {:unknown, :freeform}
    end
  end

  # ============================================================================
  # Pattern Detectors (spray and pray)
  # ============================================================================

  defp json_log?(text), do: String.starts_with?(String.trim(text), "{")

  defp wireshark_csv?(text) do
    String.contains?(text, "No.\t") or
    String.contains?(text, "\"No.\",\"Time\"")
  end

  defp ipconfig?(text) do
    String.contains?(text, "Windows IP Configuration") or
    String.contains?(text, "IPv4 Address") or
    String.contains?(text, "Default Gateway")
  end

  defp netstat?(text) do
    String.contains?(text, "Active Connections") or
    String.contains?(text, "Proto  Local Address")
  end

  defp routing_table?(text) do
    String.contains?(text, "Route Table") or
    String.contains?(text, "Network Destination") or
    String.contains?(text, "Persistent Routes")
  end

  defp tasklist?(text) do
    String.contains?(text, "Image Name") and String.contains?(text, "PID") or
    Regex.match?(~r/\.exe\s+\d+/, text)
  end

  defp dns_cache?(text) do
    String.contains?(text, "DNS Resolver Cache") or
    String.contains?(text, "Record Name") and String.contains?(text, "Record Type")
  end

  defp vpn_session_log?(text) do
    vpn_keywords = ["tunnel", "IKE", "IPSEC", "VPN", "peer", "handshake",
                    "phase1", "phase2", "established", "negotiation"]
    keyword_count = Enum.count(vpn_keywords, &String.contains?(String.downcase(text), String.downcase(&1)))
    keyword_count >= 2
  end

  defp auth_log?(text) do
    auth_keywords = ["login", "logout", "authentication", "authorized",
                     "denied", "token", "session", "credential"]
    keyword_count = Enum.count(auth_keywords, &String.contains?(String.downcase(text), String.downcase(&1)))
    keyword_count >= 2
  end

  defp has_timestamps?(sample) do
    timestamp_pattern = ~r/\d{4}[-\/]\d{2}[-\/]\d{2}|\d{2}:\d{2}:\d{2}|\d{10,13}/
    Enum.any?(sample, &Regex.match?(timestamp_pattern, &1))
  end

  # ============================================================================
  # Format Detection - What structure does it have?
  # ============================================================================

  defp detect_format(sample) do
    first_lines = Enum.take(sample, 5)

    cond do
      all_json?(first_lines) -> :json
      all_key_value?(first_lines) -> :key_value
      looks_tabular?(first_lines) -> :tabular
      has_consistent_delimiter?(first_lines, ",") -> :csv
      has_consistent_delimiter?(first_lines, "\t") -> :tsv
      true -> :freeform
    end
  end

  defp all_json?(lines) do
    Enum.all?(lines, fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[")
    end)
  end

  defp all_key_value?(lines) do
    kv_pattern = ~r/^\s*[\w\.-]+\s*[=:]\s*.+/
    match_ratio = Enum.count(lines, &Regex.match?(kv_pattern, &1)) / max(length(lines), 1)
    match_ratio > 0.6
  end

  defp looks_tabular?(lines) when length(lines) < 2, do: false
  defp looks_tabular?(lines) do
    # Check if lines have consistent column-like structure
    widths = Enum.map(lines, &String.length/1)
    avg_width = Enum.sum(widths) / length(widths)
    variance = Enum.sum(Enum.map(widths, fn w -> :math.pow(w - avg_width, 2) end)) / length(widths)

    # Low variance + contains multiple spaces = probably tabular
    variance < 100 and Enum.all?(lines, &String.contains?(&1, "  "))
  end

  defp has_consistent_delimiter?(lines, _delimiter) when length(lines) < 2, do: false
  defp has_consistent_delimiter?(lines, delimiter) do
    counts = Enum.map(lines, fn line ->
      length(String.split(line, delimiter)) - 1
    end)

    # All lines have same number of delimiters and at least 2
    first = hd(counts)
    first >= 2 and Enum.all?(counts, &(&1 == first))
  end

  # ============================================================================
  # Timestamp Extraction (used by Perception)
  # ============================================================================

  defp extract_timestamps(lines) do
    # Patterns ordered by specificity (most specific first)
    # Each pattern captures the full timestamp including optional milliseconds
    timestamp_patterns = [
      # ISO format with optional ms: 2024-01-15T10:30:45.001 or 2024-01-15T10:30:45
      # Works both bare and inside quotes (JSON)
      {~r/(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)/, :datetime},

      # Syslog format: Jan 15 10:30:45 or Dec  5 08:30:45
      {~r/([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})/, :syslog},

      # Common log format: 15/Jan/2024:10:30:45
      {~r/(\d{2}\/[A-Z][a-z]{2}\/\d{4}:\d{2}:\d{2}:\d{2})/, :clf},

      # Windows event log: 1/15/2024 10:30:45 AM
      {~r/(\d{1,2}\/\d{1,2}\/\d{4}\s+\d{1,2}:\d{2}:\d{2}\s*(?:AM|PM)?)/, :windows},

      # Unix epoch milliseconds (13 digits): 1705318245001
      {~r/"?(\d{13})"?/, :epoch_ms},

      # Unix epoch seconds (10 digits): 1705318245
      {~r/\b(1[6-9]\d{8})\b/, :epoch_s},

      # Time only with optional ms: 10:30:45.001 or 10:30:45
      {~r/\b(\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)\b/, :time_only}
    ]

    lines
    |> Enum.take(200)  # Sample first 200 lines for performance
    |> Enum.flat_map(fn line ->
      Enum.find_value(timestamp_patterns, [], fn {pattern, format} ->
        case Regex.run(pattern, line) do
          [_, match] ->
            case parse_timestamp(match, format) do
              nil -> nil
              ts -> [ts]
            end
          _ -> nil
        end
      end)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Unified timestamp parser that returns seconds (float for sub-second precision)
  defp parse_timestamp(str, :datetime) do
    # Handle both "T" and space separator, strip trailing Z if present
    normalized = str
    |> String.replace(~r/\s+/, "T")
    |> String.trim_trailing("Z")

    # Split off milliseconds if present
    {base, ms} = case String.split(normalized, ".") do
      [base, frac] ->
        # Pad or truncate to 6 digits for microseconds
        frac_normalized = String.pad_trailing(String.slice(frac, 0, 6), 6, "0")
        {base, String.to_integer(frac_normalized) / 1_000_000}
      [base] ->
        {base, 0.0}
    end

    case NaiveDateTime.from_iso8601(base) do
      {:ok, dt} ->
        {secs, _} = NaiveDateTime.to_gregorian_seconds(dt)
        secs + ms
      _ -> nil
    end
  end

  defp parse_timestamp(str, :syslog) do
    # Parse "Jan 15 10:30:45" - assume current year
    case Regex.run(~r/([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})/, str) do
      [_, month, day, hour, min, sec] ->
        month_num = month_to_number(month)
        # Use current year as syslog doesn't include it
        {{year, _, _}, _} = :calendar.local_time()
        case NaiveDateTime.new(year, month_num, String.to_integer(day),
                               String.to_integer(hour), String.to_integer(min),
                               String.to_integer(sec)) do
          {:ok, dt} ->
            {secs, _} = NaiveDateTime.to_gregorian_seconds(dt)
            secs * 1.0
          _ -> nil
        end
      _ -> nil
    end
  end

  defp parse_timestamp(str, :clf) do
    # Parse "15/Jan/2024:10:30:45"
    case Regex.run(~r/(\d{2})\/([A-Z][a-z]{2})\/(\d{4}):(\d{2}):(\d{2}):(\d{2})/, str) do
      [_, day, month, year, hour, min, sec] ->
        month_num = month_to_number(month)
        case NaiveDateTime.new(String.to_integer(year), month_num, String.to_integer(day),
                               String.to_integer(hour), String.to_integer(min),
                               String.to_integer(sec)) do
          {:ok, dt} ->
            {secs, _} = NaiveDateTime.to_gregorian_seconds(dt)
            secs * 1.0
          _ -> nil
        end
      _ -> nil
    end
  end

  defp parse_timestamp(str, :windows) do
    # Parse "1/15/2024 10:30:45 AM"
    case Regex.run(~r/(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s*(AM|PM)?/i, str) do
      [_, month, day, year, hour, min, sec | rest] ->
        hour_int = String.to_integer(hour)
        hour_adjusted = case rest do
          ["PM"] when hour_int < 12 -> hour_int + 12
          ["AM"] when hour_int == 12 -> 0
          _ -> hour_int
        end
        case NaiveDateTime.new(String.to_integer(year), String.to_integer(month),
                               String.to_integer(day), hour_adjusted,
                               String.to_integer(min), String.to_integer(sec)) do
          {:ok, dt} ->
            {secs, _} = NaiveDateTime.to_gregorian_seconds(dt)
            secs * 1.0
          _ -> nil
        end
      _ -> nil
    end
  end

  defp parse_timestamp(str, :epoch_ms) do
    case Integer.parse(str) do
      {n, _} -> n / 1000.0  # Convert ms to seconds
      _ -> nil
    end
  end

  defp parse_timestamp(str, :epoch_s) do
    case Integer.parse(str) do
      {n, _} -> n * 1.0
      _ -> nil
    end
  end

  defp parse_timestamp(str, :time_only) do
    # Convert HH:MM:SS.mmm to seconds since midnight
    {base, ms} = case String.split(str, ".") do
      [base, frac] ->
        frac_normalized = String.pad_trailing(String.slice(frac, 0, 6), 6, "0")
        {base, String.to_integer(frac_normalized) / 1_000_000}
      [base] ->
        {base, 0.0}
    end

    case String.split(base, ":") do
      [h, m, s] ->
        hours = String.to_integer(h)
        mins = String.to_integer(m)
        secs = String.to_integer(s)
        hours * 3600 + mins * 60 + secs + ms
      _ -> nil
    end
  end

  defp month_to_number(month) do
    %{
      "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4,
      "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
      "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
    }[month] || 1
  end

  # ============================================================================
  # Temperature Detection - Context-aware mood/severity sensing
  # ============================================================================

  defp detect_temperature(lines) do
    total = length(lines)

    if total == 0 do
      {:unknown, 0.5}
    else
      # Use weighted scoring - log level indicators count more than mentions
      error_score = score_error_signals(lines)
      warning_score = score_warning_signals(lines)
      success_score = score_success_signals(lines)

      # Normalize by line count
      error_ratio = error_score / total
      warning_ratio = warning_score / total
      success_ratio = success_score / total

      # Calculate continuous temperature score (0.0 = cool, 1.0 = hot)
      #
      # We want a gradual curve where:
      #   0% errors, high success → ~0.15 (calm)
      #   0% errors, neutral → ~0.35 (neutral)
      #   2-5% errors → ~0.45-0.55 (uneasy)
      #   5-15% errors → ~0.55-0.70 (troubled)
      #   15%+ errors → ~0.70-0.90 (critical)
      #
      # Using a piecewise linear approach for more control

      base_temp = cond do
        # Heavy success pushes toward calm
        success_ratio > 0.5 and error_ratio == 0 -> 0.15 + (1 - success_ratio) * 0.3
        # No errors, no strong success = neutral
        error_ratio == 0 and warning_ratio < 0.1 -> 0.35
        # Warnings only push slightly warm
        error_ratio == 0 -> 0.35 + min(warning_ratio * 1.5, 0.2)
        # Errors drive the temperature
        true -> 0.35 + error_ratio * 4.0  # Linear scaling, capped by clamp
      end

      # Warnings add heat on top of base
      warning_heat = if error_ratio > 0, do: warning_ratio * 0.5, else: 0

      # Success cools things down slightly
      cooling = success_ratio * 0.15

      temperature_score = clamp(base_temp + warning_heat - cooling, 0.0, 0.95)

      # Also derive discrete bucket for backward compatibility
      temperature = cond do
        temperature_score > 0.8 -> :critical
        temperature_score > 0.6 -> :troubled
        temperature_score > 0.45 -> :uneasy
        temperature_score < 0.3 -> :calm
        true -> :neutral
      end

      {temperature, Float.round(temperature_score, 3)}
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)

  # ============================================================================
  # Weighted Signal Scoring
  # ============================================================================

  # Strong indicators: log level markers, structured severity fields
  # Weak indicators: keyword mentions that might be values or descriptions

  defp score_error_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      acc + score_line_for_error(line)
    end)
  end

  defp score_line_for_error(line) do
    cond do
      # Strong: Log level indicators (full weight: 1.0)
      is_error_level?(line) -> 1.0

      # Strong: HTTP error status codes
      has_http_error_status?(line) -> 1.0

      # Medium: Error keywords in context that suggests actual error (0.5)
      has_contextual_error?(line) -> 0.5

      # Weak: Just contains error word, might be a value (0.1)
      has_weak_error_mention?(line) -> 0.1

      true -> 0.0
    end
  end

  # Log level patterns: ERROR:, [ERROR], level=error, "level":"error", etc.
  defp is_error_level?(line) do
    level_patterns = [
      # Bracketed: [ERROR], [FATAL], [CRITICAL]
      ~r/\[(ERROR|FATAL|CRITICAL|SEVERE)\]/i,
      # Prefixed: ERROR:, FATAL:, ERROR -
      ~r/\b(ERROR|FATAL|CRITICAL|SEVERE)\s*[:\-\|]/i,
      # After timestamp: 2024-01-15 10:30:45 ERROR
      ~r/\d{2}:\d{2}:\d{2}[.,]?\d*\s+(ERROR|FATAL|CRITICAL)/i,
      # Structured: level=error, severity=critical, "level":"error"
      ~r/(level|severity|loglevel)\s*[=:]\s*"?(error|fatal|critical|severe)"?/i,
      # JSON: "level":"error" or "severity":"critical"
      ~r/"(level|severity)"\s*:\s*"(error|fatal|critical|severe)"/i
    ]
    Enum.any?(level_patterns, &Regex.match?(&1, line))
  end

  defp has_http_error_status?(line) do
    # HTTP 4xx and 5xx status codes in context
    Regex.match?(~r/\b(status|code|http)[=:\s]+[45]\d{2}\b/i, line) or
    Regex.match?(~r/\bHTTP\/\d\.\d\s+[45]\d{2}\b/, line)
  end

  defp has_contextual_error?(line) do
    # Error keywords followed by descriptive text (not just as values)
    contextual_patterns = [
      # "failed to", "error occurred", "exception thrown"
      ~r/\b(failed|error|exception|failure)\s+(to|in|on|at|while|when|occurred|thrown|caught)/i,
      # "connection refused", "request timeout"
      ~r/\b(connection|request|operation)\s+(refused|denied|timeout|failed)/i,
      # "cannot", "could not", "unable to"
      ~r/\b(cannot|couldn't|could not|unable to|failed to)\b/i
    ]
    Enum.any?(contextual_patterns, &Regex.match?(&1, line))
  end

  defp has_weak_error_mention?(line) do
    # Check if error keywords exist but might be values
    error_keywords = ~r/\b(error|fail|failed|failure|exception|fatal|denied|refused|timeout|unreachable|disconnect)\b/i

    if Regex.match?(error_keywords, line) do
      # Downweight if it looks like a key=value where error is the value
      # e.g., "status=error", "gamma=error", "result: error"
      is_value_pattern = ~r/\w+\s*[=:]\s*(error|fail|failed|failure)\b/i
      is_field_name = ~r/"?(error|failure)"?\s*[=:]/i

      cond do
        # It's being used as a value for some other key - very weak signal
        Regex.match?(is_value_pattern, line) and not Regex.match?(~r/(level|severity|status)\s*[=:]/i, line) -> false
        # It's a field name like "error_code:" - not an error itself
        Regex.match?(is_field_name, line) -> false
        # Otherwise, give it weak weight
        true -> true
      end
    else
      false
    end
  end

  defp score_warning_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      acc + score_line_for_warning(line)
    end)
  end

  defp score_line_for_warning(line) do
    cond do
      # Strong: Log level indicators
      is_warning_level?(line) -> 1.0

      # Medium: Contextual warnings
      has_contextual_warning?(line) -> 0.5

      # Weak: Just mentions warning words
      Regex.match?(~r/\b(warn|warning|caution|deprecated)\b/i, line) -> 0.1

      true -> 0.0
    end
  end

  defp is_warning_level?(line) do
    level_patterns = [
      ~r/\[(WARN|WARNING)\]/i,
      ~r/\b(WARN|WARNING)\s*[:\-\|]/i,
      ~r/\d{2}:\d{2}:\d{2}[.,]?\d*\s+(WARN|WARNING)/i,
      ~r/(level|severity)\s*[=:]\s*"?(warn|warning)"?/i,
      ~r/"(level|severity)"\s*:\s*"(warn|warning)"/i
    ]
    Enum.any?(level_patterns, &Regex.match?(&1, line))
  end

  defp has_contextual_warning?(line) do
    Regex.match?(~r/\b(deprecated|retry|retrying|slow|degraded|high\s+latency|low\s+memory)\b/i, line)
  end

  defp score_success_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      acc + score_line_for_success(line)
    end)
  end

  defp score_line_for_success(line) do
    cond do
      # Strong: Log level or status indicators
      is_success_level?(line) -> 1.0

      # Medium: Contextual success
      has_contextual_success?(line) -> 0.5

      true -> 0.0
    end
  end

  defp is_success_level?(line) do
    level_patterns = [
      ~r/\[(INFO|SUCCESS|OK)\]/i,
      ~r/\b(INFO|SUCCESS)\s*[:\-\|]/i,
      ~r/(status|result)\s*[=:]\s*"?(success|ok|completed)"?/i,
      ~r/\bHTTP\/\d\.\d\s+2\d{2}\b/  # HTTP 2xx
    ]
    Enum.any?(level_patterns, &Regex.match?(&1, line))
  end

  defp has_contextual_success?(line) do
    Regex.match?(~r/\b(successfully|succeeded|completed|established|connected|accepted|approved|ready)\b/i, line)
  end
end
