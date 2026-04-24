#!/usr/bin/env bats

# Cover the kill-switch surface: STOP detection, max-iteration cap, debug
# gating. The stop-hook is the only way RedEye stops outside an explicit
# CEO-DIRECTED-STOP promise — a regression here makes the loop unstoppable.

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
  echo '{"phase":"TRIAGE","iteration":0}' > .redeye/state.json
  mkdir -p .claude
}

teardown() { teardown_tmp_project; }

write_loop_file() {
  local iteration="$1" max="$2"
  cat > "$TMP_PROJECT/.claude/ralph-loop.local.md" <<EOF
---
active: true
session_id: redeye-managed
iteration: $iteration
max_iterations: $max
completion_promise: "CEO DIRECTED STOP"
---
You are the CTO. Body content here.
EOF
}

run_hook_with_empty_input() {
  echo '{"transcript_path": ""}' | "$REDEYE_ROOT/hooks/stop-hook.sh"
}

@test "stop-hook deactivates loop when steering.md has STOP directive" {
  write_loop_file 1 0
  cat > "$TMP_PROJECT/.redeye/steering.md" <<'EOF'
## Directives

STOP — CEO directed
EOF
  run run_hook_with_empty_input
  [ "$status" -eq 0 ]
  grep -q "^active: false" "$TMP_PROJECT/.claude/ralph-loop.local.md"
}

@test "stop-hook continues when steering.md has no STOP directive" {
  write_loop_file 1 0
  : > "$TMP_PROJECT/.redeye/steering.md"
  run run_hook_with_empty_input
  [ "$status" -eq 0 ]
  grep -q "^active: true" "$TMP_PROJECT/.claude/ralph-loop.local.md"
}

@test "stop-hook deactivates when iteration >= max_iterations" {
  write_loop_file 5 5
  run run_hook_with_empty_input
  [ "$status" -eq 0 ]
  grep -q "^active: false" "$TMP_PROJECT/.claude/ralph-loop.local.md"
}

@test "stop-hook continues with unlimited iterations (max = 0)" {
  write_loop_file 9999 0
  run run_hook_with_empty_input
  [ "$status" -eq 0 ]
  grep -q "^active: true" "$TMP_PROJECT/.claude/ralph-loop.local.md"
}

@test "stop-hook increments iteration counter" {
  write_loop_file 3 0
  run_hook_with_empty_input >/dev/null
  grep -q "^iteration: 4$" "$TMP_PROJECT/.claude/ralph-loop.local.md"
}

@test "stop-hook does not write debug log when REDEYE_DEBUG unset" {
  write_loop_file 1 0
  : > "$TMP_PROJECT/.redeye/steering.md"
  local debug="$TMP_PROJECT/.redeye-debug.log"
  REDEYE_DEBUG_LOG="$debug" run run_hook_with_empty_input
  [ ! -e "$debug" ]
}

@test "stop-hook writes debug log when REDEYE_DEBUG=1" {
  write_loop_file 1 0
  : > "$TMP_PROJECT/.redeye/steering.md"
  local debug="$TMP_PROJECT/.redeye-debug.log"
  REDEYE_DEBUG=1 REDEYE_DEBUG_LOG="$debug" run run_hook_with_empty_input
  [ -f "$debug" ]
  grep -q "Stop hook invoked" "$debug"
}

@test "stop-hook exits cleanly when loop file is missing" {
  rm -f "$TMP_PROJECT/.claude/ralph-loop.local.md"
  run run_hook_with_empty_input
  [ "$status" -eq 0 ]
}
