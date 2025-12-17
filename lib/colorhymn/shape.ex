defmodule Colorhymn.Shape do
  @moduledoc """
  Continuous shape representation for log temporal/structural patterns.

  All scores are floats from 0.0 to 1.0 (or -1.0 to 1.0 for acceleration).
  """

  defstruct [
    burstiness: 0.5,      # 0 = sparse (long gaps), 1 = bursty (rapid fire)
    regularity: 0.5,      # 0 = erratic (chaotic), 1 = periodic (clockwork)
    acceleration: 0.0,    # -1 = decelerating, 0 = steady, +1 = accelerating
    concentration: 0.5,   # 0 = front-loaded, 0.5 = uniform, 1 = back-loaded
    entropy: 0.5          # 0 = predictable/monotonous, 1 = high variation
  ]

  @type t :: %__MODULE__{
    burstiness: float(),
    regularity: float(),
    acceleration: float(),
    concentration: float(),
    entropy: float()
  }

  @doc """
  Analyze a list of timestamps and produce a continuous shape profile.

  Timestamps should be floats representing seconds (with sub-second precision).
  """
  def from_timestamps(timestamps) when length(timestamps) < 3 do
    # Not enough data - return neutral shape
    %__MODULE__{}
  end

  def from_timestamps(timestamps) do
    sorted = Enum.sort(timestamps)
    deltas = compute_deltas(sorted)

    %__MODULE__{
      burstiness: compute_burstiness(deltas),
      regularity: compute_regularity(deltas),
      acceleration: compute_acceleration(deltas),
      concentration: compute_concentration(sorted),
      entropy: compute_entropy(deltas)
    }
  end

  @doc """
  Analyze shape from lines when no timestamps are available.
  Uses structural signals instead of temporal ones.
  """
  def from_lines(lines) when length(lines) < 3 do
    %__MODULE__{}
  end

  def from_lines(lines) do
    line_lengths = Enum.map(lines, &String.length/1)

    %__MODULE__{
      burstiness: 0.5,  # Can't determine without timestamps
      regularity: compute_length_regularity(line_lengths),
      acceleration: 0.0,  # Can't determine without timestamps
      concentration: 0.5,  # Uniform assumption
      entropy: compute_length_entropy(line_lengths)
    }
  end

  # ============================================================================
  # Delta computation
  # ============================================================================

  defp compute_deltas(sorted_timestamps) do
    sorted_timestamps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
    |> Enum.reject(&(&1 <= 0))
  end

  # ============================================================================
  # Burstiness: How rapid are the events?
  # ============================================================================

  defp compute_burstiness([]), do: 0.5
  defp compute_burstiness(deltas) do
    avg_delta = Enum.sum(deltas) / length(deltas)

    # Map delta to burstiness using sigmoid-like curve
    # < 0.1s = very bursty (0.95+)
    # ~ 1s = bursty (0.8)
    # ~ 10s = moderate (0.5)
    # ~ 60s = sparse (0.2)
    # > 300s = very sparse (0.05)
    cond do
      avg_delta < 0.1 -> 0.95 + (0.05 * (1 - avg_delta / 0.1))
      avg_delta < 1 -> 0.8 + (0.15 * (1 - avg_delta))
      avg_delta < 10 -> 0.5 + (0.3 * (1 - (avg_delta - 1) / 9))
      avg_delta < 60 -> 0.2 + (0.3 * (1 - (avg_delta - 10) / 50))
      avg_delta < 300 -> 0.05 + (0.15 * (1 - (avg_delta - 60) / 240))
      true -> 0.05
    end
    |> clamp(0.0, 1.0)
  end

  # ============================================================================
  # Regularity: How consistent is the rhythm?
  # ============================================================================

  defp compute_regularity([]), do: 0.5
  defp compute_regularity(deltas) when length(deltas) < 2, do: 0.5
  defp compute_regularity(deltas) do
    mean = Enum.sum(deltas) / length(deltas)

    # Coefficient of variation (std dev / mean)
    variance = Enum.sum(Enum.map(deltas, fn d -> :math.pow(d - mean, 2) end)) / length(deltas)
    std_dev = :math.sqrt(variance)
    cv = if mean > 0, do: std_dev / mean, else: 1.0

    # Low CV = high regularity
    # CV of 0 = perfect regularity (1.0)
    # CV of 0.5 = moderate (0.5)
    # CV of 1+ = erratic (approaching 0)
    regularity = 1.0 / (1.0 + cv)

    clamp(regularity, 0.0, 1.0)
  end

  # ============================================================================
  # Acceleration: Is the pace changing?
  # ============================================================================

  defp compute_acceleration([]), do: 0.0
  defp compute_acceleration(deltas) when length(deltas) < 4, do: 0.0
  defp compute_acceleration(deltas) do
    # Compare first quarter deltas to last quarter deltas
    n = length(deltas)
    quarter = max(div(n, 4), 1)

    first_quarter = Enum.take(deltas, quarter)
    last_quarter = Enum.take(deltas, -quarter)

    avg_first = Enum.sum(first_quarter) / length(first_quarter)
    avg_last = Enum.sum(last_quarter) / length(last_quarter)

    # If last deltas are smaller, we're accelerating (events getting faster)
    # If last deltas are larger, we're decelerating
    cond do
      avg_first == 0 and avg_last == 0 -> 0.0
      avg_first == 0 -> 1.0  # Started at zero, now has gaps = decel? Actually accelerating from nothing
      avg_last == 0 -> -1.0
      true ->
        ratio = avg_first / avg_last
        # ratio > 1 means first gaps were bigger, so we're accelerating
        # ratio < 1 means last gaps are bigger, so we're decelerating
        acceleration = (ratio - 1) / (ratio + 1)  # Normalize to -1..1
        clamp(acceleration, -1.0, 1.0)
    end
  end

  # ============================================================================
  # Concentration: Where is the mass of activity?
  # ============================================================================

  defp compute_concentration([]), do: 0.5
  defp compute_concentration(sorted_timestamps) when length(sorted_timestamps) < 2, do: 0.5
  defp compute_concentration(sorted_timestamps) do
    first = List.first(sorted_timestamps)
    last = List.last(sorted_timestamps)
    span = last - first

    if span == 0 do
      0.5
    else
      # Find the "center of mass" - median timestamp position relative to span
      n = length(sorted_timestamps)
      median_idx = div(n, 2)
      median_ts = Enum.at(sorted_timestamps, median_idx)

      # Where does median fall in the time span?
      concentration = (median_ts - first) / span

      clamp(concentration, 0.0, 1.0)
    end
  end

  # ============================================================================
  # Entropy: How unpredictable is the pattern?
  # ============================================================================

  defp compute_entropy([]), do: 0.5
  defp compute_entropy(deltas) when length(deltas) < 3, do: 0.5
  defp compute_entropy(deltas) do
    # Bucket deltas into categories and compute Shannon entropy
    buckets = bucket_deltas(deltas)
    total = Enum.sum(Map.values(buckets))

    if total == 0 do
      0.5
    else
      # Shannon entropy
      entropy = buckets
      |> Map.values()
      |> Enum.filter(&(&1 > 0))
      |> Enum.map(fn count ->
        p = count / total
        -p * :math.log2(p)
      end)
      |> Enum.sum()

      # Normalize by max possible entropy (log2 of bucket count)
      max_entropy = :math.log2(map_size(buckets))
      normalized = if max_entropy > 0, do: entropy / max_entropy, else: 0.5

      clamp(normalized, 0.0, 1.0)
    end
  end

  defp bucket_deltas(deltas) do
    # Bucket into time ranges
    Enum.reduce(deltas, %{
      sub_second: 0,
      seconds: 0,
      tens_of_seconds: 0,
      minutes: 0,
      many_minutes: 0
    }, fn delta, acc ->
      bucket = cond do
        delta < 1 -> :sub_second
        delta < 10 -> :seconds
        delta < 60 -> :tens_of_seconds
        delta < 300 -> :minutes
        true -> :many_minutes
      end
      Map.update!(acc, bucket, &(&1 + 1))
    end)
  end

  # ============================================================================
  # Line-based analysis (fallback when no timestamps)
  # ============================================================================

  defp compute_length_regularity(lengths) when length(lengths) < 2, do: 0.5
  defp compute_length_regularity(lengths) do
    mean = Enum.sum(lengths) / length(lengths)
    variance = Enum.sum(Enum.map(lengths, fn l -> :math.pow(l - mean, 2) end)) / length(lengths)
    std_dev = :math.sqrt(variance)
    cv = if mean > 0, do: std_dev / mean, else: 1.0

    clamp(1.0 / (1.0 + cv), 0.0, 1.0)
  end

  defp compute_length_entropy(lengths) when length(lengths) < 3, do: 0.5
  defp compute_length_entropy(lengths) do
    # Bucket by length ranges
    buckets = Enum.reduce(lengths, %{short: 0, medium: 0, long: 0, very_long: 0}, fn len, acc ->
      bucket = cond do
        len < 40 -> :short
        len < 100 -> :medium
        len < 200 -> :long
        true -> :very_long
      end
      Map.update!(acc, bucket, &(&1 + 1))
    end)

    total = Enum.sum(Map.values(buckets))
    if total == 0, do: 0.5, else: compute_bucket_entropy(buckets, total)
  end

  defp compute_bucket_entropy(buckets, total) do
    entropy = buckets
    |> Map.values()
    |> Enum.filter(&(&1 > 0))
    |> Enum.map(fn count ->
      p = count / total
      -p * :math.log2(p)
    end)
    |> Enum.sum()

    max_entropy = :math.log2(map_size(buckets))
    if max_entropy > 0, do: clamp(entropy / max_entropy, 0.0, 1.0), else: 0.5
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  @doc """
  Return a human-readable summary of the shape.
  """
  def describe(%__MODULE__{} = shape) do
    [
      describe_burstiness(shape.burstiness),
      describe_regularity(shape.regularity),
      describe_acceleration(shape.acceleration),
      describe_concentration(shape.concentration)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp describe_burstiness(b) when b > 0.8, do: "rapid-fire"
  defp describe_burstiness(b) when b > 0.6, do: "bursty"
  defp describe_burstiness(b) when b > 0.4, do: "steady"
  defp describe_burstiness(b) when b > 0.2, do: "sparse"
  defp describe_burstiness(_), do: "very sparse"

  defp describe_regularity(r) when r > 0.8, do: "clockwork"
  defp describe_regularity(r) when r > 0.6, do: "rhythmic"
  defp describe_regularity(r) when r > 0.4, do: nil  # Don't mention if neutral
  defp describe_regularity(r) when r > 0.2, do: "irregular"
  defp describe_regularity(_), do: "erratic"

  defp describe_acceleration(a) when a > 0.3, do: "accelerating"
  defp describe_acceleration(a) when a < -0.3, do: "decelerating"
  defp describe_acceleration(_), do: nil

  defp describe_concentration(c) when c < 0.3, do: "front-loaded"
  defp describe_concentration(c) when c > 0.7, do: "back-loaded"
  defp describe_concentration(_), do: nil
end
