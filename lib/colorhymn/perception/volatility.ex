defmodule Colorhymn.Perception.Volatility do
  @moduledoc """
  Volatility dimension analysis - change and stability over the log.
  """

  def analyze(lines) when length(lines) < 3 do
    %{
      field_variance: 0.5,
      state_churn: 0.5,
      drift: 0.0,
      stability: 0.5
    }
  end

  def analyze(lines) do
    %{
      field_variance: compute_field_variance(lines),
      state_churn: compute_state_churn(lines),
      drift: compute_drift(lines),
      stability: compute_stability(lines)
    }
  end

  defp compute_field_variance(lines) do
    # Extract key=value pairs and see how much values change
    kv_pairs = lines
    |> Enum.flat_map(&extract_key_values/1)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)

    if map_size(kv_pairs) == 0 do
      0.5
    else
      # For each key, compute variance in values
      variances = kv_pairs
      |> Enum.map(fn {_key, values} ->
        unique = values |> Enum.uniq() |> length()
        total = length(values)
        if total > 1, do: (unique - 1) / (total - 1), else: 0.0
      end)

      avg_variance = Enum.sum(variances) / length(variances)
      clamp(avg_variance, 0.0, 1.0)
    end
  end

  defp extract_key_values(line) do
    # Match key=value or key:value patterns
    Regex.scan(~r/(\w+)\s*[=:]\s*([^\s,;\]}"']+)/, line)
    |> Enum.map(fn [_, key, value] -> {String.downcase(key), value} end)
  end

  defp compute_state_churn(lines) do
    # Detect state transitions
    state_keywords = ~r/\b(state|status|phase|stage|mode)\s*[=:]\s*(\w+)/i
    states = lines
    |> Enum.flat_map(fn line ->
      case Regex.run(state_keywords, line) do
        [_, _field, state] -> [state]
        _ -> []
      end
    end)

    if length(states) < 2 do
      0.5
    else
      transitions = states
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> a != b end)

      clamp(transitions / (length(states) - 1), 0.0, 1.0)
    end
  end

  defp compute_drift(lines) do
    # Compare first half vs second half for "health" indicators
    if length(lines) < 4 do
      0.0
    else
      mid = div(length(lines), 2)
      first_half = Enum.take(lines, mid)
      second_half = Enum.drop(lines, mid)

      first_health = compute_health_score(first_half)
      second_health = compute_health_score(second_half)

      # Positive drift = improving, negative = degrading
      clamp(second_health - first_health, -1.0, 1.0)
    end
  end

  defp compute_health_score(lines) do
    if length(lines) == 0 do
      0.5
    else
      error_patterns = ~r/\b(error|fail|failed|critical|fatal|denied|timeout)\b/i
      success_patterns = ~r/\b(success|ok|completed|established|connected|ready)\b/i

      errors = Enum.count(lines, &Regex.match?(error_patterns, &1))
      successes = Enum.count(lines, &Regex.match?(success_patterns, &1))

      total_signals = errors + successes
      if total_signals == 0 do
        0.5
      else
        successes / total_signals
      end
    end
  end

  defp compute_stability(lines) do
    # Measure overall stability - consistent format, no wild swings
    # Combine several signals

    # 1. Line length stability
    lengths = Enum.map(lines, &String.length/1)
    length_cv = coefficient_of_variation(lengths)

    # 2. Token count stability
    token_counts = Enum.map(lines, fn line ->
      line |> String.split(~r/\s+/, trim: true) |> length()
    end)
    token_cv = coefficient_of_variation(token_counts)

    # Average stability (low CV = high stability)
    avg_cv = (length_cv + token_cv) / 2
    stability = 1.0 / (1.0 + avg_cv)

    clamp(stability, 0.0, 1.0)
  end

  defp coefficient_of_variation(values) when length(values) < 2, do: 0.0
  defp coefficient_of_variation(values) do
    mean = Enum.sum(values) / length(values)
    if mean == 0 do
      0.0
    else
      variance = Enum.sum(Enum.map(values, fn v -> :math.pow(v - mean, 2) end)) / length(values)
      :math.sqrt(variance) / mean
    end
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
