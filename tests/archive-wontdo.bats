#!/usr/bin/env bats

# tests/archive-wontdo.bats — pin the contract that archive-wontdo.sh sweeps
# every wontdo task from `.redeye/tasks.md` to docs/tasks-archive/YYYY-MM.md
# (current UTC month) and leaves active tasks in place. Without this sweep
# tasks.md grows unbounded with rejected items — every TRIAGE iteration
# pays the read cost.

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
}

teardown() { teardown_tmp_project; }

write_tasks() {
  cat > "$TMP_PROJECT/.redeye/tasks.md"
}

current_month() { date -u +%Y-%m; }

@test "archives canonical 'wontdo' tasks and leaves active tasks in place" {
  write_tasks <<'EOF'
# Tasks

## CEO Requests

### T001: Active feature
- **Type:** feature
- **Priority:** P1
- **Status:** pending

### T002: Skipped feature
- **Type:** feature
- **Priority:** P2
- **Status:** wontdo
- **Won't do reason:** out of scope

### T003: Another active
- **Type:** bug
- **Status:** pending-triage
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: 1"* ]]

  # Active tasks survive
  grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "T003" "$TMP_PROJECT/.redeye/tasks.md"
  # Wontdo task is gone from tasks.md
  ! grep -q "T002" "$TMP_PROJECT/.redeye/tasks.md"

  # Wontdo task is in current-month archive
  month="$(current_month)"
  [ -f "$TMP_PROJECT/docs/tasks-archive/${month}.md" ]
  grep -q "T002" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
  grep -q "out of scope" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
}

@test "archives legacy 'wont-do' status variant" {
  write_tasks <<'EOF'
## CEO Requests

### T010: Legacy hyphenated
- **Status:** wont-do
- **Reason:** old format
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: 1"* ]]
  ! grep -q "T010" "$TMP_PROJECT/.redeye/tasks.md"
  month="$(current_month)"
  grep -q "T010" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
}

@test "archives legacy 'won't do' apostrophe variant" {
  write_tasks <<'EOF'
## CEO Requests

### T020: Legacy apostrophe
- **Status:** won't do
- **Reason:** old format
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: 1"* ]]
  ! grep -q "T020" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "archives MULTIPLE wontdo tasks in a single sweep" {
  write_tasks <<'EOF'
## CEO Requests

### T001: Active
- **Status:** pending

### T002: Skip 1
- **Status:** wontdo

### T003: Skip 2
- **Status:** wontdo

### T004: Skip 3
- **Status:** wont-do
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: 3"* ]]

  # Only T001 stays
  grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "T002" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "T003" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "T004" "$TMP_PROJECT/.redeye/tasks.md"

  # All three in archive
  month="$(current_month)"
  for id in T002 T003 T004; do
    grep -q "$id" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
  done
}

@test "no-op when no wontdo tasks present" {
  write_tasks <<'EOF'
## CEO Requests

### T001: Just active
- **Status:** pending
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no wontdo"* ]]
  [ ! -d "$TMP_PROJECT/docs/tasks-archive" ]
  grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "no-op when tasks.md does not exist" {
  rm -f "$TMP_PROJECT/.redeye/tasks.md"
  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
}

@test "second run after success is idempotent" {
  write_tasks <<'EOF'
## CEO Requests

### T100: One shot
- **Status:** wontdo
EOF

  "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT" >/dev/null 2>&1
  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no wontdo"* ]]

  # Archive still has exactly one T100
  month="$(current_month)"
  run grep -c "^### T100" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
  [ "$output" = "1" ]
}

@test "appends to existing archive file (does not clobber done tasks)" {
  month="$(current_month)"
  mkdir -p "$TMP_PROJECT/docs/tasks-archive"
  cat > "$TMP_PROJECT/docs/tasks-archive/${month}.md" <<'EOF'
# Tasks archive — existing

### T050: Pre-existing done task
- **Status:** done
- **Merged:** earlier this month
EOF

  write_tasks <<'EOF'
### T100: New skip
- **Status:** wontdo
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]

  # Both pre-existing done and newly archived wontdo are in the file
  grep -q "T050" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
  grep -q "T100" "$TMP_PROJECT/docs/tasks-archive/${month}.md"
}

@test "preserves the section header (## CEO Requests) and surrounding active items" {
  write_tasks <<'EOF'
# Tasks

## CEO Requests

### T001: Active before
- **Status:** pending

### T002: Skip
- **Status:** wontdo
- **Description:** drop me

### T003: Active after
- **Status:** pending-triage
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "^# Tasks" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^## CEO Requests" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "T001" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "T003" "$TMP_PROJECT/.redeye/tasks.md"
  ! grep -q "T002" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "does NOT archive 'pending', 'planned', 'in-progress', 'blocked', or 'done' tasks" {
  write_tasks <<'EOF'
### T001: Pending
- **Status:** pending

### T002: Planned
- **Status:** planned

### T003: In-progress
- **Status:** in-progress

### T004: Blocked
- **Status:** blocked

### T005: Done
- **Status:** done
- **Merged:** 2026-04-29

### T006: Skip
- **Status:** wontdo
EOF

  run "$REDEYE_ROOT/scripts/archive-wontdo.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"archived: 1"* ]]

  # Only T006 archived; everything else stays in tasks.md
  for id in T001 T002 T003 T004 T005; do
    grep -q "$id" "$TMP_PROJECT/.redeye/tasks.md" || { echo "missing: $id"; return 1; }
  done
  ! grep -q "T006" "$TMP_PROJECT/.redeye/tasks.md"
}
