defmodule Colorhymn.Perception.Network do
  @moduledoc """
  Network dimension analysis - VPN/connectivity specific patterns.
  """

  # Connection lifecycle patterns
  @connect_patterns [
    ~r/\b(connect|connecting|connection|handshake|negotiate|establish)\b/i,
    ~r/\b(tunnel|ike|ipsec|ssl|tls)\s+(init|start|begin)/i,
    ~r/\bphase\s*[12]\b/i
  ]

  @disconnect_patterns [
    ~r/\b(disconnect|disconnecting|disconnected|teardown|terminate|close)\b/i,
    ~r/\b(tunnel|session|connection)\s+(down|closed|ended|terminated)/i,
    ~r/\b(bye|goodbye|fin|rst)\b/i
  ]

  @success_patterns [
    ~r/\b(established|connected|success|complete|up|active|ready)\b/i,
    ~r/\bphase\s*[12]\s*(complete|success|done)/i,
    ~r/\bSA\s+established\b/i
  ]

  @failure_patterns [
    ~r/\b(failed|failure|error|timeout|refused|rejected|denied)\b/i,
    ~r/\b(no\s+response|unreachable|dropped)\b/i,
    ~r/\bretransmit/i
  ]

  @ip_pattern ~r/\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b/
  @inbound_patterns [~r/\b(inbound|incoming|receive|from|src)\b/i, ~r/<-|<<<|<--/]
  @outbound_patterns [~r/\b(outbound|outgoing|send|to|dst)\b/i, ~r/->|>>>|-->/]

  def analyze(lines, _content) when length(lines) < 1 do
    %{
      session_coherence: 0.5,
      directionality: 0.0,
      entity_churn: 0.5,
      lifecycle_health: 0.5,
      connection_success_ratio: 0.5,
      handshake_completeness: 0.5
    }
  end

  def analyze(lines, content) do
    %{
      session_coherence: compute_session_coherence(lines),
      directionality: compute_directionality(lines),
      entity_churn: compute_entity_churn(lines, content),
      lifecycle_health: compute_lifecycle_health(lines),
      connection_success_ratio: compute_success_ratio(lines),
      handshake_completeness: compute_handshake_completeness(lines)
    }
  end

  defp compute_session_coherence(lines) do
    # Detect if this looks like a single session or multiple interleaved
    # Look for session IDs, connection IDs, or thread markers

    session_markers = lines
    |> Enum.flat_map(fn line ->
      # UUID patterns
      uuids = Regex.scan(~r/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/, line)
      |> Enum.map(fn [id] -> {:uuid, id} end)

      # Session ID patterns
      session_ids = Regex.scan(~r/(session|conn|connection|thread)[_\-\s]*(?:id)?[=:\s]*([a-zA-Z0-9_\-]+)/i, line)
      |> Enum.map(fn [_, _type, id] -> {:session, id} end)

      uuids ++ session_ids
    end)

    if length(session_markers) == 0 do
      0.5  # Can't determine
    else
      unique_sessions = session_markers |> Enum.uniq() |> length()
      # 1 session = 1.0, many sessions = lower coherence
      clamp(1.0 / unique_sessions, 0.0, 1.0)
    end
  end

  defp compute_directionality(lines) do
    inbound_count = Enum.count(lines, fn line ->
      Enum.any?(@inbound_patterns, &Regex.match?(&1, line))
    end)

    outbound_count = Enum.count(lines, fn line ->
      Enum.any?(@outbound_patterns, &Regex.match?(&1, line))
    end)

    total = inbound_count + outbound_count

    if total == 0 do
      0.0  # Balanced/unknown
    else
      # -1 = all inbound, 0 = balanced, +1 = all outbound
      balance = (outbound_count - inbound_count) / total
      clamp(balance, -1.0, 1.0)
    end
  end

  defp compute_entity_churn(lines, _content) do
    # Count unique IPs and see how they're distributed
    ips = lines
    |> Enum.flat_map(fn line ->
      Regex.scan(@ip_pattern, line) |> Enum.map(fn [ip, _] -> ip end)
    end)

    if length(ips) == 0 do
      0.5
    else
      unique_ips = ips |> Enum.uniq() |> length()
      total_mentions = length(ips)

      # High churn = many unique IPs relative to mentions
      # Low churn = same IPs repeated
      churn = unique_ips / total_mentions
      clamp(churn, 0.0, 1.0)
    end
  end

  defp compute_lifecycle_health(lines) do
    # Track connection lifecycle: connect -> established -> disconnect
    # Healthy = proper sequences, Unhealthy = stuck states, retries, failures

    events = Enum.map(lines, &classify_lifecycle_event/1)
    |> Enum.filter(&(&1 != :other))

    if length(events) < 2 do
      0.5
    else
      # Look for healthy patterns: connect followed by success
      # Unhealthy: multiple connects without success, failures

      connects = Enum.count(events, &(&1 == :connect))
      successes = Enum.count(events, &(&1 == :success))
      failures = Enum.count(events, &(&1 == :failure))
      disconnects = Enum.count(events, &(&1 == :disconnect))

      # Healthy ratio: successes and proper disconnects vs failures and hanging connects
      positive = successes + disconnects
      negative = failures + max(0, connects - successes)
      total = positive + negative

      if total == 0 do
        0.5
      else
        clamp(positive / total, 0.0, 1.0)
      end
    end
  end

  defp classify_lifecycle_event(line) do
    cond do
      Enum.any?(@connect_patterns, &Regex.match?(&1, line)) -> :connect
      Enum.any?(@success_patterns, &Regex.match?(&1, line)) -> :success
      Enum.any?(@failure_patterns, &Regex.match?(&1, line)) -> :failure
      Enum.any?(@disconnect_patterns, &Regex.match?(&1, line)) -> :disconnect
      true -> :other
    end
  end

  defp compute_success_ratio(lines) do
    success_count = Enum.count(lines, fn line ->
      Enum.any?(@success_patterns, &Regex.match?(&1, line))
    end)

    failure_count = Enum.count(lines, fn line ->
      Enum.any?(@failure_patterns, &Regex.match?(&1, line))
    end)

    total = success_count + failure_count

    if total == 0 do
      0.5
    else
      clamp(success_count / total, 0.0, 1.0)
    end
  end

  defp compute_handshake_completeness(lines) do
    # Look for handshake phases and see if they complete
    # Common patterns: phase1 -> phase2, client_hello -> server_hello -> finished

    phase1_start = Enum.any?(lines, &Regex.match?(~r/phase\s*1\s*(init|start|begin)/i, &1))
    phase1_done = Enum.any?(lines, &Regex.match?(~r/phase\s*1\s*(complete|success|done)/i, &1))
    phase2_start = Enum.any?(lines, &Regex.match?(~r/phase\s*2\s*(init|start|begin)/i, &1))
    phase2_done = Enum.any?(lines, &Regex.match?(~r/phase\s*2\s*(complete|success|done)/i, &1))

    # TLS handshake patterns
    client_hello = Enum.any?(lines, &Regex.match?(~r/client.?hello/i, &1))
    server_hello = Enum.any?(lines, &Regex.match?(~r/server.?hello/i, &1))
    finished = Enum.any?(lines, &Regex.match?(~r/\b(finished|handshake\s+complete)\b/i, &1))

    # Calculate completeness - build signals list functionally
    signals = []
    |> maybe_add_signal(phase1_start or phase1_done, if(phase1_done, do: 1.0, else: 0.3))
    |> maybe_add_signal(phase2_start or phase2_done, if(phase2_done, do: 1.0, else: 0.3))
    |> maybe_add_signal(client_hello or server_hello or finished,
        cond do
          finished -> 1.0
          client_hello and server_hello -> 0.7
          client_hello or server_hello -> 0.3
          true -> 0.5
        end)

    if length(signals) == 0 do
      0.5  # No handshake patterns detected
    else
      Enum.sum(signals) / length(signals)
    end
  end

  defp maybe_add_signal(list, false, _value), do: list
  defp maybe_add_signal(list, true, value), do: [value | list]

  defp clamp(val, min_v, max_v), do: val |> max(min_v) |> min(max_v)
end
