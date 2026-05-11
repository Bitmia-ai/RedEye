#!/usr/bin/env bash
# create-question.sh — deterministically append a canonical Q-entry to
# .redeye/inbox.md `## Questions (Open)`. Allocates the next Q-NNN ID
# atomically from state.json.counters.next_q_id and bumps the counter.
#
# This is the ONLY supported way to create inbox questions. Hand-edits
# are accepted for filling the `- **Answer:**` field on an existing Q
# (the user typing an answer) and for moving Qs to `## Answered / Provided`
# during INCORPORATE — never to create new entries.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-question.sh [OPTIONS]

Deterministically appends a canonical Q-NNN entry to .redeye/inbox.md.
Allocates the next Q-NNN ID atomically from .redeye/state.json.

Required:
  --question TEXT           Single-line question (the actual ask).
  --default TEXT            Single-line default the agent will proceed
                            with if the CEO does not answer.

Optional:
  --title TEXT              One-line header title (appended to ### Q-NNN:).
  --options OPT1,OPT2,...   Comma-separated multiple-choice options.
                            If provided, --default must match one of them.
  --context TEXT            Single-line context — which task/spec this
                            question affects, why it matters now.
  --blocks-task T-NNN       Task ID this question blocks (informational —
                            written into the Context line if --context absent).
  --project-root PATH       Project root (must contain .redeye/). Default: $PWD.
  --dry-run                 Print the assembled entry, do not write.
  -h, --help                Show this message.

On success, prints the allocated question ID (e.g. "Q-007") to stdout.
EOF
}

question=""
default=""
title=""
options=""
context=""
blocks_task=""
project_root="$PWD"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --question)      question="$2"; shift 2;;
    --default)       default="$2"; shift 2;;
    --title)         title="$2"; shift 2;;
    --options)       options="$2"; shift 2;;
    --context)       context="$2"; shift 2;;
    --blocks-task)   blocks_task="$2"; shift 2;;
    --project-root)  project_root="$2"; shift 2;;
    --dry-run)       dry_run=1; shift;;
    -h|--help)       usage; exit 0;;
    *) echo "create-question.sh: unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
done

err() { echo "create-question.sh: $1" >&2; exit 2; }

[[ -n "$question" ]] || err "--question is required"
[[ -n "$default" ]]  || err "--default is required"

# Single-line guards
for var_name in question default title context blocks_task; do
  val="${!var_name:-}"
  if [[ -n "$val" && "$val" == *$'\n'* ]]; then
    err "--$var_name must be single-line (no newlines)"
  fi
done
[[ ${#question} -le 500 ]] || err "--question must be ≤500 chars"

# Options validation
if [[ -n "$options" ]]; then
  [[ "$options" != *$'\n'* ]] || err "--options must be single-line"
  # Check that --default matches one of the options (case-insensitive trim)
  default_trim="$(echo "$default" | xargs)"
  found=0
  IFS=',' read -ra opt_arr <<< "$options"
  for opt in "${opt_arr[@]}"; do
    opt_trim="$(echo "$opt" | xargs)"
    [[ "$opt_trim" == "$default_trim" ]] && { found=1; break; }
  done
  [[ "$found" -eq 1 ]] || err "--default must match one of --options (got default='$default', options='$options')"
fi

# Blocks-task format
if [[ -n "$blocks_task" ]]; then
  [[ "$blocks_task" =~ ^T[0-9]+$ ]] || err "--blocks-task must match T<NNN> (got: $blocks_task)"
fi

# Project paths
inbox_file="$project_root/.redeye/inbox.md"
state_file="$project_root/.redeye/state.json"
lock_file="$project_root/.redeye/.inbox.lock"

[[ -d "$project_root/.redeye" ]] || err "no .redeye/ directory at: $project_root"
[[ -f "$inbox_file" ]]           || err "missing inbox.md at: $inbox_file"
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
next_id="$(jq -r '.counters.next_q_id // 1' "$state_file")"
[[ "$next_id" =~ ^[0-9]+$ ]] || err "state.json counters.next_q_id is not a number: $next_id"
q_id="$(printf 'Q-%03d' "$next_id")"

# Build the block
build_block() {
  if [[ -n "$title" ]]; then
    printf '### %s: %s\n' "$q_id" "$title"
  else
    printf '### %s\n' "$q_id"
  fi
  printf -- '- **Question:** %s\n' "$question"
  if [[ -n "$options" ]]; then
    # Normalise spacing: "a,b,c" -> "a, b, c"
    normalised="$(echo "$options" | sed 's/[[:space:]]*,[[:space:]]*/, /g')"
    printf -- '- **Options:** %s\n' "$normalised"
  fi
  printf -- '- **Default:** %s\n' "$default"
  if [[ -n "$context" ]]; then
    printf -- '- **Context:** %s\n' "$context"
  elif [[ -n "$blocks_task" ]]; then
    printf -- '- **Context:** Blocks %s\n' "$blocks_task"
  fi
}

block="$(build_block)"

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n' "$block"
  echo "(dry-run; counter would advance: $next_id -> $((next_id+1)))" >&2
  exit 0
fi

# Find `## Questions (Open)` and insert at end of that section
header_line="$(grep -nFx '## Questions (Open)' "$inbox_file" | head -1 | cut -d: -f1)"
[[ -n "$header_line" ]] || err "could not find section header: ## Questions (Open) in $inbox_file"

end_line="$(awk -v start="$header_line" 'NR > start && /^## / { print NR-1; exit }' "$inbox_file" || true)"
total_lines="$(wc -l < "$inbox_file" | tr -d ' ')"
[[ -z "$end_line" ]] && end_line="$total_lines"

# Walk back to the last non-blank line of the section
last_non_blank="$end_line"
while [[ "$last_non_blank" -gt "$header_line" ]]; do
  line_content="$(sed -n "${last_non_blank}p" "$inbox_file")"
  [[ -n "$line_content" ]] && break
  last_non_blank=$((last_non_blank-1))
done

# If the section is empty (placeholder italic only or just header), the
# last_non_blank line will be the placeholder. Detect it and replace
# rather than appending after it.
section_only_has_placeholder=0
if [[ "$last_non_blank" -gt "$header_line" ]]; then
  ph_line="$(sed -n "${last_non_blank}p" "$inbox_file")"
  if [[ "$ph_line" =~ ^_\(.*\)_[[:space:]]*$ ]]; then
    section_only_has_placeholder=1
  fi
fi

tmp="$(mktemp "${inbox_file}.tmp.XXXXXX")"
trap 'rm -f "$tmp"; release_lock' EXIT
{
  if [[ "$section_only_has_placeholder" -eq 1 ]]; then
    sed -n "1,$((last_non_blank-1))p" "$inbox_file"
    printf '%s\n' "$block"
  else
    sed -n "1,${last_non_blank}p" "$inbox_file"
    printf '\n'
    printf '%s\n' "$block"
  fi
  awk -v skip_until=$((last_non_blank+1)) '
    NR < skip_until { next }
    !started && /^[[:space:]]*$/ { next }
    { started=1; print }
  ' "$inbox_file"
} > "$tmp"

mv "$tmp" "$inbox_file"
trap release_lock EXIT

# Bump counter
state_tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
jq --argjson next $((next_id+1)) '.counters.next_q_id = $next' "$state_file" > "$state_tmp"
mv "$state_tmp" "$state_file"

printf '%s\n' "$q_id"
