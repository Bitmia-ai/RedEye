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
