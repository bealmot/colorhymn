# Test comprehensive Perception system

alias Colorhymn.Perception

IO.puts("═══════════════════════════════════════════════════════════════")
IO.puts("            COLORHYMN PERCEPTION SYSTEM TEST")
IO.puts("═══════════════════════════════════════════════════════════════\n")

defmodule PerceptionViz do
  def bar(val, width \\ 20) do
    filled = round(val * width)
    empty = width - filled
    "│" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "│"
  end

  def accel_bar(val, width \\ 20) do
    mid = div(width, 2)
    pos = round((val + 1) / 2 * width)
    chars = for i <- 0..(width-1) do
      cond do
        i == mid -> "│"
        i < mid and i >= pos -> "◄"
        i > mid and i <= pos -> "►"
        true -> "░"
      end
    end
    "│" <> Enum.join(chars) <> "│"
  end

  def print_perception(p) do
    IO.puts("  ┌─ TEMPORAL ─────────────────────────────────────────────────┐")
    IO.puts("  │ burstiness:         #{format(p.burstiness)} #{bar(p.burstiness)}")
    IO.puts("  │ regularity:         #{format(p.regularity)} #{bar(p.regularity)}")
    IO.puts("  │ acceleration:      #{format_signed(p.acceleration)} #{accel_bar(p.acceleration)}")
    IO.puts("  │ concentration:      #{format(p.temporal_concentration)} #{bar(p.temporal_concentration)}")
    IO.puts("  │ entropy:            #{format(p.temporal_entropy)} #{bar(p.temporal_entropy)}")
    IO.puts("  │")
    IO.puts("  ├─ STRUCTURAL ────────────────────────────────────────────────┤")
    IO.puts("  │ line_length_var:    #{format(p.line_length_variance)} #{bar(p.line_length_variance)}")
    IO.puts("  │ consistency:        #{format(p.structure_consistency)} #{bar(p.structure_consistency)}")
    IO.puts("  │ nesting_depth:      #{format(p.nesting_depth)} #{bar(p.nesting_depth)}")
    IO.puts("  │ whitespace:         #{format(p.whitespace_ratio)} #{bar(p.whitespace_ratio)}")
    IO.puts("  │ block_regularity:   #{format(p.block_regularity)} #{bar(p.block_regularity)}")
    IO.puts("  │")
    IO.puts("  ├─ DENSITY ───────────────────────────────────────────────────┤")
    IO.puts("  │ token_density:      #{format(p.token_density)} #{bar(p.token_density)}")
    IO.puts("  │ entity_density:     #{format(p.entity_density)} #{bar(p.entity_density)}")
    IO.puts("  │ info_density:       #{format(p.information_density)} #{bar(p.information_density)}")
    IO.puts("  │ noise_ratio:        #{format(p.noise_ratio)} #{bar(p.noise_ratio)}")
    IO.puts("  │")
    IO.puts("  ├─ REPETITION ────────────────────────────────────────────────┤")
    IO.puts("  │ uniqueness:         #{format(p.uniqueness)} #{bar(p.uniqueness)}")
    IO.puts("  │ template_ratio:     #{format(p.template_ratio)} #{bar(p.template_ratio)}")
    IO.puts("  │ pattern_recurrence: #{format(p.pattern_recurrence)} #{bar(p.pattern_recurrence)}")
    IO.puts("  │ motif_strength:     #{format(p.motif_strength)} #{bar(p.motif_strength)}")
    IO.puts("  │")
    IO.puts("  ├─ DIALOGUE ──────────────────────────────────────────────────┤")
    IO.puts("  │ req/resp balance:   #{format(p.request_response_balance)} #{bar(p.request_response_balance)}")
    IO.puts("  │ turn_frequency:     #{format(p.turn_frequency)} #{bar(p.turn_frequency)}")
    IO.puts("  │ monologue:          #{format(p.monologue_tendency)} #{bar(p.monologue_tendency)}")
    IO.puts("  │ echo_ratio:         #{format(p.echo_ratio)} #{bar(p.echo_ratio)}")
    IO.puts("  │")
    IO.puts("  ├─ VOLATILITY ────────────────────────────────────────────────┤")
    IO.puts("  │ field_variance:     #{format(p.field_variance)} #{bar(p.field_variance)}")
    IO.puts("  │ state_churn:        #{format(p.state_churn)} #{bar(p.state_churn)}")
    IO.puts("  │ drift:             #{format_signed(p.drift)} #{accel_bar(p.drift)}")
    IO.puts("  │ stability:          #{format(p.stability)} #{bar(p.stability)}")
    IO.puts("  │")
    IO.puts("  ├─ COMPLEXITY ────────────────────────────────────────────────┤")
    IO.puts("  │ bracket_depth:      #{format(p.bracket_depth)} #{bar(p.bracket_depth)}")
    IO.puts("  │ clause_chains:      #{format(p.clause_chains)} #{bar(p.clause_chains)}")
    IO.puts("  │ parse_difficulty:   #{format(p.parse_difficulty)} #{bar(p.parse_difficulty)}")
    IO.puts("  │ cognitive_load:     #{format(p.cognitive_load)} #{bar(p.cognitive_load)}")
    IO.puts("  │")
    IO.puts("  ├─ NETWORK ───────────────────────────────────────────────────┤")
    IO.puts("  │ session_coherence:  #{format(p.session_coherence)} #{bar(p.session_coherence)}")
    IO.puts("  │ directionality:    #{format_signed(p.directionality)} #{accel_bar(p.directionality)}")
    IO.puts("  │ entity_churn:       #{format(p.entity_churn)} #{bar(p.entity_churn)}")
    IO.puts("  │ lifecycle_health:   #{format(p.lifecycle_health)} #{bar(p.lifecycle_health)}")
    IO.puts("  │ success_ratio:      #{format(p.connection_success_ratio)} #{bar(p.connection_success_ratio)}")
    IO.puts("  │ handshake_complete: #{format(p.handshake_completeness)} #{bar(p.handshake_completeness)}")
    IO.puts("  └────────────────────────────────────────────────────────────────┘")
  end

  defp format(val), do: val |> Float.round(2) |> Float.to_string() |> String.pad_leading(5)
  defp format_signed(val) do
    s = if val >= 0, do: "+", else: ""
    s <> (val |> Float.round(2) |> Float.to_string() |> String.pad_leading(4))
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 1: VPN Connection Log
# ═══════════════════════════════════════════════════════════════════════════════

vpn_log = """
2024-01-15T10:30:45.100 [INFO] VPN client starting, version 2.5.1
2024-01-15T10:30:45.150 [INFO] Initiating connection to gateway 203.0.113.50
2024-01-15T10:30:45.200 [INFO] IKE phase 1 negotiation started
2024-01-15T10:30:45.350 [INFO] IKE phase 1 complete, identity verified
2024-01-15T10:30:45.400 [INFO] IKE phase 2 negotiation started
2024-01-15T10:30:45.550 [INFO] IKE phase 2 complete, SA established
2024-01-15T10:30:45.600 [INFO] IPsec tunnel established to 203.0.113.50
2024-01-15T10:30:45.650 [INFO] Tunnel up, assigned IP: 10.8.0.15
2024-01-15T10:30:46.000 [INFO] DNS servers configured: 10.8.0.1, 10.8.0.2
2024-01-15T10:30:46.100 [INFO] Connection ready, routing traffic
"""

IO.puts("TEST 1: VPN Connection Log (successful handshake)")
IO.puts("─────────────────────────────────────────────────────────────────")
result1 = Colorhymn.FirstSight.perceive(vpn_log, "vpn_session.log")
IO.puts("Type: #{inspect(result1.type)}")
IO.puts("Format: #{inspect(result1.format)}")
IO.puts("Temperature: #{inspect(result1.temperature)}")
PerceptionViz.print_perception(result1.perception)
IO.puts("")

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 2: Failed VPN with retries
# ═══════════════════════════════════════════════════════════════════════════════

failed_vpn = """
2024-01-15T10:30:45 [INFO] Connecting to 198.51.100.25
2024-01-15T10:30:50 [WARN] Connection timeout, retrying...
2024-01-15T10:30:55 [WARN] Connection timeout, retrying...
2024-01-15T10:31:00 [ERROR] Failed to establish tunnel after 3 attempts
2024-01-15T10:31:01 [INFO] Trying alternate gateway 198.51.100.26
2024-01-15T10:31:06 [WARN] Connection timeout, retrying...
2024-01-15T10:31:11 [ERROR] Connection refused by server
2024-01-15T10:31:12 [FATAL] All gateways exhausted, connection failed
"""

IO.puts("TEST 2: Failed VPN Connection (cascade failure)")
IO.puts("─────────────────────────────────────────────────────────────────")
result2 = Colorhymn.FirstSight.perceive(failed_vpn, "vpn_error.log")
IO.puts("Type: #{inspect(result2.type)}")
IO.puts("Format: #{inspect(result2.format)}")
IO.puts("Temperature: #{inspect(result2.temperature)}")
PerceptionViz.print_perception(result2.perception)
IO.puts("")

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 3: JSON API Log
# ═══════════════════════════════════════════════════════════════════════════════

json_log = """
{"ts":"2024-01-15T10:30:45.001","level":"info","method":"GET","path":"/api/users","status":200,"duration_ms":45}
{"ts":"2024-01-15T10:30:45.050","level":"info","method":"POST","path":"/api/login","status":200,"duration_ms":120}
{"ts":"2024-01-15T10:30:45.200","level":"info","method":"GET","path":"/api/posts","status":200,"duration_ms":35}
{"ts":"2024-01-15T10:30:45.300","level":"error","method":"POST","path":"/api/upload","status":500,"duration_ms":5000,"error":"timeout"}
{"ts":"2024-01-15T10:30:45.400","level":"info","method":"GET","path":"/api/health","status":200,"duration_ms":5}
"""

IO.puts("TEST 3: JSON API Log (structured, bursty)")
IO.puts("─────────────────────────────────────────────────────────────────")
result3 = Colorhymn.FirstSight.perceive(json_log, "api.log")
IO.puts("Type: #{inspect(result3.type)}")
IO.puts("Format: #{inspect(result3.format)}")
IO.puts("Temperature: #{inspect(result3.temperature)}")
PerceptionViz.print_perception(result3.perception)
IO.puts("")

# ═══════════════════════════════════════════════════════════════════════════════
# TEST 4: Windows ipconfig snapshot
# ═══════════════════════════════════════════════════════════════════════════════

ipconfig = """
Windows IP Configuration

Ethernet adapter Local Area Connection:

   Connection-specific DNS Suffix  . : corp.example.com
   IPv4 Address. . . . . . . . . . . : 192.168.1.100
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1

Wireless LAN adapter Wi-Fi:

   Media State . . . . . . . . . . . : Media disconnected
   Connection-specific DNS Suffix  . :
"""

IO.puts("TEST 4: Windows ipconfig (snapshot, no timestamps)")
IO.puts("─────────────────────────────────────────────────────────────────")
result4 = Colorhymn.FirstSight.perceive(ipconfig, "ipconfig.txt")
IO.puts("Type: #{inspect(result4.type)}")
IO.puts("Format: #{inspect(result4.format)}")
IO.puts("Temperature: #{inspect(result4.temperature)}")
PerceptionViz.print_perception(result4.perception)
IO.puts("")

IO.puts("═══════════════════════════════════════════════════════════════")
IO.puts("                    ALL TESTS COMPLETED")
IO.puts("═══════════════════════════════════════════════════════════════")
