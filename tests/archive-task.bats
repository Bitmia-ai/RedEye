#!/usr/bin/env bats

# tests/archive-task.bats — pin the contract that archive-task.sh moves a
# done-task's body to docs/tasks-archive/YYYY-MM.md and removes it from
# tasks.md entirely (no stub left behind). Without these tests TRIAGE's
# per-iteration tasks.md read can silently regrow as the bash glue subtly
# drifts.

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
}

teardown() { teardown_tmp_project; }

write_tasks() {
  cat > "$TMP_PROJECT/.redeye/tasks.md"
}

@test "archive-task moves a done task's body and removes it from tasks.md" {
  write_tasks <<'EOF'
# Backlog

## CEO Requests

### T001: Build feature X
- **Type:** feature
- **Priority:** P1
- **Status:** done
- **Merged:** 2026-04-28 (iter 100)
- **Spec:** docs/specs/T001.md
- **Summary:** Feature X built and shipped successfully.
- **Description:** Long description that should not remain in tasks.md.

### T002: Active task
- **Type:** bug
- **Status:** pending
EOF
  run "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: T001"* ]]

  # tasks.md no longer contains T001 at all — heading, body, anything.
  ! grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "Build feature X" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "Long description" "$TMP_PROJECT/.redeye/tasks.md"

  # T002 untouched.
  grep -q "^### T002: Active task$" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^- \*\*Status:\*\* pending$" "$TMP_PROJECT/.redeye/tasks.md"

  # Archive file holds the full body.
  archive="$TMP_PROJECT/docs/tasks-archive/2026-04.md"
  [ -f "$archive" ]
  grep -q "^### T001: Build feature X$" "$archive"
  grep -q "Long description" "$archive"
  grep -q "Spec:" "$archive"
  grep -q "Summary:" "$archive"
}

@test "archive-task is a no-op when the task is already archived (absent from tasks.md)" {
  write_tasks <<'EOF'
## CEO Requests

### T001: X
- **Type:** feature
- **Status:** done
- **Merged:** 2026-04-28 (iter 1)
- **Description:** First archive run moves this away.
EOF
  "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001 >/dev/null
  size_before="$(wc -c < "$TMP_PROJECT/.redeye/tasks.md")"
  archive_size_before="$(wc -c < "$TMP_PROJECT/docs/tasks-archive/2026-04.md")"

  # Re-running is a no-op — task no longer in tasks.md, so the script bails.
  run "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001
  [ "$status" -eq 0 ]
  [[ "$output" == *"already archived"* || "$output" == *"not in tasks.md"* ]]

  size_after="$(wc -c < "$TMP_PROJECT/.redeye/tasks.md")"
  archive_size_after="$(wc -c < "$TMP_PROJECT/docs/tasks-archive/2026-04.md")"
  [ "$size_before" = "$size_after" ]
  [ "$archive_size_before" = "$archive_size_after" ]
}

@test "archive-task refuses to archive a non-done task" {
  write_tasks <<'EOF'
## CEO Requests

### T001: Active
- **Type:** feature
- **Status:** pending
- **Description:** Should stay put.
EOF
  run "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001
  [ "$status" -eq 0 ]
  [[ "$output" == *"not Status: done"* ]]

  # File untouched.
  grep -q "Should stay put" "$TMP_PROJECT/.redeye/tasks.md"
  [ ! -d "$TMP_PROJECT/docs/tasks-archive" ] || [ -z "$(ls -A "$TMP_PROJECT/docs/tasks-archive" 2>/dev/null)" ]
}

@test "archive-task is a no-op on unknown task id (already-archived semantics)" {
  write_tasks <<'EOF'
## CEO Requests

### T001: X
- **Status:** done
EOF
  run "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T999
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in tasks.md"* ]]
}

@test "archive-task rejects malformed task id" {
  write_tasks <<'EOF'
## CEO Requests
EOF
  run "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" "rm -rf"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid task_id"* ]]
}

@test "archive-task buckets by Merged month, not current month" {
  write_tasks <<'EOF'
## CEO Requests

### T001: Old
- **Type:** feature
- **Status:** done
- **Merged:** 2025-12-15 (iter 1)
- **Description:** Body.
EOF
  "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001 >/dev/null
  [ -f "$TMP_PROJECT/docs/tasks-archive/2025-12.md" ]
  ! grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "archive-task appends to an existing monthly archive" {
  write_tasks <<'EOF'
## CEO Requests

### T001: One
- **Type:** feature
- **Status:** done
- **Merged:** 2026-04-01 (iter 1)
- **Description:** First.

### T002: Two
- **Type:** feature
- **Status:** done
- **Merged:** 2026-04-15 (iter 2)
- **Description:** Second.
EOF
  "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T001 >/dev/null
  "$REDEYE_ROOT/scripts/archive-task.sh" "$TMP_PROJECT" T002 >/dev/null

  # Both gone from tasks.md.
  ! grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "T002" "$TMP_PROJECT/.redeye/tasks.md"

  # Both present in archive.
  archive="$TMP_PROJECT/docs/tasks-archive/2026-04.md"
  grep -q "^### T001: One$" "$archive"
  grep -q "^### T002: Two$" "$archive"
  grep -q "First." "$archive"
  grep -q "Second." "$archive"
}
