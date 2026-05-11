#!/usr/bin/env bats

load test_helper

CREATE_Q="$REDEYE_ROOT/scripts/create-question.sh"

setup() {
  setup_tmp_project
  write_state <<'EOF'
{"counters":{"next_task_id":1,"next_q_id":7,"next_cred_id":1,"next_sched_id":1}}
EOF
  cat > "$TMP_PROJECT/.redeye/inbox.md" <<'EOF'
# Inbox

## Questions (Open)

_(No questions yet. The team will ask questions here as they work.)_

## Credentials Needed

_(No credential requests yet.)_

## Answered / Provided

_(Answered questions and provided credentials will be moved here.)_
EOF
}
teardown() { teardown_tmp_project; }

@test "appends a Q-NNN with the next ID and the placeholder is replaced" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "Which library for date formatting?" \
      --default "date-fns"
  [ "$status" -eq 0 ]
  [ "$output" = "Q-007" ]
  grep -q "^### Q-007$"                              "$TMP_PROJECT/.redeye/inbox.md"
  grep -q "^- \*\*Question:\*\* Which library"       "$TMP_PROJECT/.redeye/inbox.md"
  grep -q "^- \*\*Default:\*\* date-fns$"            "$TMP_PROJECT/.redeye/inbox.md"
  ! grep -q "No questions yet"                       "$TMP_PROJECT/.redeye/inbox.md"
}

@test "bumps next_q_id atomically" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --default "y"
  [ "$status" -eq 0 ]
  next="$(jq -r '.counters.next_q_id' "$TMP_PROJECT/.redeye/state.json")"
  [ "$next" = "8" ]
}

@test "second call appends, does not replace placeholder twice" {
  "$CREATE_Q" --project-root "$TMP_PROJECT" --question "first?" --default "a" >/dev/null
  run "$CREATE_Q" --project-root "$TMP_PROJECT" --question "second?" --default "b"
  [ "$status" -eq 0 ]
  [ "$output" = "Q-008" ]
  grep -q "^### Q-007$" "$TMP_PROJECT/.redeye/inbox.md"
  grep -q "^### Q-008$" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "lands INSIDE ## Questions (Open), not after Credentials/Answered" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" --question "x?" --default "y"
  [ "$status" -eq 0 ]
  open_line="$(grep -n '^## Questions (Open)' "$TMP_PROJECT/.redeye/inbox.md" | cut -d: -f1)"
  q_line="$(grep -n '^### Q-007$'              "$TMP_PROJECT/.redeye/inbox.md" | cut -d: -f1)"
  cred_line="$(grep -n '^## Credentials Needed' "$TMP_PROJECT/.redeye/inbox.md" | cut -d: -f1)"
  [ "$open_line" -lt "$q_line" ]
  [ "$q_line" -lt "$cred_line" ]
}

@test "title is appended to the header after Q-NNN" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --title "date library choice" --question "x?" --default "y"
  [ "$status" -eq 0 ]
  grep -q "^### Q-007: date library choice$" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "options + matching default works; spaces are normalised" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "Which library?" \
      --options "date-fns,luxon,dayjs" \
      --default "luxon"
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Options:\*\* date-fns, luxon, dayjs$" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "rejects --default that does not match any --option" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --options "a,b,c" --default "z"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--default must match one of --options"* ]]
}

@test "context line is written when --context provided" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --default "y" --context "Blocks T042; UX decision"
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Context:\*\* Blocks T042; UX decision$" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "blocks-task synthesises a context line if --context absent" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --default "y" --blocks-task T042
  [ "$status" -eq 0 ]
  grep -q "^- \*\*Context:\*\* Blocks T042$" "$TMP_PROJECT/.redeye/inbox.md"
}

@test "rejects malformed --blocks-task" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --default "y" --blocks-task t42
  [ "$status" -ne 0 ]
  [[ "$output" == *"--blocks-task must match"* ]]
}

@test "rejects multi-line --question" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question $'two\nlines' --default "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"single-line"* ]]
}

@test "rejects missing required flags" {
  run "$CREATE_Q" --project-root "$TMP_PROJECT" --default "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--question is required"* ]]
  run "$CREATE_Q" --project-root "$TMP_PROJECT" --question "x?"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--default is required"* ]]
}

@test "dry-run prints the entry and does not write" {
  before_inbox="$(sha1sum "$TMP_PROJECT/.redeye/inbox.md" | cut -d' ' -f1)"
  before_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  run "$CREATE_Q" --project-root "$TMP_PROJECT" \
      --question "x?" --default "y" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"### Q-007"* ]]
  [[ "$output" == *"Question:** x?"* ]]
  after_inbox="$(sha1sum "$TMP_PROJECT/.redeye/inbox.md" | cut -d' ' -f1)"
  after_state="$(sha1sum "$TMP_PROJECT/.redeye/state.json" | cut -d' ' -f1)"
  [ "$before_inbox" = "$after_inbox" ]
  [ "$before_state" = "$after_state" ]
}

@test "rejects when .redeye/inbox.md is missing" {
  rm "$TMP_PROJECT/.redeye/inbox.md"
  run "$CREATE_Q" --project-root "$TMP_PROJECT" --question "x?" --default "y"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing inbox.md"* ]]
}
