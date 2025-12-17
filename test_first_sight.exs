# Test FirstSight with continuous Shape scores

alias Colorhymn.Shape

IO.puts("=== Testing Continuous Shape Scores ===\n")

# Simple visualization helpers
defmodule Viz do
  def progress_bar(val) do
    filled = round(val * 10)
    empty = 10 - filled
    "[" <> String.duplicate("█", filled) <> String.duplicate("░", empty) <> "]"
  end

  def accel_bar(val) do
    # -1 to 1 scale, center at 5
    pos = round((val + 1) / 2 * 10)
    left = String.duplicate("░", min(pos, 5))
    right = String.duplicate("░", max(0, 10 - max(pos, 5)))
    center = if pos < 5, do: String.duplicate("◄", 5 - pos), else: ""
    center2 = if pos > 5, do: String.duplicate("►", pos - 5), else: ""
    "[" <> left <> center <> "│" <> center2 <> right <> "]"
  end
end

# Test 1: Bursty VPN log (sub-second events)
IO.puts("1. Bursty VPN log (50ms between events)")
vpn_bursty = """
2024-01-15T10:30:45.100 VPN tunnel negotiation started
2024-01-15T10:30:45.150 IKE phase1 initiated
2024-01-15T10:30:45.200 IKE phase1 complete
2024-01-15T10:30:45.250 IKE phase2 initiated
2024-01-15T10:30:45.300 IPSEC SA established
2024-01-15T10:30:45.350 Tunnel up
"""
result = Colorhymn.FirstSight.perceive(vpn_bursty, "vpn.log")
IO.puts("   burstiness:    #{Float.round(result.shape.burstiness, 2)} #{Viz.progress_bar(result.shape.burstiness)}")
IO.puts("   regularity:    #{Float.round(result.shape.regularity, 2)} #{Viz.progress_bar(result.shape.regularity)}")
IO.puts("   acceleration:  #{Float.round(result.shape.acceleration, 2)} #{Viz.accel_bar(result.shape.acceleration)}")
IO.puts("   concentration: #{Float.round(result.shape.concentration, 2)} #{Viz.progress_bar(result.shape.concentration)}")
IO.puts("   entropy:       #{Float.round(result.shape.entropy, 2)} #{Viz.progress_bar(result.shape.entropy)}")
IO.puts("   → #{Shape.describe(result.shape)}")
IO.puts("")

# Test 2: Sparse heartbeat (5 min intervals)
IO.puts("2. Sparse heartbeat log (5 minute intervals)")
sparse_log = """
2024-01-15T10:00:00 System heartbeat
2024-01-15T10:05:00 System heartbeat
2024-01-15T10:10:00 System heartbeat
2024-01-15T10:15:00 System heartbeat
2024-01-15T10:20:00 System heartbeat
"""
result2 = Colorhymn.FirstSight.perceive(sparse_log, "heartbeat.log")
IO.puts("   burstiness:    #{Float.round(result2.shape.burstiness, 2)} #{Viz.progress_bar(result2.shape.burstiness)}")
IO.puts("   regularity:    #{Float.round(result2.shape.regularity, 2)} #{Viz.progress_bar(result2.shape.regularity)}")
IO.puts("   acceleration:  #{Float.round(result2.shape.acceleration, 2)} #{Viz.accel_bar(result2.shape.acceleration)}")
IO.puts("   concentration: #{Float.round(result2.shape.concentration, 2)} #{Viz.progress_bar(result2.shape.concentration)}")
IO.puts("   entropy:       #{Float.round(result2.shape.entropy, 2)} #{Viz.progress_bar(result2.shape.entropy)}")
IO.puts("   → #{Shape.describe(result2.shape)}")
IO.puts("")

# Test 3: Accelerating pattern (gaps shrinking)
IO.puts("3. Accelerating cascade (gaps shrinking)")
accel_log = """
2024-01-15T10:00:00 First event
2024-01-15T10:00:30 Second event
2024-01-15T10:00:45 Third event
2024-01-15T10:00:52 Fourth event
2024-01-15T10:00:56 Fifth event
2024-01-15T10:00:58 Sixth event
2024-01-15T10:00:59 Seventh event
2024-01-15T10:00:59.500 Eighth event
"""
result3 = Colorhymn.FirstSight.perceive(accel_log, "cascade.log")
IO.puts("   burstiness:    #{Float.round(result3.shape.burstiness, 2)} #{Viz.progress_bar(result3.shape.burstiness)}")
IO.puts("   regularity:    #{Float.round(result3.shape.regularity, 2)} #{Viz.progress_bar(result3.shape.regularity)}")
IO.puts("   acceleration:  #{Float.round(result3.shape.acceleration, 2)} #{Viz.accel_bar(result3.shape.acceleration)}")
IO.puts("   concentration: #{Float.round(result3.shape.concentration, 2)} #{Viz.progress_bar(result3.shape.concentration)}")
IO.puts("   entropy:       #{Float.round(result3.shape.entropy, 2)} #{Viz.progress_bar(result3.shape.entropy)}")
IO.puts("   → #{Shape.describe(result3.shape)}")
IO.puts("")

# Test 4: Front-loaded incident
IO.puts("4. Front-loaded incident (activity at start)")
front_log = """
2024-01-15T10:00:00 Incident started
2024-01-15T10:00:01 Error detected
2024-01-15T10:00:02 Failover initiated
2024-01-15T10:00:03 Failover complete
2024-01-15T10:05:00 System stable
2024-01-15T10:10:00 Monitoring resumed
"""
result4 = Colorhymn.FirstSight.perceive(front_log, "incident.log")
IO.puts("   burstiness:    #{Float.round(result4.shape.burstiness, 2)} #{Viz.progress_bar(result4.shape.burstiness)}")
IO.puts("   regularity:    #{Float.round(result4.shape.regularity, 2)} #{Viz.progress_bar(result4.shape.regularity)}")
IO.puts("   acceleration:  #{Float.round(result4.shape.acceleration, 2)} #{Viz.accel_bar(result4.shape.acceleration)}")
IO.puts("   concentration: #{Float.round(result4.shape.concentration, 2)} #{Viz.progress_bar(result4.shape.concentration)}")
IO.puts("   entropy:       #{Float.round(result4.shape.entropy, 2)} #{Viz.progress_bar(result4.shape.entropy)}")
IO.puts("   → #{Shape.describe(result4.shape)}")
IO.puts("")

# Test 5: Erratic pattern (random intervals)
IO.puts("5. Erratic pattern (random intervals)")
erratic_log = """
2024-01-15T10:00:00 Event A
2024-01-15T10:00:01 Event B
2024-01-15T10:02:00 Event C
2024-01-15T10:02:01 Event D
2024-01-15T10:02:02 Event E
2024-01-15T10:10:00 Event F
2024-01-15T10:10:30 Event G
"""
result5 = Colorhymn.FirstSight.perceive(erratic_log, "random.log")
IO.puts("   burstiness:    #{Float.round(result5.shape.burstiness, 2)} #{Viz.progress_bar(result5.shape.burstiness)}")
IO.puts("   regularity:    #{Float.round(result5.shape.regularity, 2)} #{Viz.progress_bar(result5.shape.regularity)}")
IO.puts("   acceleration:  #{Float.round(result5.shape.acceleration, 2)} #{Viz.accel_bar(result5.shape.acceleration)}")
IO.puts("   concentration: #{Float.round(result5.shape.concentration, 2)} #{Viz.progress_bar(result5.shape.concentration)}")
IO.puts("   entropy:       #{Float.round(result5.shape.entropy, 2)} #{Viz.progress_bar(result5.shape.entropy)}")
IO.puts("   → #{Shape.describe(result5.shape)}")
IO.puts("")

IO.puts("=== All shape tests completed ===")
