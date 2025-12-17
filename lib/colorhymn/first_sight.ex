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

    {temperature, temperature_score, temp_signal_quality} = detect_temperature(lines)
    {type, type_confidence} = detect_type(filename, sample, content)
    {format, format_confidence} = detect_format(sample)

    # Aggregate confidence from all signal sources
    # Type and format are primary indicators, temperature signal quality is secondary
    confidence = calculate_confidence(type_confidence, format_confidence, temp_signal_quality)

    %{
      type: type,
      format: format,
      perception: Perception.perceive(content, lines, timestamps),
      temperature: temperature,
      temperature_score: temperature_score,
      confidence: confidence
    }
  end

  # Weighted confidence aggregation
  # Type detection: 40% (strong filename signals are very reliable)
  # Format detection: 35% (structural patterns are clear indicators)
  # Temperature signal quality: 25% (how strong vs weak were our severity signals)
  defp calculate_confidence(type_conf, format_conf, temp_quality) do
    raw = type_conf * 0.40 + format_conf * 0.35 + temp_quality * 0.25

    # Boost if multiple signals agree on high confidence
    boost = if type_conf > 0.7 and format_conf > 0.7, do: 0.1, else: 0.0

    # Floor at 0.3 - we always have some useful perception
    Float.round(clamp(raw + boost, 0.3, 0.98), 2)
  end

  # ============================================================================
  # Type Detection - What am I looking at?
  # ============================================================================

  # Returns {type, confidence} tuple
  defp detect_type(filename, sample, content) do
    # Filename is the strongest signal
    {filename_type, filename_conf} = detect_from_filename(filename)

    # Content patterns as backup
    {content_type, content_conf} = detect_from_content(sample, content)

    # Prefer filename if it gave us something specific
    case filename_type do
      {:unknown, _} -> {content_type, content_conf}
      # Filename match + content agreement = boost confidence
      type when type == content_type -> {type, min(filename_conf + 0.15, 0.98)}
      type -> {type, filename_conf}
    end
  end

  # Filename-based detection - returns {type, confidence}
  # Confidence levels:
  #   0.95 - specific file extensions (.evtx, .pcap, .har)
  #   0.85 - specific keyword matches (ipsec, openvpn, wireguard)
  #   0.75 - general keyword matches (vpn, auth, firewall)
  #   0.50 - generic extensions (.log)
  #   0.30 - unknown/no signal
  defp detect_from_filename(nil), do: {{:unknown, :no_filename}, 0.30}

  defp detect_from_filename(filename) do
    fname = String.downcase(filename)

    cond do
      # VPN logs - specific tools are high confidence
      String.contains?(fname, "ipsec") -> {{:vpn_log, :ipsec}, 0.90}
      String.contains?(fname, "openvpn") -> {{:vpn_log, :openvpn}, 0.90}
      String.contains?(fname, "wireguard") -> {{:vpn_log, :wireguard}, 0.90}
      String.contains?(fname, "vpn") -> {{:vpn_log, :generic}, 0.75}

      # Network captures - file extensions are definitive
      String.ends_with?(fname, ".pcap") -> {{:capture, :pcap}, 0.95}
      String.ends_with?(fname, ".pcapng") -> {{:capture, :pcapng}, 0.95}
      String.contains?(fname, "wireshark") -> {{:capture, :wireshark_export}, 0.85}

      # Windows - specific extensions and commands
      String.ends_with?(fname, ".evtx") -> {{:os_log, :windows_evtx}, 0.95}
      String.contains?(fname, "ipconfig") -> {{:snapshot, :ipconfig}, 0.85}
      String.contains?(fname, "netstat") -> {{:snapshot, :netstat}, 0.85}
      String.contains?(fname, "tasklist") -> {{:snapshot, :tasklist}, 0.85}
      String.contains?(fname, "route") -> {{:snapshot, :routing_table}, 0.70}

      # Auth/SSO - protocol names are high confidence
      String.contains?(fname, "saml") -> {{:auth_log, :saml}, 0.85}
      String.contains?(fname, "oauth") -> {{:auth_log, :oauth}, 0.85}
      String.contains?(fname, "sso") -> {{:auth_log, :sso}, 0.80}
      String.contains?(fname, "auth") -> {{:auth_log, :generic}, 0.70}

      # Browser - HAR is definitive
      String.ends_with?(fname, ".har") -> {{:browser, :har}, 0.95}

      # DNS
      String.contains?(fname, "dns") -> {{:network, :dns}, 0.75}

      # Firewall
      String.contains?(fname, "firewall") -> {{:security, :firewall}, 0.80}
      String.contains?(fname, "fw") -> {{:security, :firewall}, 0.60}

      # Generic app logs - extension tells us it's a log, but not what kind
      String.ends_with?(fname, ".log") -> {{:application_log, :generic}, 0.50}
      String.ends_with?(fname, ".txt") -> {{:unknown, :text_file}, 0.35}

      true -> {{:unknown, :unrecognized}, 0.30}
    end
  end

  # Content-based detection - returns {type, confidence}
  # Confidence based on pattern specificity:
  #   0.90+ - unique structural markers (wireshark headers, windows command output)
  #   0.80  - clear format (JSON)
  #   0.70  - keyword density (VPN, auth)
  #   0.45  - generic patterns (timestamps)
  #   0.30  - fallback (freeform)
  defp detect_from_content(sample, full_content) do
    first_lines = Enum.take(sample, 10) |> Enum.join("\n")

    cond do
      # Structured formats first - clear structural signal
      json_log?(first_lines) -> {{:structured, :json}, 0.85}

      # Wireshark CSV export - very specific headers
      wireshark_csv?(first_lines) -> {{:capture, :wireshark_csv}, 0.92}

      # Windows snapshots - specific command output headers
      ipconfig?(first_lines) -> {{:snapshot, :ipconfig}, 0.90}
      netstat?(first_lines) -> {{:snapshot, :netstat}, 0.90}
      routing_table?(first_lines) -> {{:snapshot, :routing_table}, 0.88}
      tasklist?(first_lines) -> {{:snapshot, :tasklist}, 0.85}
      dns_cache?(first_lines) -> {{:snapshot, :dns_cache}, 0.88}

      # VPN patterns - confidence based on keyword density
      true ->
        vpn_score = vpn_keyword_score(full_content)
        auth_score = auth_keyword_score(full_content)

        cond do
          vpn_score >= 4 -> {{:vpn_log, :session}, 0.80}
          vpn_score >= 2 -> {{:vpn_log, :session}, 0.65}
          auth_score >= 4 -> {{:auth_log, :generic}, 0.75}
          auth_score >= 2 -> {{:auth_log, :generic}, 0.60}
          has_timestamps?(sample) -> {{:application_log, :timestamped}, 0.45}
          true -> {{:unknown, :freeform}, 0.30}
        end
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

  # Returns keyword match count for confidence calculation
  defp vpn_keyword_score(text) do
    vpn_keywords = ["tunnel", "IKE", "IPSEC", "VPN", "peer", "handshake",
                    "phase1", "phase2", "established", "negotiation"]
    Enum.count(vpn_keywords, &String.contains?(String.downcase(text), String.downcase(&1)))
  end

  # Returns keyword match count for confidence calculation
  defp auth_keyword_score(text) do
    auth_keywords = ["login", "logout", "authentication", "authorized",
                     "denied", "token", "session", "credential"]
    Enum.count(auth_keywords, &String.contains?(String.downcase(text), String.downcase(&1)))
  end

  defp has_timestamps?(sample) do
    timestamp_pattern = ~r/\d{4}[-\/]\d{2}[-\/]\d{2}|\d{2}:\d{2}:\d{2}|\d{10,13}/
    Enum.any?(sample, &Regex.match?(timestamp_pattern, &1))
  end

  # ============================================================================
  # Format Detection - What structure does it have?
  # ============================================================================

  # Format detection - returns {format, confidence}
  # Confidence based on structural consistency:
  #   0.90+ - all lines match pattern perfectly (JSON, CSV with many columns)
  #   0.80  - strong pattern match (tabular, TSV)
  #   0.70  - good pattern match (key-value)
  #   0.40  - freeform/unstructured
  defp detect_format(sample) do
    first_lines = Enum.take(sample, 5)

    # Check each format and return with confidence
    json_conf = json_confidence(first_lines)
    kv_conf = key_value_confidence(first_lines)
    tabular_conf = tabular_confidence(first_lines)
    csv_conf = delimiter_confidence(first_lines, ",")
    tsv_conf = delimiter_confidence(first_lines, "\t")

    # Pick the highest confidence format
    candidates = [
      {:json, json_conf},
      {:key_value, kv_conf},
      {:tabular, tabular_conf},
      {:csv, csv_conf},
      {:tsv, tsv_conf}
    ]

    {best_format, best_conf} = Enum.max_by(candidates, fn {_, conf} -> conf end)

    # If best confidence is too low, call it freeform
    if best_conf >= 0.5 do
      {best_format, best_conf}
    else
      {:freeform, 0.40}
    end
  end

  defp json_confidence(lines) when length(lines) == 0, do: 0.0
  defp json_confidence(lines) do
    json_lines = Enum.count(lines, fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[")
    end)

    ratio = json_lines / length(lines)
    # Scale: 100% match = 0.92, 80% = 0.75, below 60% = too low
    if ratio >= 0.6, do: 0.5 + ratio * 0.42, else: 0.0
  end

  defp key_value_confidence(lines) when length(lines) == 0, do: 0.0
  defp key_value_confidence(lines) do
    kv_pattern = ~r/^\s*[\w\.-]+\s*[=:]\s*.+/
    match_ratio = Enum.count(lines, &Regex.match?(kv_pattern, &1)) / length(lines)

    # Scale: 90%+ = 0.82, 70% = 0.65, below 50% = too low
    if match_ratio >= 0.5, do: 0.4 + match_ratio * 0.45, else: 0.0
  end

  defp tabular_confidence(lines) when length(lines) < 2, do: 0.0
  defp tabular_confidence(lines) do
    # Check if lines have consistent column-like structure
    widths = Enum.map(lines, &String.length/1)
    avg_width = Enum.sum(widths) / length(widths)
    variance = Enum.sum(Enum.map(widths, fn w -> :math.pow(w - avg_width, 2) end)) / length(widths)

    has_columns = Enum.all?(lines, &String.contains?(&1, "  "))

    cond do
      # Very consistent widths + column separators = high confidence
      variance < 25 and has_columns -> 0.85
      variance < 100 and has_columns -> 0.70
      variance < 200 and has_columns -> 0.55
      true -> 0.0
    end
  end

  defp delimiter_confidence(lines, _delimiter) when length(lines) < 2, do: 0.0
  defp delimiter_confidence(lines, delimiter) do
    counts = Enum.map(lines, fn line ->
      length(String.split(line, delimiter)) - 1
    end)

    first = hd(counts)
    all_consistent = Enum.all?(counts, &(&1 == first))

    cond do
      # Many columns + all consistent = very high confidence
      first >= 5 and all_consistent -> 0.90
      first >= 3 and all_consistent -> 0.82
      first >= 2 and all_consistent -> 0.70
      true -> 0.0
    end
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

  # Sample size for temperature detection
  @temp_sample_size 500

  # Returns {temperature, temperature_score, signal_quality}
  # signal_quality: 0.0-1.0 indicating how reliable our temperature reading is
  defp detect_temperature(lines) do
    total = length(lines)

    if total == 0 do
      {:unknown, 0.5, 0.30}
    else
      # Sample for large files to improve performance
      sampled = if total > @temp_sample_size do
        sample_for_temperature(lines, @temp_sample_size)
      else
        lines
      end
      sample_total = length(sampled)

      # Use weighted scoring - log level indicators count more than mentions
      # Now also track strong signal counts for quality calculation
      {error_score, error_strong} = score_error_signals_detailed(sampled)
      {warning_score, warning_strong} = score_warning_signals_detailed(sampled)
      {success_score, success_strong} = score_success_signals_detailed(sampled)

      # Normalize by sampled line count
      error_ratio = error_score / sample_total
      warning_ratio = warning_score / sample_total
      success_ratio = success_score / sample_total

      # Calculate signal quality based on:
      # 1. What proportion of signals are strong (log levels vs weak keywords)
      # 2. Signal density (what % of lines have any signal)
      total_signals = error_score + warning_score + success_score
      strong_signals = error_strong + warning_strong + success_strong

      signal_quality = calculate_signal_quality(
        total_signals,
        strong_signals,
        sample_total
      )

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

      {temperature, Float.round(temperature_score, 3), Float.round(signal_quality, 2)}
    end
  end

  # Calculate how reliable our temperature signals are
  # High quality = many strong signals (log levels, status codes)
  # Low quality = only weak signals (keyword mentions) or very few signals
  defp calculate_signal_quality(total_signals, strong_signals, sample_size) do
    if total_signals == 0 do
      # No signals at all - we're guessing based on absence
      0.35
    else
      # Signal density: what proportion of lines had any signal
      density = min(total_signals / sample_size, 1.0)

      # Signal strength: proportion of strong signals
      strength_ratio = strong_signals / total_signals

      # Combine: density matters but strength matters more
      # - Dense strong signals: high quality
      # - Sparse strong signals: medium quality
      # - Dense weak signals: medium-low quality
      # - Sparse weak signals: low quality
      base_quality = strength_ratio * 0.6 + density * 0.4

      # Boost if we have both good density AND strong signals
      boost = if density > 0.1 and strength_ratio > 0.5, do: 0.15, else: 0.0

      clamp(base_quality + boost, 0.35, 0.95)
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)

  # Sample from start, middle, and end for representative coverage
  defp sample_for_temperature(lines, size) do
    total = length(lines)
    chunk = div(size, 3)

    start_chunk = Enum.take(lines, chunk)
    middle_start = div(total, 2) - div(chunk, 2)
    middle_chunk = lines |> Enum.drop(middle_start) |> Enum.take(chunk)
    end_chunk = Enum.take(lines, -chunk)

    start_chunk ++ middle_chunk ++ end_chunk
  end

  # ============================================================================
  # Weighted Signal Scoring
  # ============================================================================

  # Strong indicators: log level markers, structured severity fields
  # Weak indicators: keyword mentions that might be values or descriptions

  # Detailed versions return {total_score, strong_signal_count}
  # Used for calculating signal quality
  defp score_error_signals_detailed(lines) do
    Enum.reduce(lines, {0.0, 0}, fn line, {score_acc, strong_acc} ->
      {score, is_strong} = score_line_for_error_detailed(line)
      {score_acc + score, if(is_strong, do: strong_acc + 1, else: strong_acc)}
    end)
  end

  defp score_warning_signals_detailed(lines) do
    Enum.reduce(lines, {0.0, 0}, fn line, {score_acc, strong_acc} ->
      {score, is_strong} = score_line_for_warning_detailed(line)
      {score_acc + score, if(is_strong, do: strong_acc + 1, else: strong_acc)}
    end)
  end

  defp score_success_signals_detailed(lines) do
    Enum.reduce(lines, {0.0, 0}, fn line, {score_acc, strong_acc} ->
      {score, is_strong} = score_line_for_success_detailed(line)
      {score_acc + score, if(is_strong, do: strong_acc + 1, else: strong_acc)}
    end)
  end

  # Returns {score, is_strong_signal}
  defp score_line_for_error_detailed(line) do
    cond do
      is_error_level?(line) -> {1.0, true}
      has_http_error_status?(line) -> {1.0, true}
      has_contextual_error?(line) -> {0.5, false}
      has_weak_error_mention?(line) -> {0.1, false}
      true -> {0.0, false}
    end
  end

  defp score_line_for_warning_detailed(line) do
    cond do
      is_warning_level?(line) -> {1.0, true}
      has_contextual_warning?(line) -> {0.5, false}
      Regex.match?(~r/\b(warn|warning|caution|deprecated)\b/i, line) -> {0.1, false}
      true -> {0.0, false}
    end
  end

  defp score_line_for_success_detailed(line) do
    cond do
      is_success_level?(line) -> {1.0, true}
      has_contextual_success?(line) -> {0.5, false}
      true -> {0.0, false}
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
