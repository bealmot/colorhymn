defmodule Colorhymn.Perception.Dialogue do
  @moduledoc """
  Dialogue dimension analysis - conversational flow and structure.
  """

  # Patterns that suggest request/outbound direction
  @request_patterns [
    ~r/\b(request|send|sending|sent|query|asking|outbound|->|>>>)\b/i,
    ~r/\bGET|POST|PUT|DELETE|PATCH\b/,
    ~r/\b(connect|connecting|initiating|starting)\b/i
  ]

  # Patterns that suggest response/inbound direction
  @response_patterns [
    ~r/\b(response|receive|received|receiving|reply|answer|inbound|<-|<<<)\b/i,
    ~r/\bHTTP\/\d\.\d\s+\d{3}\b/,
    ~r/\b(accepted|returned|responded)\b/i
  ]

  def analyze(lines) when length(lines) < 2 do
    %{
      request_response_balance: 0.5,
      turn_frequency: 0.5,
      monologue_tendency: 0.5,
      echo_ratio: 0.5
    }
  end

  def analyze(lines) do
    directions = Enum.map(lines, &classify_direction/1)

    %{
      request_response_balance: compute_balance(directions),
      turn_frequency: compute_turn_frequency(directions),
      monologue_tendency: compute_monologue_tendency(directions),
      echo_ratio: compute_echo_ratio(lines)
    }
  end

  defp classify_direction(line) do
    is_request = Enum.any?(@request_patterns, &Regex.match?(&1, line))
    is_response = Enum.any?(@response_patterns, &Regex.match?(&1, line))

    cond do
      is_request and not is_response -> :request
      is_response and not is_request -> :response
      is_request and is_response -> :both
      true -> :neutral
    end
  end

  defp compute_balance(directions) do
    requests = Enum.count(directions, &(&1 == :request))
    responses = Enum.count(directions, &(&1 == :response))
    total = requests + responses

    if total == 0 do
      0.5  # No clear direction markers
    else
      # 0 = all requests, 0.5 = balanced, 1 = all responses
      clamp(responses / total, 0.0, 1.0)
    end
  end

  defp compute_turn_frequency(directions) do
    # Count how often direction changes
    directional = Enum.filter(directions, &(&1 in [:request, :response]))

    if length(directional) < 2 do
      0.5
    else
      turns = directional
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.count(fn [a, b] -> a != b end)

      # Normalize by potential turns
      clamp(turns / (length(directional) - 1), 0.0, 1.0)
    end
  end

  defp compute_monologue_tendency(directions) do
    # Look for long runs of same direction
    directional = Enum.filter(directions, &(&1 in [:request, :response]))

    if length(directional) < 3 do
      0.5
    else
      runs = directional
      |> Enum.chunk_by(& &1)
      |> Enum.map(&length/1)

      avg_run = Enum.sum(runs) / length(runs)

      # Long runs = monologue tendency
      # Normalize: avg run of 1-2 = conversational (0.0-0.3), 5+ = monologue (0.8+)
      clamp((avg_run - 1) / 4, 0.0, 1.0)
    end
  end

  defp compute_echo_ratio(lines) do
    # Detect echoed content (same or very similar content appearing twice)
    if length(lines) < 2 do
      0.5
    else
      # Simplified: count lines that are near-duplicates of another line
      templates = Enum.map(lines, &simplify_for_echo/1)
      frequencies = Enum.frequencies(templates)

      echoed_count = frequencies
      |> Enum.filter(fn {_t, count} -> count > 1 end)
      |> Enum.map(fn {_t, count} -> count - 1 end)  # Don't count original
      |> Enum.sum()

      clamp(echoed_count / length(lines), 0.0, 1.0)
    end
  end

  defp simplify_for_echo(line) do
    line
    |> String.downcase()
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
