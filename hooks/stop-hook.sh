#!/usr/bin/env bash
set -euo pipefail

# RedEye Stop Hook — resilient loop continuation.
# Unlike ralph-loop's hook, this NEVER deletes the loop file on error.
# It always tries to continue the loop. Only stops on explicit CEO STOP.

if [[ "${REDEYE_DEBUG:-}" == "1" ]]; then
  DEBUG_LOG="${REDEYE_DEBUG_LOG:-/tmp/redeye-stop-hook-debug.log}"
  debug_log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" >> "$DEBUG_LOG"; }
else
  debug_log() { :; }
fi
debug_log "=== Stop hook invoked ==="

if [[ "${REDEYE_LOOP_EXTERNAL:-}" == "1" ]]; then
  debug_log "DECISION: exit (external loop runner)"
  exit 0
fi

HOOK_INPUT=$(cat)

PROJECT_ROOT="$(pwd)"
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -f "$PROJECT_ROOT/.redeye/state.json" ] && break
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

# Guard: upward traversal hit / without finding .redeye/state.json — no
# active redeye project in this directory tree. Exit cleanly without
# writing any files (otherwise we'd write pid / loop files at root paths).
if [ "$PROJECT_ROOT" = "/" ] && [ ! -f "$PROJECT_ROOT/.redeye/state.json" ]; then
  debug_log "DECISION: exit (no .redeye/state.json found up to /)"
  exit 0
fi

LOOP_FILE="$PROJECT_ROOT/.claude/ralph-loop.local.md"

if [[ ! -f "$LOOP_FILE" ]]; then
  debug_log "DECISION: exit (no loop file)"
  exit 0
fi

echo $PPID > "$PROJECT_ROOT/.redeye/session-cto.pid" 2>/dev/null || true

deactivate_and_exit() {
  sed "s/^active: true/active: false/" "$LOOP_FILE" > "${LOOP_FILE}.tmp.$$"
  mv "${LOOP_FILE}.tmp.$$" "$LOOP_FILE"
  rm -f "$PROJECT_ROOT/.redeye/session-cto.pid" 2>/dev/null || true
  exit 0
}

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$LOOP_FILE")
ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')

if [[ "$ACTIVE" != "true" ]]; then
  debug_log "DECISION: exit (not active)"
  rm -f "$PROJECT_ROOT/.redeye/session-cto.pid" 2>/dev/null || true
  exit 0
fi

ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# Default to sane values on parse failure — NEVER stop on parse error.
[[ ! "$ITERATION" =~ ^[0-9]+$ ]] && ITERATION=0
[[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] && MAX_ITERATIONS=0

debug_log "iteration=$ITERATION max=$MAX_ITERATIONS"

# 0 = unlimited
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  debug_log "DECISION: exit (max iterations)"
  deactivate_and_exit
fi

STEERING_FILE="$PROJECT_ROOT/.redeye/steering.md"
if [[ -f "$STEERING_FILE" ]] && grep -qiE -- '^\s*STOP\b' "$STEERING_FILE"; then
  debug_log "DECISION: exit (STOP directive)"
  deactivate_and_exit
fi

# Check completion promise in transcript (best effort).
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path' 2>/dev/null || echo "")
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && -n "$COMPLETION_PROMISE" && "$COMPLETION_PROMISE" != "null" ]]; then
  LAST_OUTPUT=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -50 | jq -rs 'map(.message.content[]? | select(.type == "text") | .text) | last // ""' 2>/dev/null || echo "")
  if [[ -n "$LAST_OUTPUT" ]]; then
    PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
    if [[ -n "$PROMISE_TEXT" && "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
      debug_log "DECISION: exit (promise matched)"
      deactivate_and_exit
    fi
  fi
fi

NEXT_ITER=$((ITERATION + 1))
TEMP_FILE="${LOOP_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITER/" "$LOOP_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$LOOP_FILE"

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$LOOP_FILE")
if [[ -z "$PROMPT_TEXT" ]]; then
  debug_log "DECISION: exit (no prompt text)"
  exit 0
fi

SYSTEM_MSG="RedEye iteration $NEXT_ITER | To stop: output <promise>$COMPLETION_PROMISE</promise>"

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{"decision":"block","reason":$prompt,"systemMessage":$msg}'

debug_log "DECISION: block (iteration $NEXT_ITER)"
exit 0
