#!/usr/bin/env bash
# create-schedule.sh — deterministically append a canonical SCHED-NNN
# entry to .redeye/schedules.md. Allocates the next SCHED-NNN ID atomically
# from state.json.counters.next_sched_id and bumps the counter.
#
# This is the ONLY supported way to create scheduled tasks. Hand-edits are
# accepted for updating the `- **Last run:**` timestamp on an existing
# entry (the SCHEDULES agent does this every iteration) — never for
# creating new entries.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-schedule.sh [OPTIONS]

Deterministically appends a canonical SCHED-NNN entry to .redeye/schedules.md.
Allocates the next SCHED-NNN ID atomically from .redeye/state.json.

Required:
  --title TITLE             Single-line schedule title.
  --frequency FREQ          Recurrence as "every <N><unit>" where unit is
                            h (hour), d (day), or w (week). Min 1h.
                            Examples: "every 1h", "every 6h", "every 1d", "every 1w".
  --task-step STEP          A single step description. Repeat the flag for
                            additional steps; the script writes them as a
                            numbered list under - **Task:**.

Optional:
  --assigned-to ROLES       Comma-separated role list (default: documenter).
  --last-run ISO            Initial Last run timestamp. Default: "1970-01-01T00:00:00Z"
                            (causes the schedule to fire on the next iteration).
  --project-root PATH       Project root (must contain .redeye/). Default: $PWD.
  --dry-run                 Print the assembled entry, do not write.
  -h, --help                Show this message.

On success, prints the allocated schedule ID (e.g. "SCHED-003") to stdout.
EOF
}

title=""
frequency=""
assigned_to="documenter"
last_run="1970-01-01T00:00:00Z"
project_root="$PWD"
dry_run=0
declare -a task_steps=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)         title="$2"; shift 2;;
    --frequency)     frequency="$2"; shift 2;;
    --task-step)     task_steps+=("$2"); shift 2;;
    --assigned-to)   assigned_to="$2"; shift 2;;
    --last-run)      last_run="$2"; shift 2;;
    --project-root)  project_root="$2"; shift 2;;
    --dry-run)       dry_run=1; shift;;
    -h|--help)       usage; exit 0;;
    *) echo "create-schedule.sh: unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
done

err() { echo "create-schedule.sh: $1" >&2; exit 2; }

[[ -n "$title" ]]              || err "--title is required"
[[ -n "$frequency" ]]          || err "--frequency is required"
[[ ${#task_steps[@]} -gt 0 ]]  || err "--task-step is required (pass at least one)"

# Single-line guards
for var_name in title frequency assigned_to last_run; do
  val="${!var_name:-}"
  if [[ -n "$val" && "$val" == *$'\n'* ]]; then
    err "--$var_name must be single-line (no newlines)"
  fi
done
[[ "$title" != \#* ]] || err "--title may not begin with '#'"

# Frequency format — must match the parser's regex AND clear the 1h floor
if ! [[ "$frequency" =~ ^every[[:space:]]+([0-9]+(\.[0-9]+)?)[[:space:]]*([hdw])$ ]]; then
  err "--frequency must match 'every <N><h|d|w>' (got: '$frequency')"
fi
freq_n="${BASH_REMATCH[1]}"
freq_u="${BASH_REMATCH[3]}"
case "$freq_u" in
  h) min_ok="$(awk -v n="$freq_n" 'BEGIN{print (n >= 1) ? 1 : 0}')";;
  d|w) min_ok=1;;
esac
[[ "$min_ok" -eq 1 ]] || err "--frequency floor is 1 hour (got: '$frequency')"

# Last run sanity (ISO 8601 — yyyy-mm-ddThh:mm:ssZ)
if ! [[ "$last_run" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
  err "--last-run must be ISO 8601 (yyyy-mm-ddThh:mm:ssZ); got: '$last_run'"
fi

# Each step single-line
for step in "${task_steps[@]}"; do
  [[ "$step" != *$'\n'* ]] || err "--task-step must be single-line (no newlines)"
done

# Project paths
sched_file="$project_root/.redeye/schedules.md"
state_file="$project_root/.redeye/state.json"
lock_file="$project_root/.redeye/.schedules.lock"

[[ -d "$project_root/.redeye" ]] || err "no .redeye/ directory at: $project_root"
[[ -f "$sched_file" ]]           || err "missing schedules.md at: $sched_file"
[[ -f "$state_file" ]]           || err "missing state.json at: $state_file"
command -v jq >/dev/null          || err "jq required but not on PATH"

# Lock
acquire_lock() {
  local tries=50
  while ! mkdir "$lock_file.d" 2>/dev/null; do
    tries=$((tries-1))
    [[ $tries -gt 0 ]] || err "could not acquire lock $lock_file.d after 5s"
    sleep 0.1
  done
}
release_lock() { rmdir "$lock_file.d" 2>/dev/null || true; }

acquire_lock
trap release_lock EXIT

# Allocate ID
next_id="$(jq -r '.counters.next_sched_id // 1' "$state_file")"
[[ "$next_id" =~ ^[0-9]+$ ]] || err "state.json counters.next_sched_id is not a number: $next_id"
sched_id="$(printf 'SCHED-%03d' "$next_id")"

# Build the block
build_block() {
  printf '### %s: %s\n' "$sched_id" "$title"
  printf -- '- **Frequency:** %s\n' "$frequency"
  printf -- '- **Last run:** %s\n' "$last_run"
  printf -- '- **Task:**\n'
  local i=1
  for step in "${task_steps[@]}"; do
    printf '  %d. %s\n' "$i" "$step"
    i=$((i+1))
  done
  printf -- '- **Assigned to:** %s\n' "$assigned_to"
}

block="$(build_block)"

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n' "$block"
  echo "(dry-run; counter would advance: $next_id -> $((next_id+1)))" >&2
  exit 0
fi

# schedules.md has no `## ` sections — entries are appended at the end.
# Strip trailing blank lines, then append the block separated by one blank line.
total_lines="$(wc -l < "$sched_file" | tr -d ' ')"
last_non_blank="$total_lines"
while [[ "$last_non_blank" -gt 0 ]]; do
  line_content="$(sed -n "${last_non_blank}p" "$sched_file")"
  [[ -n "$line_content" ]] && break
  last_non_blank=$((last_non_blank-1))
done
[[ "$last_non_blank" -gt 0 ]] || err "schedules.md appears empty"

tmp="$(mktemp "${sched_file}.tmp.XXXXXX")"
trap 'rm -f "$tmp"; release_lock' EXIT
{
  sed -n "1,${last_non_blank}p" "$sched_file"
  printf '\n'
  printf '%s\n' "$block"
} > "$tmp"
mv "$tmp" "$sched_file"
trap release_lock EXIT

# Bump counter
state_tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
jq --argjson next $((next_id+1)) '.counters.next_sched_id = $next' "$state_file" > "$state_tmp"
mv "$state_tmp" "$state_file"

printf '%s\n' "$sched_id"
