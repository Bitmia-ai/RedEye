#!/usr/bin/env bats

# tests/archive-changelog.bats — pin the contract that archive-changelog.sh
# moves prior-month iteration entries to docs/changelog-archive/YYYY-MM.md
# and keeps the current month + header lines in active changelog.md.

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
}

teardown() { teardown_tmp_project; }

write_changelog() {
  cat > "$TMP_PROJECT/.redeye/changelog.md"
}

@test "archives prior-month iterations and keeps current month" {
  current_month="$(date -u +%Y-%m)"
  write_changelog <<EOF
# Changelog

_(Append-only iteration history.)_

## Iteration 10 — 2025-12-15T10:00:00Z
- **Built:** T010 Old work

## Iteration 11 — 2026-01-05T10:00:00Z
- **Built:** T011 January work

## Iteration 99 — ${current_month}-15T12:00:00Z
- **Built:** T099 Current month entry
EOF

  run "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]

  # active changelog: header + current-month entry only
  ! grep -q "Iteration 10" "$TMP_PROJECT/.redeye/changelog.md"
  ! grep -q "Iteration 11" "$TMP_PROJECT/.redeye/changelog.md"
  grep -q "Iteration 99" "$TMP_PROJECT/.redeye/changelog.md"
  grep -q "^# Changelog" "$TMP_PROJECT/.redeye/changelog.md"

  # buckets
  [ -f "$TMP_PROJECT/docs/changelog-archive/2025-12.md" ]
  [ -f "$TMP_PROJECT/docs/changelog-archive/2026-01.md" ]
  grep -q "Iteration 10" "$TMP_PROJECT/docs/changelog-archive/2025-12.md"
  grep -q "Iteration 11" "$TMP_PROJECT/docs/changelog-archive/2026-01.md"
}

@test "no-op when only current-month entries present" {
  current_month="$(date -u +%Y-%m)"
  write_changelog <<EOF
# Changelog

## Iteration 1 — ${current_month}-01T10:00:00Z
- **Built:** T001 Recent
EOF

  run "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no prior-month"* ]]
  [ ! -d "$TMP_PROJECT/docs/changelog-archive" ]
  grep -q "Iteration 1" "$TMP_PROJECT/.redeye/changelog.md"
}

@test "no-op when changelog.md does not exist" {
  rm -f "$TMP_PROJECT/.redeye/changelog.md"
  run "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
}

@test "second run after success is idempotent" {
  write_changelog <<'EOF'
# Changelog

## Iteration 1 — 2025-01-15T10:00:00Z
- **Built:** T001 Old
EOF

  "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  run "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no prior-month"* ]]

  run grep -c "^## Iteration 1 " "$TMP_PROJECT/docs/changelog-archive/2025-01.md"
  [ "$output" = "1" ]
}

@test "iteration with no parseable date stays in active file" {
  current_month="$(date -u +%Y-%m)"
  write_changelog <<EOF
# Changelog

## Iteration 7 — T005: undated entry
- **Built:** Old format

## Iteration 8 — ${current_month}-01T10:00:00Z
- **Built:** Recent
EOF

  run "$REDEYE_ROOT/scripts/archive-changelog.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  grep -q "Iteration 7" "$TMP_PROJECT/.redeye/changelog.md"
  grep -q "Iteration 8" "$TMP_PROJECT/.redeye/changelog.md"
}
