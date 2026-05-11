#!/usr/bin/env bats

load test_helper

CREATE_SCHED="$REDEYE_ROOT/scripts/create-schedule.sh"

setup() {
  setup_tmp_project
  write_state <<'EOF'
{"counters":{"next_task_id":1,"next_q_id":1,"next_cred_id":1,"next_sched_id":3}}
EOF
  cat > "$TMP_PROJECT/.redeye/schedules.md" <<'EOF'
# Scheduled Tasks

_(Define recurring tasks here. Minimum frequency: 1 hour.)_

## Format
Each task follows:
### SCHED-{id}: {title}
- **Frequency:** every {duration}
- **Last run:** {ISO timestamp}
- **Task:**
  1. {step}
  2. {step}
- **Assigned to:** {role(s)}
EOF
}
teardown() { teardown_tmp_project; }

@test "appends a SCHED-NNN at end with the next ID" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "Bump deps weekly" --frequency "every 1w" \
      --task-step "Run npm outdated" --task-step "Open PRs for safe bumps"
  [ "$status" -eq 0 ]
  [ "$output" = "SCHED-003" ]
  grep -q "^### SCHED-003: Bump deps weekly$" "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^- \*\*Frequency:\*\* every 1w$"   "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^- \*\*Last run:\*\* 1970-01-01"   "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^- \*\*Task:\*\*$"                 "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^  1. Run npm outdated$"            "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^  2. Open PRs for safe bumps$"     "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^- \*\*Assigned to:\*\* documenter$" "$TMP_PROJECT/.redeye/schedules.md"
}

@test "bumps next_sched_id atomically" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1h" --task-step "do thing"
  [ "$status" -eq 0 ]
  next="$(jq -r '.counters.next_sched_id' "$TMP_PROJECT/.redeye/state.json")"
  [ "$next" = "4" ]
}

@test "second call appends another schedule with the next ID" {
  "$CREATE_SCHED" --project-root "$TMP_PROJECT" --title "a" --frequency "every 1d" --task-step "x" >/dev/null
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" --title "b" --frequency "every 1d" --task-step "y"
  [ "$status" -eq 0 ]
  [ "$output" = "SCHED-004" ]
  grep -q "^### SCHED-003: a$" "$TMP_PROJECT/.redeye/schedules.md"
  grep -q "^### SCHED-004: b$" "$TMP_PROJECT/.redeye/schedules.md"
}

@test "--assigned-to overrides the default" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d" --task-step "y" \
      --assigned-to "reviewer, user-tester"
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Assigned to:\*\* reviewer, user-tester$" "$TMP_PROJECT/.redeye/schedules.md"
}

@test "--last-run overrides the default epoch timestamp" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d" --task-step "y" \
      --last-run "2026-05-11T12:00:00Z"
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Last run:\*\* 2026-05-11T12:00:00Z$" "$TMP_PROJECT/.redeye/schedules.md"
}

@test "rejects --frequency below the 1h floor" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 0.5h" --task-step "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"floor is 1 hour"* ]]
}

@test "rejects malformed --frequency" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "weekly" --task-step "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must match 'every <N><h|d|w>'"* ]]
}

@test "rejects malformed --last-run (non-ISO)" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d" --task-step "y" \
      --last-run "2026-05-11 12:00:00"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be ISO 8601"* ]]
}

@test "rejects missing --task-step" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--task-step is required"* ]]
}

@test "rejects missing --title or --frequency" {
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --frequency "every 1d" --task-step "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--title is required"* ]]
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --task-step "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--frequency is required"* ]]
}

@test "dry-run prints the entry and does not write" {
  before_sched="$(sha1sum "$TMP_PROJECT/.redeye/schedules.md" | cut -d' ' -f1)"
  before_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d" --task-step "y" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"### SCHED-003: x"* ]]
  [[ "$output" == *"every 1d"* ]]
  after_sched="$(sha1sum "$TMP_PROJECT/.redeye/schedules.md" | cut -d' ' -f1)"
  after_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  [ "$before_sched" = "$after_sched" ]
  [ "$before_state" = "$after_state" ]
}

@test "rejects when .redeye/schedules.md is missing" {
  rm "$TMP_PROJECT/.redeye/schedules.md"
  run "$CREATE_SCHED" --project-root "$TMP_PROJECT" \
      --title "x" --frequency "every 1d" --task-step "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing schedules.md"* ]]
}
