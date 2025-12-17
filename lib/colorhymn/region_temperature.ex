defmodule Colorhymn.RegionTemperature do
  @moduledoc """
  Per-region temperature calculation.

  Each region type has its own temperature source:
  - Timestamp: Temporal density, acceleration, gaps
  - Log level: Semantic mapping (FATAL=hot, DEBUG=cool)
  - Message: Content analysis
  - Component/Bracket: Context inheritance
  """

  alias Colorhymn.RegionTemperature.TemporalContext
  alias Colorhymn.Structure.Region

  # ============================================================================
  # Temporal Context
  # ============================================================================

  defmodule TemporalContext do
    @moduledoc """
    Tracks temporal patterns across log lines for timestamp temperature.
    """

    @type t :: %__MODULE__{
            recent_timestamps: [DateTime.t()],
            recent_deltas: [float()],
            current_density: float(),
            density_trend: :stable | :accelerating | :decelerating,
            last_timestamp: DateTime.t() | nil,
            window_size: pos_integer()
          }

    defstruct [
      recent_timestamps: [],
      recent_deltas: [],
      current_density: 0.0,
      density_trend: :stable,
      last_timestamp: nil,
      window_size: 20
    ]

    @doc """
    Create a new temporal context.
    """
    def new(opts \\ []) do
      %__MODULE__{
        window_size: Keyword.get(opts, :window_size, 20)
      }
    end

    @doc """
    Update context with a new timestamp.
    Returns {updated_context, delta_seconds}.
    """
    def update(%__MODULE__{} = ctx, timestamp) when is_binary(timestamp) do
      case parse_timestamp(timestamp) do
        {:ok, dt} -> update_with_datetime(ctx, dt)
        :error -> {ctx, nil}
      end
    end

    def update(%__MODULE__{} = ctx, nil), do: {ctx, nil}

    defp update_with_datetime(%__MODULE__{} = ctx, dt) do
      delta =
        case ctx.last_timestamp do
          nil -> nil
          last -> DateTime.diff(dt, last, :millisecond) / 1000.0
        end

      # Update timestamps window
      new_timestamps =
        [dt | ctx.recent_timestamps]
        |> Enum.take(ctx.window_size)

      # Update deltas window
      new_deltas =
        case delta do
          nil -> ctx.recent_deltas
          d when d >= 0 -> [d | ctx.recent_deltas] |> Enum.take(ctx.window_size - 1)
          # Negative delta (time went backward) - ignore
          _ -> ctx.recent_deltas
        end

      # Calculate current density
      density = calculate_density(new_deltas)

      # Determine trend
      trend = calculate_trend(new_deltas, ctx.recent_deltas)

      new_ctx = %{
        ctx
        | recent_timestamps: new_timestamps,
          recent_deltas: new_deltas,
          current_density: density,
          density_trend: trend,
          last_timestamp: dt
      }

      {new_ctx, delta}
    end

    defp calculate_density([]), do: 0.0

    defp calculate_density(deltas) do
      avg_delta = Enum.sum(deltas) / length(deltas)

      if avg_delta > 0 do
        1.0 / avg_delta
      else
        10.0
      end
    end

    defp calculate_trend(new_deltas, old_deltas) when length(new_deltas) >= 3 and length(old_deltas) >= 3 do
      new_avg = Enum.sum(Enum.take(new_deltas, 3)) / 3
      old_avg = Enum.sum(Enum.take(old_deltas, 3)) / 3

      cond do
        new_avg < old_avg * 0.7 -> :accelerating
        new_avg > old_avg * 1.3 -> :decelerating
        true -> :stable
      end
    end

    defp calculate_trend(_, _), do: :stable

    defp parse_timestamp(str) do
      str = String.trim(str)

      cond do
        # Try ISO/common format first
        match = Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})[T\s](\d{2}):(\d{2}):(\d{2})/, str) ->
          [_, y, m, d, h, min, s] = match

          case DateTime.new(
                 Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d)),
                 Time.new!(String.to_integer(h), String.to_integer(min), String.to_integer(s))
               ) do
            {:ok, dt} -> {:ok, dt}
            _ -> :error
          end

        # Syslog format (assume current year)
        match = Regex.run(~r/^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})/, str) ->
          [_, month_str, d, h, min, s] = match
          month = month_to_num(month_str)
          year = Date.utc_today().year

          case DateTime.new(
                 Date.new!(year, month, String.to_integer(d)),
                 Time.new!(String.to_integer(h), String.to_integer(min), String.to_integer(s))
               ) do
            {:ok, dt} -> {:ok, dt}
            _ -> :error
          end

        true ->
          :error
      end
    end

    defp month_to_num("Jan"), do: 1
    defp month_to_num("Feb"), do: 2
    defp month_to_num("Mar"), do: 3
    defp month_to_num("Apr"), do: 4
    defp month_to_num("May"), do: 5
    defp month_to_num("Jun"), do: 6
    defp month_to_num("Jul"), do: 7
    defp month_to_num("Aug"), do: 8
    defp month_to_num("Sep"), do: 9
    defp month_to_num("Oct"), do: 10
    defp month_to_num("Nov"), do: 11
    defp month_to_num("Dec"), do: 12
  end

  # ============================================================================
  # Main API
  # ============================================================================

  @doc """
  Initialize a new calculation context.
  """
  def init_context(opts \\ []) do
    TemporalContext.new(opts)
  end

  @doc """
  Calculate temperatures for all regions in a line.
  Returns {region_temps_map, new_context}.

  The map keys are region types (:timestamp, :log_level, :message, etc.)
  and values are temperature scores (0.0 to 1.0).
  """
  def calculate_line(regions, context) when is_list(regions) do
    {temps, new_context} =
      Enum.reduce(regions, {%{}, context}, fn region, {temps_acc, ctx} ->
        {temp, new_ctx} = calculate_region_temp(region, ctx)
        {Map.put(temps_acc, region.type, temp), new_ctx}
      end)

    {temps, new_context}
  end

  @doc """
  Calculate temperature for a single region.
  Returns {temperature, updated_context}.
  """
  def calculate_region_temp(%Region{type: :timestamp} = region, context) do
    calculate_timestamp_temperature(region.value, context)
  end

  def calculate_region_temp(%Region{type: :log_level} = region, context) do
    level = Map.get(region.metadata, :level, :unknown)
    {calculate_log_level_temperature(level), context}
  end

  def calculate_region_temp(%Region{type: :message} = region, context) do
    {calculate_message_temperature(region.value), context}
  end

  def calculate_region_temp(%Region{type: :key_value} = region, context) do
    {calculate_key_value_temperature(region), context}
  end

  def calculate_region_temp(%Region{type: _other}, context) do
    # Component, bracket, whitespace - inherit base temperature
    {0.4, context}
  end

  # ============================================================================
  # Timestamp Temperature
  # ============================================================================

  @doc """
  Calculate timestamp temperature based on temporal density.

  Temperature effects:
  - Dense bursts (>5 events/sec) → 0.85+ (urgent)
  - Sparse gaps (>60s silence) → 0.55-0.65 (ominous)
  - Regular rhythm → 0.35-0.45 (stable)
  - Acceleration → +0.1 to +0.2
  """
  def calculate_timestamp_temperature(timestamp_value, context) do
    {new_context, delta} = TemporalContext.update(context, timestamp_value)

    base_temp =
      cond do
        # Very dense burst
        new_context.current_density > 5.0 ->
          0.85 + min(0.1, (new_context.current_density - 5) / 50)

        # Dense activity
        new_context.current_density > 1.0 ->
          0.65 + (new_context.current_density - 1) / 20

        # Normal activity
        new_context.current_density > 0.1 ->
          0.4 + new_context.current_density * 0.25

        # Sparse (potentially ominous gap)
        new_context.current_density > 0.01 ->
          0.55

        # Very sparse / initial
        true ->
          0.35
      end

    # Apply trend modifier
    trend_mod =
      case new_context.density_trend do
        :accelerating -> 0.15
        :decelerating -> -0.05
        :stable -> 0.0
      end

    # Apply large gap modifier
    gap_mod =
      case delta do
        nil -> 0.0
        d when d > 60.0 -> 0.1
        d when d > 30.0 -> 0.05
        _ -> 0.0
      end

    temp = base_temp + trend_mod + gap_mod
    {clamp(temp, 0.1, 0.95), new_context}
  end

  # ============================================================================
  # Log Level Temperature
  # ============================================================================

  @doc """
  Calculate temperature from log level semantics.

  Mapping:
  - FATAL/CRITICAL → 0.98
  - ERROR → 0.85
  - WARNING → 0.65
  - INFO → 0.40
  - DEBUG → 0.25
  - TRACE → 0.15
  """
  def calculate_log_level_temperature(level) when is_atom(level) do
    case level do
      :fatal -> 0.98
      :critical -> 0.95
      :error -> 0.85
      :warning -> 0.65
      :warn -> 0.65
      :info -> 0.40
      :debug -> 0.25
      :trace -> 0.15
      _ -> 0.40
    end
  end

  def calculate_log_level_temperature(_), do: 0.40

  # ============================================================================
  # Message Temperature
  # ============================================================================

  @critical_patterns ~w(fatal panic crash abort segfault oom killed terminated)
  @error_patterns ~w(error fail failed failure exception refused denied invalid timeout)
  @warning_patterns ~w(warn warning deprecated slow retry retrying missing unavailable)
  @success_patterns ~w(success successful completed done finished started ready connected)
  @neutral_patterns ~w(info processing checking loading waiting)

  @doc """
  Calculate temperature from message content analysis.
  Uses pattern matching for error indicators, success indicators, etc.
  """
  def calculate_message_temperature(text) when is_binary(text) do
    text_lower = String.downcase(text)

    # Count indicators
    critical_count = count_patterns(text_lower, @critical_patterns)
    error_count = count_patterns(text_lower, @error_patterns)
    warning_count = count_patterns(text_lower, @warning_patterns)
    success_count = count_patterns(text_lower, @success_patterns)
    neutral_count = count_patterns(text_lower, @neutral_patterns)

    # Calculate weighted score
    score =
      critical_count * 0.95 +
        error_count * 0.75 +
        warning_count * 0.55 +
        success_count * 0.25 +
        neutral_count * 0.35

    total_matches = critical_count + error_count + warning_count + success_count + neutral_count

    if total_matches > 0 do
      clamp(score / total_matches, 0.2, 0.9)
    else
      0.4
    end
  end

  def calculate_message_temperature(_), do: 0.4

  defp count_patterns(text, patterns) do
    Enum.count(patterns, &String.contains?(text, &1))
  end

  # ============================================================================
  # Key-Value Temperature
  # ============================================================================

  @doc """
  Calculate temperature from key-value content.
  Certain keys/values indicate temperature.
  """
  def calculate_key_value_temperature(%Region{metadata: %{key: key, value: value}}) do
    key_lower = String.downcase(key)
    value_lower = String.downcase(to_string(value))

    cond do
      # Error-related keys
      key_lower in ~w(error err status code exit_code) and
          value_lower in ~w(error fail failed 1 -1 500 502 503 504) ->
        0.8

      # Status success
      key_lower in ~w(status state result) and value_lower in ~w(ok success 0 200 201 204) ->
        0.3

      # Duration/latency (high values = hot)
      key_lower in ~w(duration latency elapsed time_ms) ->
        parse_duration_temp(value)

      # Count/retry (high = concerning)
      key_lower in ~w(retry retries attempts count errors) ->
        parse_count_temp(value)

      true ->
        0.4
    end
  end

  def calculate_key_value_temperature(_), do: 0.4

  defp parse_duration_temp(value) do
    case Float.parse(to_string(value)) do
      {ms, _} when ms > 5000 -> 0.8
      {ms, _} when ms > 1000 -> 0.6
      {ms, _} when ms > 100 -> 0.45
      {_, _} -> 0.35
      :error -> 0.4
    end
  end

  defp parse_count_temp(value) do
    case Integer.parse(to_string(value)) do
      {n, _} when n > 5 -> 0.75
      {n, _} when n > 2 -> 0.6
      {n, _} when n > 0 -> 0.5
      {0, _} -> 0.35
      _ -> 0.4
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Blend multiple region temperatures into a line temperature.
  Uses weighted average with log_level having highest weight.
  """
  def blend_region_temps(region_temps) when is_map(region_temps) do
    weights = %{
      log_level: 3.0,
      message: 2.0,
      timestamp: 1.0,
      key_value: 1.5
    }

    {weighted_sum, total_weight} =
      Enum.reduce(region_temps, {0.0, 0.0}, fn {type, temp}, {sum, weight} ->
        w = Map.get(weights, type, 0.5)
        {sum + temp * w, weight + w}
      end)

    if total_weight > 0 do
      weighted_sum / total_weight
    else
      0.4
    end
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end
end
