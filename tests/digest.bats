#!/usr/bin/env bats

load test_helper

setup() { setup_tmp_project; }
teardown() { teardown_tmp_project; }

@test "digest fails when state.json is missing" {
  run "$REDEYE_ROOT/scripts/digest.sh" "$TMP_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"state.json not found"* ]]
}

@test "digest fails when state.json is invalid JSON" {
  echo "not json" > "$TMP_PROJECT/.redeye/state.json"
  run "$REDEYE_ROOT/scripts/digest.sh" "$TMP_PROJECT"
  [ "$status" -ne 0 ]
}

@test "digest produces valid JSON for a minimal state" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1,"phase_status":"in-progress"}
EOF
  run_digest
  [ "$status" -eq 0 ]
  digest_json | jq -e '.phase == "TRIAGE"' >/dev/null
  digest_json | jq -e '.iteration == 1' >/dev/null
}

@test "digest emits state_age_seconds and it is non-negative" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  run_digest
  [ "$status" -eq 0 ]
  age="$(digest_json | jq -r '.state_age_seconds')"
  [[ "$age" =~ ^[0-9]+$ ]]
}

@test "digest writes warning when steering.md is missing" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  run_digest
  [ "$status" -eq 0 ]
  digest_json | jq -e '.validation_warnings | map(.code) | index("file.missing")' >/dev/null
}

@test "digest detects STOP directive in steering.md" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  cat > "$TMP_PROJECT/.redeye/steering.md" <<'EOF'
## Directives

STOP — done for tonight
EOF
  run_digest
  [ "$status" -eq 0 ]
  digest_json | jq -e '.stop_directive == true' >/dev/null
}

@test "digest reports never-run schedules as overdue" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<'EOF'
### SCHED-1: weekly audit
- **Frequency:** every 7 days
- **Last run:** Never
EOF
  run_digest
  [ "$status" -eq 0 ]
  [ "$(digest_json | jq -r '.overdue_schedules')" = "1" ]
}

@test "digest reports recently-run schedules as not overdue" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<EOF
### SCHED-1: hourly poll
- **Frequency:** every 1 hour
- **Last run:** $now_iso
EOF
  run_digest
  [ "$status" -eq 0 ]
  [ "$(digest_json | jq -r '.overdue_schedules')" = "0" ]
}

@test "digest reports schedules whose interval has elapsed as overdue" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  long_ago=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<EOF
### SCHED-1: weekly audit
- **Frequency:** every 7 days
- **Last run:** $long_ago
EOF
  run_digest
  [ "$status" -eq 0 ]
  [ "$(digest_json | jq -r '.overdue_schedules')" = "1" ]
}

@test "digest counts mixed schedules correctly" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  long_ago=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<EOF
### SCHED-1: never run
- **Frequency:** every 7 days
- **Last run:** Never

### SCHED-2: just ran
- **Frequency:** every 7 days
- **Last run:** $now_iso

### SCHED-3: long ago
- **Frequency:** every 7 days
- **Last run:** $long_ago
EOF
  run_digest
  [ "$status" -eq 0 ]
  [ "$(digest_json | jq -r '.overdue_schedules')" = "2" ]
}

@test "digest schedule logic handles uppercase frequency unit (bash 3.2 path)" {
  # macOS ships bash 3.2 which doesn't support ${var,,}. The fix uses
  # `tr '[:upper:]' '[:lower:]'`. A `Frequency: every 1 Hour` (capital H)
  # must parse correctly on both bash versions.
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<'EOF'
### SCHED-1: hourly with capital
- **Frequency:** every 1 Hour
- **Last run:** Never
EOF
  run_digest
  [ "$status" -eq 0 ]
  [ "$(digest_json | jq -r '.overdue_schedules')" = "1" ]
}

@test "digest preserves prior digest.json on failure" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  run_digest
  [ "$status" -eq 0 ]
  prior="$(digest_json)"

  echo "not json" > "$TMP_PROJECT/.redeye/state.json"
  run_digest
  [ "$status" -ne 0 ]

  current="$(digest_json)"
  [ "$prior" = "$current" ]
}

# --- Degenerate-loop detector ---------------------------------------------
#
# Pin the contract that digest.sh flags a wedged CTO session (≥ 3 consecutive
# identical assistant turns with no tool calls). Without these tests, a future
# refactor of the jq pipeline could silently drop the warning and we'd lose
# the visible signal that the model is stuck (slash-command → skill bridge
# regression on 2026-04-29 was invisible until users noticed token burn).

# Helper: append a synthetic assistant turn to session-cto.jsonl. Pass --tool
# to mark the turn as containing a tool_use block (which excludes it from the
# detector). Pass any number of text args (one per text content block).
write_assistant_turn() {
  local has_tool=false
  if [ "$1" = "--tool" ]; then has_tool=true; shift; fi
  local content="["
  local first=1
  for txt in "$@"; do
    if [ $first -eq 0 ]; then content+=","; fi
    content+="$(jq -nc --arg t "$txt" '{type:"text", text:$t}')"
    first=0
  done
  if [ "$has_tool" = true ]; then
    if [ $first -eq 0 ]; then content+=","; fi
    content+="$(jq -nc '{type:"tool_use", id:"t1", name:"Bash", input:{}}')"
  fi
  content+="]"
  jq -nc --argjson c "$content" '{type:"assistant", message:{content:$c}}' \
    >> "$TMP_PROJECT/.redeye/session-cto.jsonl"
}

@test "digest flags loop.degenerate when last 3 assistant turns are identical" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  write_assistant_turn "Invoke the redeye:start skill."
  write_assistant_turn "Invoke the redeye:start skill."
  write_assistant_turn "Invoke the redeye:start skill."
  run_digest
  [ "$status" -eq 0 ]
  digest_json | jq -e '.validation_warnings | map(.code) | index("loop.degenerate")' >/dev/null
}

@test "digest does NOT flag loop.degenerate when a tool_use sits between" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  write_assistant_turn "Same text"
  write_assistant_turn --tool "Same text"
  write_assistant_turn "Same text"
  run_digest
  [ "$status" -eq 0 ]
  # The middle turn carries a tool_use block so it's filtered out of the
  # detector's window. The remaining 2 text-only turns are below the
  # 3-in-a-row threshold.
  result="$(digest_json | jq -r '.validation_warnings | map(.code) | index("loop.degenerate")')"
  [ "$result" = "null" ]
}

@test "digest does NOT flag loop.degenerate with fewer than 3 assistant turns" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  write_assistant_turn "Only one"
  write_assistant_turn "Only one"
  run_digest
  [ "$status" -eq 0 ]
  result="$(digest_json | jq -r '.validation_warnings | map(.code) | index("loop.degenerate")')"
  [ "$result" = "null" ]
}

@test "digest does NOT flag loop.degenerate when jsonl is missing" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  # No session-cto.jsonl created.
  run_digest
  [ "$status" -eq 0 ]
  result="$(digest_json | jq -r '.validation_warnings | map(.code) | index("loop.degenerate")')"
  [ "$result" = "null" ]
}

@test "digest does NOT flag loop.degenerate when last 3 turns differ" {
  write_state <<'EOF'
{"phase":"TRIAGE","iteration":1}
EOF
  write_assistant_turn "Turn one"
  write_assistant_turn "Turn two"
  write_assistant_turn "Turn three"
  run_digest
  [ "$status" -eq 0 ]
  result="$(digest_json | jq -r '.validation_warnings | map(.code) | index("loop.degenerate")')"
  [ "$result" = "null" ]
}
