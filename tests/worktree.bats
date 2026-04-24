#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp_project
  cd "$TMP_PROJECT"
  echo "hello" > README.md
  git add README.md
  git -c commit.gpgsign=false commit -q -m "initial"
  echo '{"phase":"TRIAGE","iteration":0}' > .redeye/state.json
}

teardown() { teardown_tmp_project; }

@test "worktree create rejects non-numeric task id" {
  run "$REDEYE_ROOT/scripts/worktree.sh" create "$TMP_PROJECT" "abc"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid task_id"* ]]
}

@test "worktree create succeeds and updates state.json" {
  run "$REDEYE_ROOT/scripts/worktree.sh" create "$TMP_PROJECT" "1"
  [ "$status" -eq 0 ]
  [ -d "$TMP_PROJECT/.worktrees/T1" ]
  branch="$(jq -r '.worktree_branch' "$TMP_PROJECT/.redeye/state.json")"
  [ "$branch" = "redeye/T1" ]
  path="$(jq -r '.worktree_path' "$TMP_PROJECT/.redeye/state.json")"
  [ "$path" = "$TMP_PROJECT/.worktrees/T1" ]
}

@test "worktree create adds .worktrees/ to .gitignore" {
  run "$REDEYE_ROOT/scripts/worktree.sh" create "$TMP_PROJECT" "2"
  [ "$status" -eq 0 ]
  grep -qF '.worktrees/' "$TMP_PROJECT/.gitignore"
}

@test "worktree create fails if directory already exists" {
  mkdir -p "$TMP_PROJECT/.worktrees/T3"
  run "$REDEYE_ROOT/scripts/worktree.sh" create "$TMP_PROJECT" "3"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "worktree teardown removes worktree and clears state" {
  "$REDEYE_ROOT/scripts/worktree.sh" create "$TMP_PROJECT" "4"
  [ -d "$TMP_PROJECT/.worktrees/T4" ]

  run "$REDEYE_ROOT/scripts/worktree.sh" teardown "$TMP_PROJECT"
  [ "$status" -eq 0 ]
  [ ! -d "$TMP_PROJECT/.worktrees/T4" ]

  branch="$(jq -r '.worktree_branch' "$TMP_PROJECT/.redeye/state.json")"
  [ "$branch" = "null" ]
}

@test "worktree teardown is a no-op when nothing is recorded" {
  run "$REDEYE_ROOT/scripts/worktree.sh" teardown "$TMP_PROJECT"
  [ "$status" -eq 0 ]
}

@test "worktree teardown refuses a branch outside the redeye/T* prefix" {
  echo '{"phase":"TRIAGE","iteration":0,"worktree_branch":"main","worktree_path":""}' \
    > "$TMP_PROJECT/.redeye/state.json"
  run "$REDEYE_ROOT/scripts/worktree.sh" teardown "$TMP_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to delete branch"* ]]
}

@test "worktree teardown refuses a path outside .worktrees/" {
  echo '{"phase":"TRIAGE","iteration":0,"worktree_branch":"redeye/T7","worktree_path":"/tmp/escape"}' \
    > "$TMP_PROJECT/.redeye/state.json"
  run "$REDEYE_ROOT/scripts/worktree.sh" teardown "$TMP_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to remove worktree"* ]]
}
