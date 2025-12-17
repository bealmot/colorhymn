# Test context-aware temperature detection

IO.puts("=== Testing Context-Aware Temperature ===\n")

# Test 1: False positive case - gamma=error should NOT be critical
IO.puts("1. False positive test: key=value with 'error' as value")
mystery_kv = """
alpha=100
beta=200
gamma=error
delta=warning
epsilon=success
"""
result1 = Colorhymn.FirstSight.perceive(mystery_kv)
IO.puts("   Temperature: #{inspect(result1.temperature)}")
IO.puts("   Expected: :neutral (not :critical)")
IO.puts("   #{if result1.temperature in [:neutral, :calm], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 2: Real error log level should be detected
IO.puts("2. Real error: [ERROR] log level indicator")
real_error = """
2024-01-15 10:30:45 [INFO] Application starting
2024-01-15 10:30:46 [INFO] Loading configuration
2024-01-15 10:30:47 [ERROR] Failed to connect to database
2024-01-15 10:30:48 [INFO] Retrying connection
"""
result2 = Colorhymn.FirstSight.perceive(real_error, "app.log")
IO.puts("   Temperature: #{inspect(result2.temperature)}")
IO.puts("   Expected: :uneasy or :troubled (has real error)")
IO.puts("   #{if result2.temperature in [:uneasy, :troubled, :critical], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 3: JSON with level=error
IO.puts("3. JSON log with \"level\":\"error\"")
json_error = """
{"timestamp":"2024-01-15T10:30:45","level":"info","msg":"starting"}
{"timestamp":"2024-01-15T10:30:46","level":"info","msg":"processing"}
{"timestamp":"2024-01-15T10:30:47","level":"error","msg":"connection failed"}
{"timestamp":"2024-01-15T10:30:48","level":"info","msg":"cleanup"}
"""
result3 = Colorhymn.FirstSight.perceive(json_error, "api.log")
IO.puts("   Temperature: #{inspect(result3.temperature)}")
IO.puts("   Expected: :uneasy or :troubled")
IO.puts("   #{if result3.temperature in [:uneasy, :troubled], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 4: HTTP error status codes
IO.puts("4. HTTP 500 error status")
http_log = """
GET /api/users HTTP/1.1 200 OK
GET /api/posts HTTP/1.1 200 OK
POST /api/login HTTP/1.1 500 Internal Server Error
GET /api/health HTTP/1.1 200 OK
"""
result4 = Colorhymn.FirstSight.perceive(http_log, "access.log")
IO.puts("   Temperature: #{inspect(result4.temperature)}")
IO.puts("   Expected: :uneasy or :troubled")
IO.puts("   #{if result4.temperature in [:uneasy, :troubled], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 5: Contextual errors (failed to, connection refused)
IO.puts("5. Contextual error phrases")
contextual = """
2024-01-15 10:30:45 Starting service
2024-01-15 10:30:46 Failed to connect to remote host
2024-01-15 10:30:47 Connection refused by server
2024-01-15 10:30:48 Service stopped
"""
result5 = Colorhymn.FirstSight.perceive(contextual, "service.log")
IO.puts("   Temperature: #{inspect(result5.temperature)}")
IO.puts("   Expected: :troubled or :critical")
IO.puts("   #{if result5.temperature in [:troubled, :critical], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 6: Clean log should be calm/neutral
IO.puts("6. Clean success log")
clean_log = """
2024-01-15 10:30:45 [INFO] Service started successfully
2024-01-15 10:30:46 [INFO] Connected to database
2024-01-15 10:30:47 [INFO] Ready to accept connections
2024-01-15 10:30:48 [INFO] Health check completed
"""
result6 = Colorhymn.FirstSight.perceive(clean_log, "service.log")
IO.puts("   Temperature: #{inspect(result6.temperature)}")
IO.puts("   Expected: :calm or :neutral")
IO.puts("   #{if result6.temperature in [:calm, :neutral], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 7: error_code field name should not trigger
IO.puts("7. Field name 'error_code' should not trigger error")
field_name = """
request_id=12345
error_code=0
status=ok
response_time=45ms
"""
result7 = Colorhymn.FirstSight.perceive(field_name)
IO.puts("   Temperature: #{inspect(result7.temperature)}")
IO.puts("   Expected: :neutral or :calm")
IO.puts("   #{if result7.temperature in [:neutral, :calm], do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

# Test 8: Heavy errors should be critical
IO.puts("8. Heavy error log (many errors)")
heavy_errors = """
2024-01-15 10:30:45 [ERROR] Connection timeout
2024-01-15 10:30:46 [ERROR] Database unreachable
2024-01-15 10:30:47 [ERROR] Cache failed
2024-01-15 10:30:48 [ERROR] Service unavailable
2024-01-15 10:30:49 [FATAL] System shutdown
"""
result8 = Colorhymn.FirstSight.perceive(heavy_errors, "crash.log")
IO.puts("   Temperature: #{inspect(result8.temperature)}")
IO.puts("   Expected: :critical")
IO.puts("   #{if result8.temperature == :critical, do: "✓ PASS", else: "✗ FAIL"}")
IO.puts("")

IO.puts("=== Temperature tests completed ===")
