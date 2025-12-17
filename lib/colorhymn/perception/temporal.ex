defmodule Colorhymn.Perception.Temporal do
  @moduledoc """
  Temporal dimension analysis - how events flow through time.
  """

  def analyze(timestamps, lines) when length(timestamps) < 3 do
    # Fall back to line-based estimation
    %{
      burstiness: 0.5,
      regularity: estimate_regularity_from_lines(lines),
      acceleration: 0.0,
      temporal_concentration: 0.5,
      temporal_entropy: 0.5
    }
  end

  def analyze(timestamps, _lines) do
    sorted = Enum.sort(timestamps)
    deltas = compute_deltas(sorted)

    %{
      burstiness: compute_burstiness(deltas),
      regularity: compute_regularity(deltas),
      acceleration: compute_acceleration(deltas),
      temporal_concentration: compute_concentration(sorted),
      temporal_entropy: compute_entropy(deltas)
    }
  end

  defp compute_deltas(sorted_timestamps) do
    sorted_timestamps
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
    |> Enum.reject(&(&1 <= 0))
  end

  defp compute_burstiness([]), do: 0.5
  defp compute_burstiness(deltas) do
    avg_delta = Enum.sum(deltas) / length(deltas)

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

  defp compute_regularity([]), do: 0.5
  defp compute_regularity(deltas) when length(deltas) < 2, do: 0.5
  defp compute_regularity(deltas) do
    mean = Enum.sum(deltas) / length(deltas)
    variance = Enum.sum(Enum.map(deltas, fn d -> :math.pow(d - mean, 2) end)) / length(deltas)
    std_dev = :math.sqrt(variance)
    cv = if mean > 0, do: std_dev / mean, else: 1.0

    clamp(1.0 / (1.0 + cv), 0.0, 1.0)
  end

  defp compute_acceleration([]), do: 0.0
  defp compute_acceleration(deltas) when length(deltas) < 4, do: 0.0
  defp compute_acceleration(deltas) do
    n = length(deltas)
    quarter = max(div(n, 4), 1)

    first_quarter = Enum.take(deltas, quarter)
    last_quarter = Enum.take(deltas, -quarter)

    avg_first = Enum.sum(first_quarter) / length(first_quarter)
    avg_last = Enum.sum(last_quarter) / length(last_quarter)

    cond do
      avg_first == 0 and avg_last == 0 -> 0.0
      avg_first == 0 -> 1.0
      avg_last == 0 -> -1.0
      true ->
        ratio = avg_first / avg_last
        clamp((ratio - 1) / (ratio + 1), -1.0, 1.0)
    end
  end

  defp compute_concentration([]), do: 0.5
  defp compute_concentration(sorted_timestamps) when length(sorted_timestamps) < 2, do: 0.5
  defp compute_concentration(sorted_timestamps) do
    first = List.first(sorted_timestamps)
    last = List.last(sorted_timestamps)
    span = last - first

    if span == 0 do
      0.5
    else
      n = length(sorted_timestamps)
      median_idx = div(n, 2)
      median_ts = Enum.at(sorted_timestamps, median_idx)
      clamp((median_ts - first) / span, 0.0, 1.0)
    end
  end

  defp compute_entropy([]), do: 0.5
  defp compute_entropy(deltas) when length(deltas) < 3, do: 0.5
  defp compute_entropy(deltas) do
    buckets = bucket_deltas(deltas)
    total = Enum.sum(Map.values(buckets))

    if total == 0 do
      0.5
    else
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
  end

  defp bucket_deltas(deltas) do
    Enum.reduce(deltas, %{sub_second: 0, seconds: 0, tens: 0, minutes: 0, many: 0}, fn delta, acc ->
      bucket = cond do
        delta < 1 -> :sub_second
        delta < 10 -> :seconds
        delta < 60 -> :tens
        delta < 300 -> :minutes
        true -> :many
      end
      Map.update!(acc, bucket, &(&1 + 1))
    end)
  end

  defp estimate_regularity_from_lines(lines) when length(lines) < 2, do: 0.5
  defp estimate_regularity_from_lines(lines) do
    lengths = Enum.map(lines, &String.length/1)
    mean = Enum.sum(lengths) / length(lengths)
    variance = Enum.sum(Enum.map(lengths, fn l -> :math.pow(l - mean, 2) end)) / length(lengths)
    std_dev = :math.sqrt(variance)
    cv = if mean > 0, do: std_dev / mean, else: 1.0
    clamp(1.0 / (1.0 + cv), 0.0, 1.0)
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
