#!/usr/bin/env bats

# scripts/lock.sh is the portable mkdir-based lock wrapper. macOS has no
# flock(1), so every git-on-main write in merge.md / triage.md routes
# through this helper. A regression here can corrupt main overnight.

load test_helper

setup() {
  TMP_DIR="$(mktemp -d)"
  LOCK="$TMP_DIR/lock.d"
  export TMP_DIR LOCK
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

@test "lock.sh acquires when free, runs the command, releases the lockdir" {
  run "$REDEYE_ROOT/scripts/lock.sh" "$LOCK" echo "ran"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran"* ]]
  [ ! -d "$LOCK" ]
}

@test "lock.sh passes through the wrapped command's exit code" {
  run "$REDEYE_ROOT/scripts/lock.sh" "$LOCK" bash -c 'exit 7'
  [ "$status" -eq 7 ]
  [ ! -d "$LOCK" ]
}

@test "lock.sh blocks while another holder keeps the lockdir" {
  # Pre-create the lockdir, launch lock.sh in the background, give it a
  # moment to enter the wait loop, then kill it. The wrapped command must
  # never have run (lockdir held throughout).
  mkdir "$LOCK"
  "$REDEYE_ROOT/scripts/lock.sh" "$LOCK" touch "$TMP_DIR/should-not-exist" &
  pid=$!
  sleep 0.3
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ ! -e "$TMP_DIR/should-not-exist" ]
  rmdir "$LOCK"
}

@test "lock.sh releases the lockdir even when the wrapped command fails" {
  run "$REDEYE_ROOT/scripts/lock.sh" "$LOCK" bash -c 'exit 42'
  [ "$status" -eq 42 ]
  [ ! -d "$LOCK" ]
}

@test "lock.sh is safe against single-quotes in the lockdir path" {
  # Earlier `trap "rmdir '$LOCK_PATH' ..."` (double-quoted trap body)
  # would have let a path containing `'` break out and execute arbitrary
  # code. The single-quoted-trap-body fix should make this benign.
  TRICKY="$TMP_DIR/lock' touch /tmp/redeye-pwn-$$ ; '"
  run "$REDEYE_ROOT/scripts/lock.sh" "$TRICKY" true
  # Either it acquires (path is unusual but valid bytes) or it fails
  # cleanly; either way the injection-attempt sentinel must NOT exist.
  [ ! -e "/tmp/redeye-pwn-$$" ]
}

@test "lock.sh requires lock-path and command arguments" {
  run "$REDEYE_ROOT/scripts/lock.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
