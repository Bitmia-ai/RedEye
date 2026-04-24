#!/usr/bin/env bash
set -euo pipefail

# Portable file-lock helper. macOS does not ship `flock(1)`; agent prompts
# previously instructed `flock "$LOCK_FILE" git ...` which hard-fails on
# macOS. This wrapper uses a portable `mkdir`-based lockdir scheme that
# works the same on macOS and Linux.
#
# Usage:
#   bash scripts/lock.sh "$LOCK_PATH" command arg arg ...
#
# Behavior:
#   - Acquires an exclusive lock on $LOCK_PATH (creates dir; releases on exit).
#   - Waits up to 30 s for the lock; exits 1 with a clear error on timeout.
#   - Runs the rest of the args via `exec` so the caller observes the
#     command's exit status, stdout, and stderr unmodified.

usage() {
  echo "Usage: lock.sh <lock_path> <command> [args ...]" >&2
  exit 2
}

[ $# -ge 2 ] || usage

LOCK_PATH="$1"; shift

max_wait_seconds=30
waited_tenths=0
while ! mkdir "$LOCK_PATH" 2>/dev/null; do
  sleep 0.1
  waited_tenths=$((waited_tenths + 1))
  if [ "$waited_tenths" -ge "$((max_wait_seconds * 10))" ]; then
    echo "ERROR: lock timeout after ${max_wait_seconds}s on $LOCK_PATH" >&2
    exit 1
  fi
done

# Single-quoted trap body so $LOCK_PATH is resolved when the trap fires, not
# when it's set. The earlier double-quoted form interpolated $LOCK_PATH into
# the trap string and let a path containing a single quote break out and run
# arbitrary code at shell exit.
trap 'rmdir "$LOCK_PATH" 2>/dev/null || true' EXIT

"$@"
