#!/usr/bin/env bats

load test_helper

CREATE_TASK="$REDEYE_ROOT/scripts/create-task.sh"

setup() {
  setup_tmp_project
  write_state <<'EOF'
{"counters":{"next_task_id":7,"next_q_id":1,"next_cred_id":1,"next_sched_id":1}}
EOF
  cat > "$TMP_PROJECT/.redeye/tasks.md" <<'EOF'
# Tasks

## CEO Requests
_(User adds items here. Agents never modify this section.)_

### T001: Existing CEO item
- **Type:** feature
- **Priority:** P1
- **Status:** pending

## Discovered
_(Agents append here. VP Product triages during PLAN.)_

## Triaged
_(VP Product moves items here after triage, in priority order.)_
EOF
}
teardown() { teardown_tmp_project; }

# --- Happy paths -----------------------------------------------------------

@test "appends a Discovered task with the next ID" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "Replace ad-hoc retry with backoff" \
      --type tech-debt --priority medium \
      --description "Three call sites duplicate a retry loop."
  [ "$status" -eq 0 ]
  [ "$output" = "T007" ]
  grep -q "^### T007: Replace ad-hoc retry with backoff$" "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^- \*\*Type:\*\* tech-debt$"                   "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^- \*\*Priority:\*\* medium$"                  "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^- \*\*Status:\*\* pending-triage$"            "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^- \*\*Description:\*\*$"                      "$TMP_PROJECT/.redeye/tasks.md"
}

@test "bumps next_task_id atomically" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type test --priority low
  [ "$status" -eq 0 ]
  next="$(jq -r '.counters.next_task_id' "$TMP_PROJECT/.redeye/state.json")"
  [ "$next" = "8" ]
}

@test "allocates monotonic IDs across two consecutive calls" {
  "$CREATE_TASK" --project-root "$TMP_PROJECT" --title "a" --type test --priority low >/dev/null
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" --title "b" --type test --priority low
  [ "$status" -eq 0 ]
  [ "$output" = "T008" ]
  next="$(jq -r '.counters.next_task_id' "$TMP_PROJECT/.redeye/state.json")"
  [ "$next" = "9" ]
}

@test "inserts new task INSIDE the requested section (not after the next one)" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "discovered item" --type test --priority low
  [ "$status" -eq 0 ]
  # Order in the file: ## Discovered header should appear before T007, T007 before ## Triaged
  disc_line="$(grep -n '^## Discovered'   "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  t007_line="$(grep -n '^### T007:'       "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  triaged_line="$(grep -n '^## Triaged'   "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  [ "$disc_line" -lt "$t007_line" ]
  [ "$t007_line" -lt "$triaged_line" ]
}

@test "section ceo lands under ## CEO Requests" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --section ceo --title "ceo item" --type feature --priority P0
  [ "$status" -eq 0 ]
  ceo_line="$(grep -n '^## CEO Requests' "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  t007_line="$(grep -n '^### T007:'      "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  disc_line="$(grep -n '^## Discovered'  "$TMP_PROJECT/.redeye/tasks.md" | cut -d: -f1)"
  [ "$ceo_line" -lt "$t007_line" ]
  [ "$t007_line" -lt "$disc_line" ]
  grep -q "^- \*\*Status:\*\* pending$" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "section triaged defaults status to planned" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --section triaged --title "triaged item" --type feature --priority high
  [ "$status" -eq 0 ]
  awk '/^### T007:/{f=1} f && /^- \*\*Status:\*\*/{print; exit}' \
    "$TMP_PROJECT/.redeye/tasks.md" | grep -q "planned"
}

@test "explicit --status overrides section default" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type test --priority low --status blocked
  [ "$status" -eq 0 ]
  awk '/^### T007:/{f=1} f && /^- \*\*Status:\*\*/{print; exit}' \
    "$TMP_PROJECT/.redeye/tasks.md" | grep -q "blocked"
}

@test "--spec is emitted as a single-line Spec bullet" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type feature --priority P2 --spec docs/specs/T007-x.md
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Spec:\*\* docs/specs/T007-x.md$" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "--summary is emitted as a single-line Summary bullet" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type feature --priority P2 --summary "Shipped retry helper"
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Summary:\*\* Shipped retry helper$" "$TMP_PROJECT/.redeye/tasks.md"
}

@test "multi-line description from --description-file is indented and ends before next section" {
  cat > "$TMP_PROJECT/desc.md" <<'EOF'
Top paragraph.

**Acceptance**

- bullet one
- bullet two
EOF
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type feature --priority P2 \
      --description-file "$TMP_PROJECT/desc.md"
  [ "$status" -eq 0 ]
  # Each line of the description should be 2-space indented under Description.
  grep -q "^  Top paragraph\.$"           "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^  \*\*Acceptance\*\*$"        "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^  - bullet one$"              "$TMP_PROJECT/.redeye/tasks.md"
  grep -q "^  - bullet two$"              "$TMP_PROJECT/.redeye/tasks.md"
}

@test "dry-run prints the block and does not write" {
  before_tasks="$(sha1sum "$TMP_PROJECT/.redeye/tasks.md" | cut -d' ' -f1)"
  before_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title "x" --type feature --priority P2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"### T007: x"* ]]
  after_tasks="$(sha1sum "$TMP_PROJECT/.redeye/tasks.md" | cut -d' ' -f1)"
  after_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  [ "$before_tasks" = "$after_tasks" ]
  [ "$before_state" = "$after_state" ]
}

# --- Rejections ------------------------------------------------------------

@test "rejects unknown --section" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --section discoverd --title x --type feature --priority P2
  [ "$status" -ne 0 ]
  [[ "$output" == *"--section must be one of"* ]]
}

@test "rejects unknown --status" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title x --type feature --priority P2 --status almost
  [ "$status" -ne 0 ]
  [[ "$output" == *"--status must be one of"* ]]
}

@test "rejects multi-line --title" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title $'two\nlines' --type feature --priority P2
  [ "$status" -ne 0 ]
  [[ "$output" == *"single-line"* ]]
}

@test "rejects description with a top-level - **Xxx:** bullet (truncation hazard)" {
  cat > "$TMP_PROJECT/bad-desc.md" <<'EOF'
Top paragraph.

- **Acceptance:** would truncate the Description capture
- **Risk:** likewise
EOF
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title x --type feature --priority P2 \
      --description-file "$TMP_PROJECT/bad-desc.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"truncate the Description field"* ]]
}

@test "rejects missing required flags" {
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" --type feature --priority P2
  [ "$status" -ne 0 ]
  [[ "$output" == *"--title is required"* ]]
}

@test "rejects when .redeye/state.json is missing" {
  rm "$TMP_PROJECT/.redeye/state.json"
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title x --type test --priority low
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing state.json"* ]]
}

@test "rejects when .redeye/tasks.md is missing" {
  rm "$TMP_PROJECT/.redeye/tasks.md"
  run "$CREATE_TASK" --project-root "$TMP_PROJECT" \
      --title x --type test --priority low
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing tasks.md"* ]]
}
