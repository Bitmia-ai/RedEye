#!/usr/bin/env bats

# tests/archive-inbox.bats — pin the contract that archive-inbox.sh moves
# every Q-XXX block in `## Answered / Provided` that has an
# `**Incorporated:**` field to docs/inbox-archive/YYYY-MM.md, leaves open
# questions and un-incorporated answers in inbox.md, and is idempotent.

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
}

teardown() { teardown_tmp_project; }

write_inbox() {
  cat > "$TMP_PROJECT/.redeye/inbox.md"
}

@test "archives incorporated entries and leaves open + un-incorporated in place" {
  write_inbox <<'EOF'
# Inbox

## Questions (Open)

### Q-005: Still pending question
- **From:** CTO
- **Asked:** 2026-04-28

## Credentials Needed

_(No credential requests yet.)_

## Answered / Provided

### Q-001: First incorporated question
- **From:** CTO
- **Answer:** option 2
- **Incorporated:** 2026-04-15 (iter 50)

### Q-002: Answer landed but not incorporated yet
- **From:** CTO
- **Answer:** option 1

### Q-003: Second incorporated question (different month)
- **From:** CTO
- **Answer:** option 3
- **Incorporated:** 2026-03-12 (iter 30)
EOF

  run "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]

  # Q-005 (open) and Q-002 (un-incorporated) survive
  run grep -c '^### Q-' "$TMP_PROJECT/.redeye/inbox.md"
  [ "$output" = "2" ]
  grep -q "Q-005" "$TMP_PROJECT/.redeye/inbox.md"
  grep -q "Q-002" "$TMP_PROJECT/.redeye/inbox.md"
  ! grep -q "Q-001" "$TMP_PROJECT/.redeye/inbox.md"
  ! grep -q "Q-003" "$TMP_PROJECT/.redeye/inbox.md"

  # Q-001 lives in 2026-04 archive, Q-003 in 2026-03
  [ -f "$TMP_PROJECT/docs/inbox-archive/2026-04.md" ]
  [ -f "$TMP_PROJECT/docs/inbox-archive/2026-03.md" ]
  grep -q "Q-001" "$TMP_PROJECT/docs/inbox-archive/2026-04.md"
  grep -q "Q-003" "$TMP_PROJECT/docs/inbox-archive/2026-03.md"
  ! grep -q "Q-001" "$TMP_PROJECT/docs/inbox-archive/2026-03.md"
}

@test "no-op when inbox has no incorporated entries" {
  write_inbox <<'EOF'
## Questions (Open)

### Q-001: Still open
EOF

  run "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no incorporated"* ]]

  [ ! -d "$TMP_PROJECT/docs/inbox-archive" ]
  grep -q "Q-001" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "no-op when inbox.md does not exist" {
  rm -f "$TMP_PROJECT/.redeye/inbox.md"
  run "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
}

@test "second run after success is idempotent" {
  write_inbox <<'EOF'
## Answered / Provided

### Q-001: Already incorporated
- **Answer:** ok
- **Incorporated:** 2026-04-15
EOF

  "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  run "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no incorporated"* ]]

  # archive still has exactly one Q-001
  run grep -c "^### Q-001" "$TMP_PROJECT/docs/inbox-archive/2026-04.md"
  [ "$output" = "1" ]
}

@test "appends to existing archive file" {
  mkdir -p "$TMP_PROJECT/docs/inbox-archive"
  cat > "$TMP_PROJECT/docs/inbox-archive/2026-04.md" <<'EOF'
# Inbox archive — 2026-04

### Q-099: Pre-existing archived entry
- **Answer:** earlier
- **Incorporated:** 2026-04-01
EOF

  write_inbox <<'EOF'
## Answered / Provided

### Q-100: New incorporated entry
- **Answer:** later
- **Incorporated:** 2026-04-25
EOF

  run "$REDEYE_ROOT/scripts/archive-inbox.sh" "$TMP_PROJECT"
  [ "$status" -eq 0 ]

  grep -q "Q-099" "$TMP_PROJECT/docs/inbox-archive/2026-04.md"
  grep -q "Q-100" "$TMP_PROJECT/docs/inbox-archive/2026-04.md"
}
