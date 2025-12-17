defmodule Colorhymn.Flow do
  @moduledoc """
  Windowed temperature analysis for logs.

  Instead of a single temperature for the whole log, calculates
  local temperature at each position using sliding window sampling.
  This captures how a log's "mood" shifts over time - from calm startup
  through crisis and back to recovery.

  Uses sampling for efficiency: doesn't read every line, just samples
  within each window to estimate local temperature.

  ## Region-Aware Analysis

  The `analyze_with_regions/2` function provides per-region temperature
  calculation, where each structural region (timestamp, log_level, message, etc.)
  gets its own temperature based on its semantic content.
  """

  alias Colorhymn.Structure
  alias Colorhymn.RegionTemperature

  # Window radius - look at N lines before and after current position
  @default_window_radius 20

  # Sample rate - check every Nth line in window (1 = all, 3 = every 3rd)
  @default_sample_rate 3

  # How often to calculate temperature (sample every Nth line, interpolate rest)
  @default_calc_interval 5

  @doc """
  Analyze temperature flow across a log.

  Returns a list of {temperature_score, temperature_atom} for each line,
  representing the local "heat" at that position.

  Options:
    - window_radius: lines to consider on each side (default: 20)
    - sample_rate: sample every Nth line in window (default: 3)
    - calc_interval: calculate every Nth line, interpolate rest (default: 5)
  """
  def analyze(lines, opts \\ []) do
    total = length(lines)

    if total < 5 do
      # Too short for windowing - use single temperature
      {temp, score} = detect_temperature(lines)
      List.duplicate({score, temp}, total)
    else
      window_radius = Keyword.get(opts, :window_radius, @default_window_radius)
      sample_rate = Keyword.get(opts, :sample_rate, @default_sample_rate)
      calc_interval = Keyword.get(opts, :calc_interval, @default_calc_interval)

      # Calculate temperature at sample points
      lines_array = :array.from_list(lines)

      sample_indices = 0..(total - 1)
        |> Enum.take_every(calc_interval)

      sample_scores = Enum.map(sample_indices, fn idx ->
        window = get_window_sampled(lines_array, idx, total, window_radius, sample_rate)
        {_temp, score} = detect_temperature(window)
        {idx, score}
      end)

      # Interpolate between sample points for all lines
      interpolate_scores(sample_scores, total)
    end
  end

  @doc """
  Get just the temperature scores as a list (one per line).
  """
  def scores(lines, opts \\ []) do
    lines
    |> analyze(opts)
    |> Enum.map(fn {score, _temp} -> score end)
  end

  # ============================================================================
  # Region-Aware Analysis
  # ============================================================================

  @doc """
  Analyze with structural region detection and per-region temperatures.

  Returns a list of maps, one per line, containing:
    - `:line` - the original line text
    - `:line_temp` - overall line temperature {score, atom}
    - `:regions` - list of Region structs
    - `:region_temps` - map of region_type => temperature score
    - `:group` - group information if part of multi-line group

  Options:
    - Same as `analyze/2` plus:
    - `:include_groups` - include multi-line group detection (default: true)
  """
  def analyze_with_regions(lines, opts \\ []) when is_list(lines) do
    include_groups = Keyword.get(opts, :include_groups, true)

    # Get windowed line temperatures
    line_temps = analyze(lines, opts)

    # Analyze structure (regions and groups)
    groups = if include_groups, do: Structure.analyze(lines), else: nil

    # Initialize temporal context for timestamp temperature tracking
    initial_context = RegionTemperature.init_context()

    # Process each line with region temperatures
    {results, _final_context} =
      lines
      |> Enum.with_index()
      |> Enum.map_reduce(initial_context, fn {line, idx}, temp_ctx ->
        # Get regions for this line
        regions = Structure.analyze_line(line)

        # Calculate per-region temperatures
        {region_temps, new_ctx} = RegionTemperature.calculate_line(regions, temp_ctx)

        # Get overall line temperature from windowed analysis
        {line_score, _line_temp} = Enum.at(line_temps, idx)

        # Blend region temps with windowed score for final line score
        blended_score = blend_with_regions(line_score, region_temps)
        blended_temp = score_to_temperature(blended_score)

        # Find group info if applicable
        group_info = if groups, do: find_group_for_line(groups, idx), else: nil

        result = %{
          line: line,
          line_num: idx,
          line_temp: {blended_score, blended_temp},
          regions: regions,
          region_temps: region_temps,
          group: group_info
        }

        {result, new_ctx}
      end)

    results
  end

  @doc """
  Analyze with regions but return simplified output (just temps and regions).
  """
  def analyze_regions_simple(lines, opts \\ []) do
    lines
    |> analyze_with_regions(opts)
    |> Enum.map(fn result ->
      %{
        temp: result.line_temp,
        region_temps: result.region_temps,
        regions: Enum.map(result.regions, &{&1.type, &1.value})
      }
    end)
  end

  # Blend windowed line temperature with region-specific temperatures
  defp blend_with_regions(line_score, region_temps) when map_size(region_temps) == 0 do
    line_score
  end

  defp blend_with_regions(line_score, region_temps) do
    region_blend = RegionTemperature.blend_region_temps(region_temps)

    # 60% windowed context, 40% region-specific
    line_score * 0.6 + region_blend * 0.4
  end

  defp find_group_for_line(groups, line_idx) do
    case Enum.find(groups, fn g -> line_idx >= g.start_line and line_idx <= g.end_line end) do
      nil ->
        nil

      group ->
        %{
          type: group.type,
          start_line: group.start_line,
          end_line: group.end_line,
          line_count: length(group.lines)
        }
    end
  end

  # ============================================================================
  # Window Sampling
  # ============================================================================

  # Get a sampled window of lines around the given index
  defp get_window_sampled(lines_array, center_idx, total, radius, sample_rate) do
    start_idx = max(0, center_idx - radius)
    end_idx = min(total - 1, center_idx + radius)

    start_idx..end_idx
    |> Enum.take_every(sample_rate)
    |> Enum.map(&:array.get(&1, lines_array))
  end

  # ============================================================================
  # Interpolation
  # ============================================================================

  # Interpolate scores between sample points
  defp interpolate_scores(sample_scores, total) do
    # Build a map of index -> score for sample points
    sample_map = Map.new(sample_scores)

    # For each line, find surrounding sample points and interpolate
    Enum.map(0..(total - 1), fn idx ->
      score = case Map.get(sample_map, idx) do
        nil ->
          # Find surrounding sample points
          {lower_idx, lower_score} = find_lower_sample(sample_scores, idx)
          {upper_idx, upper_score} = find_upper_sample(sample_scores, idx)

          if lower_idx == upper_idx do
            lower_score
          else
            # Linear interpolation
            t = (idx - lower_idx) / (upper_idx - lower_idx)
            lower_score + (upper_score - lower_score) * t
          end

        score ->
          score
      end

      temp = score_to_temperature(score)
      {score, temp}
    end)
  end

  defp find_lower_sample(samples, idx) do
    samples
    |> Enum.filter(fn {i, _} -> i <= idx end)
    |> List.last()
    |> case do
      nil -> hd(samples)
      found -> found
    end
  end

  defp find_upper_sample(samples, idx) do
    samples
    |> Enum.find(fn {i, _} -> i >= idx end)
    |> case do
      nil -> List.last(samples)
      found -> found
    end
  end

  defp score_to_temperature(score) do
    cond do
      score > 0.8 -> :critical
      score > 0.6 -> :troubled
      score > 0.45 -> :uneasy
      score < 0.3 -> :calm
      true -> :neutral
    end
  end

  # ============================================================================
  # Temperature Detection (adapted from FirstSight)
  # ============================================================================

  defp detect_temperature(lines) do
    total = length(lines)

    if total == 0 do
      {:unknown, 0.5}
    else
      error_score = score_error_signals(lines)
      warning_score = score_warning_signals(lines)
      success_score = score_success_signals(lines)

      error_ratio = error_score / total
      warning_ratio = warning_score / total
      success_ratio = success_score / total

      base_temp = cond do
        success_ratio > 0.5 and error_ratio == 0 -> 0.15 + (1 - success_ratio) * 0.3
        error_ratio == 0 and warning_ratio < 0.1 -> 0.35
        error_ratio == 0 -> 0.35 + min(warning_ratio * 1.5, 0.2)
        true -> 0.35 + error_ratio * 4.0
      end

      warning_heat = if error_ratio > 0, do: warning_ratio * 0.5, else: 0
      cooling = success_ratio * 0.15

      temperature_score = clamp(base_temp + warning_heat - cooling, 0.0, 0.95)

      temperature = score_to_temperature(temperature_score)

      {temperature, Float.round(temperature_score, 3)}
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)

  # ============================================================================
  # Signal Scoring (simplified from FirstSight for efficiency)
  # ============================================================================

  defp score_error_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      cond do
        is_error_level?(line) -> acc + 1.0
        has_http_error_status?(line) -> acc + 1.0
        has_contextual_error?(line) -> acc + 0.5
        has_weak_error_mention?(line) -> acc + 0.1
        true -> acc
      end
    end)
  end

  defp is_error_level?(line) do
    Regex.match?(~r/\[(ERROR|FATAL|CRITICAL|SEVERE)\]/i, line) or
    Regex.match?(~r/\b(ERROR|FATAL|CRITICAL|SEVERE)\s*[:\-\|]/i, line) or
    Regex.match?(~r/\d{2}:\d{2}:\d{2}[.,]?\d*\s+(ERROR|FATAL|CRITICAL)/i, line)
  end

  defp has_http_error_status?(line) do
    Regex.match?(~r/\bHTTP\/\d\.?\d?\s+[45]\d{2}\b/, line)
  end

  defp has_contextual_error?(line) do
    Regex.match?(~r/\b(failed|error|exception|failure)\s+(to|in|on|at|while|occurred)/i, line) or
    Regex.match?(~r/\b(connection|request|operation)\s+(refused|denied|timeout|failed)/i, line) or
    Regex.match?(~r/\b(cannot|couldn't|could not|unable to|failed to)\b/i, line)
  end

  defp has_weak_error_mention?(line) do
    Regex.match?(~r/\b(error|fail|failed|failure|exception|denied|refused|timeout)\b/i, line)
  end

  defp score_warning_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      cond do
        is_warning_level?(line) -> acc + 1.0
        has_contextual_warning?(line) -> acc + 0.5
        Regex.match?(~r/\b(warn|warning)\b/i, line) -> acc + 0.1
        true -> acc
      end
    end)
  end

  defp is_warning_level?(line) do
    Regex.match?(~r/\[(WARN|WARNING)\]/i, line) or
    Regex.match?(~r/\b(WARN|WARNING)\s*[:\-\|]/i, line) or
    Regex.match?(~r/\d{2}:\d{2}:\d{2}[.,]?\d*\s+(WARN|WARNING)/i, line)
  end

  defp has_contextual_warning?(line) do
    Regex.match?(~r/\b(deprecated|retry|retrying|slow|degraded|high\s+latency)\b/i, line)
  end

  defp score_success_signals(lines) do
    Enum.reduce(lines, 0.0, fn line, acc ->
      cond do
        is_success_level?(line) -> acc + 1.0
        has_contextual_success?(line) -> acc + 0.5
        true -> acc
      end
    end)
  end

  defp is_success_level?(line) do
    Regex.match?(~r/\[(INFO|SUCCESS|OK)\]/i, line) or
    Regex.match?(~r/\bHTTP\/\d\.?\d?\s+2\d{2}\b/, line)
  end

  defp has_contextual_success?(line) do
    Regex.match?(~r/\b(successfully|succeeded|completed|established|connected|ready)\b/i, line)
  end
end
