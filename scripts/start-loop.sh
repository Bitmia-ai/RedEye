#!/usr/bin/env bash
set -euo pipefail

# start-loop.sh — creates the Ralph Loop state file to begin the CTO loop.
# Called by /redeye:start.

PROJECT_ROOT="${1:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
STATE_FILE="$PROJECT_ROOT/.redeye/state.json"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed." >&2
  exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: .redeye/state.json not found. Run /redeye:init first." >&2
  exit 1
fi

ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE")

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "ERROR: .redeye/state.json has invalid iteration value: '$ITERATION'" >&2
  exit 1
fi

# The ralph-loop plugin stop-hook reads ralph-loop.local.md (no leading dot).
# max_iterations: 0 means unlimited. The `iteration: 0` line is required —
# stop-hook.sh's increment is a sed s/^iteration: ...$/iteration: N/ that
# silently no-ops when the line is absent (and ITERATION pins at 0 forever,
# breaking the max_iterations cap).
mkdir -p "$PROJECT_ROOT/.claude"
cat > "$PROJECT_ROOT/.claude/ralph-loop.local.md" << 'PROMPT_EOF'
---
active: true
session_id: redeye-managed
iteration: 0
max_iterations: 0
completion_promise: "CEO DIRECTED STOP"
---
You are the CTO. Run `bash scripts/digest.sh` to generate the control file digest, then read `.redeye/digest.json` for the current state summary. Make the phase routing decision and dispatch the appropriate phase agent. You may chain up to 6 phases per iteration (lightweight phases chain, heavyweight phases exit). Re-run digest.sh before each chained dispatch. Exit cleanly so the loop feeds you fresh context for the next iteration.
PROMPT_EOF

echo $PPID > "$PROJECT_ROOT/.redeye/session-cto.pid"

echo "Ralph Loop started (iteration $ITERATION, unlimited)"
echo "Loop file: $PROJECT_ROOT/.claude/ralph-loop.local.md"
echo "State file: $STATE_FILE"
echo "PID file: $PROJECT_ROOT/.redeye/session-cto.pid (PID=$PPID)"
