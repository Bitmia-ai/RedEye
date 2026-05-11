#!/usr/bin/env bash
# create-task.sh — deterministically append a canonical task entry to
# .redeye/tasks.md. Allocates the next T<NNN> ID atomically from state.json
# and inserts at the end of the requested section, in the exact shape the
# Control Tower UI parser and digest.sh expect.
#
# This is the ONLY supported way to create tasks. Hand-edits are accepted
# for status flips (e.g. moving an item from `## Discovered` to `## Triaged`,
# or appending `- **Summary:**` at MERGE) but creation always flows through
# this script so the parser contract is mechanically enforced.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: create-task.sh [OPTIONS]

Deterministically appends a canonical task entry to .redeye/tasks.md.
Allocates the next T<NNN> ID atomically from .redeye/state.json.

Required:
  --title TITLE             Single-line task title (max 200 chars).
  --type TYPE               e.g. feature, bug, tech-debt, docs, infra, ux, security, test.
  --priority PRIORITY       P0|P1|P2|P3 (case-insensitive). The Control Tower
                            UI and the RedEye agents have converged on the
                            P-form. Word forms (critical/high/medium/low) are
                            rejected with a hint to the equivalent P-tier.

Optional:
  --section SECTION         ceo | discovered | triaged | wontdo
                            Default: discovered.
  --status STATUS           One of: pending, pending-triage, planned,
                            in-progress, done, blocked, wontdo.
                            Default per section:
                              ceo         → pending
                              discovered  → pending-triage
                              triaged     → planned
                              wontdo      → wontdo
  --spec PATH               Spec file path (e.g. docs/specs/T042-foo.md).
  --summary TEXT            One-line summary (typically set by MERGE).
  --description TEXT        Description body (single-line).
  --description-file PATH   Read description body from a file (multi-line OK).
  --reason TEXT             One-line reason (typically for wontdo).
  --project-root PATH       Project root (must contain .redeye/). Default: $PWD.
  --dry-run                 Print the assembled block, do not write.
  -h, --help                Show this message.

Exactly one of --description or --description-file may be provided.
Multi-line description content is captured up to the next `- **` field marker
or `### ` heading — the script automatically indents each line by 2 spaces
to keep markdown rendering clean inside the Description field.

On success, prints the allocated task ID (e.g. "T042") to stdout.
EOF
}

# --- Parse args ---
section=discovered
status=""
title=""
type=""
priority=""
spec=""
summary=""
description=""
description_file=""
reason=""
project_root="$PWD"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --section)          section="$2"; shift 2;;
    --title)            title="$2"; shift 2;;
    --type)             type="$2"; shift 2;;
    --priority)         priority="$2"; shift 2;;
    --status)           status="$2"; shift 2;;
    --spec)             spec="$2"; shift 2;;
    --summary)          summary="$2"; shift 2;;
    --description)      description="$2"; shift 2;;
    --description-file) description_file="$2"; shift 2;;
    --reason)           reason="$2"; shift 2;;
    --project-root)     project_root="$2"; shift 2;;
    --dry-run)          dry_run=1; shift;;
    -h|--help)          usage; exit 0;;
    *) echo "create-task.sh: unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
done

err() { echo "create-task.sh: $1" >&2; exit 2; }

[[ -n "$title" ]]    || err "--title is required"
[[ -n "$type" ]]     || err "--type is required"
[[ -n "$priority" ]] || err "--priority is required"

# --- Priority canonicalisation ---
# Single allow-list: P0|P1|P2|P3. The Control Tower UI emits these and the
# RedEye agents are converging on them. Word forms (critical/high/medium/low)
# are still parsed by the CT UI for backward compat but new entries must use
# the P-form. Mapping for migration:
#   P0 ↔ critical
#   P1 ↔ high
#   P2 ↔ medium
#   P3 ↔ low
case "$(echo "$priority" | tr '[:upper:]' '[:lower:]')" in
  p0)       priority=P0 ;;
  p1)       priority=P1 ;;
  p2)       priority=P2 ;;
  p3)       priority=P3 ;;
  critical) err "--priority: use 'P0' (legacy 'critical'); see scripts/create-task.sh --help" ;;
  high)     err "--priority: use 'P1' (legacy 'high'); see scripts/create-task.sh --help" ;;
  medium)   err "--priority: use 'P2' (legacy 'medium'); see scripts/create-task.sh --help" ;;
  low)      err "--priority: use 'P3' (legacy 'low'); see scripts/create-task.sh --help" ;;
  *) err "--priority must be one of: P0, P1, P2, P3 (got: $priority)" ;;
esac

# --- Validate section ---
case "$section" in
  ceo|discovered|triaged|wontdo) :;;
  *) err "--section must be one of: ceo, discovered, triaged, wontdo (got: $section)";;
esac

# --- Default status by section ---
if [[ -z "$status" ]]; then
  case "$section" in
    ceo)        status=pending;;
    discovered) status=pending-triage;;
    triaged)    status=planned;;
    wontdo)     status=wontdo;;
  esac
fi

# --- Validate status against parser allow-list ---
case "$status" in
  pending|pending-triage|planned|in-progress|done|blocked|wontdo) :;;
  *) err "--status must be one of: pending, pending-triage, planned, in-progress, done, blocked, wontdo (got: $status)";;
esac

# --- Title sanity ---
[[ "$title" != *$'\n'* ]] || err "--title must be single-line (no newlines)"
[[ ${#title} -le 200 ]]    || err "--title must be ≤200 chars (got ${#title})"
# Reject characters that could forge markdown headers
[[ "$title" != \#* ]]      || err "--title may not begin with '#'"

# --- Description ---
if [[ -n "$description" && -n "$description_file" ]]; then
  err "pass at most one of --description / --description-file"
fi
if [[ -n "$description_file" ]]; then
  [[ -r "$description_file" ]] || err "--description-file unreadable: $description_file"
  description="$(cat -- "$description_file")"
fi

# --- Project paths ---
tasks_file="$project_root/.redeye/tasks.md"
state_file="$project_root/.redeye/state.json"
lock_file="$project_root/.redeye/.tasks.lock"

[[ -d "$project_root/.redeye" ]] || err "no .redeye/ directory at: $project_root"
[[ -f "$tasks_file" ]]           || err "missing tasks.md at: $tasks_file"
[[ -f "$state_file" ]]           || err "missing state.json at: $state_file"
command -v jq >/dev/null          || err "jq required but not on PATH"

# --- Section header lookup ---
case "$section" in
  ceo)        header_re='^## CEO Requests';;
  discovered) header_re='^## Discovered';;
  triaged)    header_re='^## Triaged';;
  wontdo)     header_re="^## Won'\''t Do";;
esac

# --- Lock (best-effort; bash scripts/lock.sh shim avoids macOS flock(1) absence) ---
acquire_lock() {
  # Try `bash scripts/lock.sh` if available (the redeye-portable wrapper),
  # otherwise fall back to a simple mkdir-based lock.
  if [[ -x "$project_root/scripts/lock.sh" ]] || [[ -x "$(dirname "$0")/lock.sh" ]]; then
    return 0  # caller wraps via lock.sh
  fi
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

# --- Allocate task ID ---
next_id="$(jq -r '.counters.next_task_id // 1' "$state_file")"
[[ "$next_id" =~ ^[0-9]+$ ]] || err "state.json counters.next_task_id is not a number: $next_id"
task_id="$(printf 'T%03d' "$next_id")"

# --- Build the task block ---
build_block() {
  printf '### %s: %s\n' "$task_id" "$title"
  printf -- '- **Type:** %s\n' "$type"
  printf -- '- **Priority:** %s\n' "$priority"
  printf -- '- **Status:** %s\n' "$status"
  if [[ -n "$spec" ]]; then
    printf -- '- **Spec:** %s\n' "$spec"
  fi
  if [[ -n "$summary" ]]; then
    [[ "$summary" != *$'\n'* ]] || err "--summary must be single-line"
    printf -- '- **Summary:** %s\n' "$summary"
  fi
  if [[ -n "$reason" ]]; then
    [[ "$reason" != *$'\n'* ]] || err "--reason must be single-line"
    printf -- '- **Reason:** %s\n' "$reason"
  fi
  if [[ -n "$description" ]]; then
    # Verify no stray `- **Xxx:**` lines inside description (they would
    # truncate the Description capture downstream).
    if printf '%s\n' "$description" | grep -qE '^\s*-[[:space:]]+\*\*[A-Za-z][A-Za-z _-]*:\*\*'; then
      err "description contains a '- **Xxx:**' bullet at line start, which would truncate the Description field. Restructure as '**Xxx**' inline bold."
    fi
    printf -- '- **Description:**\n'
    # Indent each line by 2 spaces. Blank lines stay blank (not "  ").
    printf '%s\n' "$description" | awk '{ if (length($0)==0) print ""; else print "  " $0 }'
  fi
}

block="$(build_block)"

if [[ "$dry_run" -eq 1 ]]; then
  printf '%s\n' "$block"
  echo "(dry-run; counter would advance: $next_id -> $((next_id+1)))" >&2
  exit 0
fi

# --- Insert into tasks.md ---
# Find the line number of the section header. Then find the line number of
# the NEXT `## ` header (or EOF). Insert the block at that position with
# one blank line before and one after.

awk_script='
  BEGIN { found=0; }
  $0 ~ header_re { found=NR; print; next; }
  found && /^## / && NR > found { exit; }
  { print; }
'

header_line="$(awk -v header_re="$header_re" '$0 ~ header_re { print NR; exit }' "$tasks_file" || true)"
[[ -n "$header_line" ]] || err "could not find section header matching: $header_re in $tasks_file"

# Find the line just before the next `## ` (or EOF). That's where we append.
total_lines="$(wc -l < "$tasks_file" | tr -d ' ')"
end_line="$(awk -v start="$header_line" 'NR > start && /^## / { print NR-1; exit }' "$tasks_file" || true)"
if [[ -z "$end_line" ]]; then
  end_line="$total_lines"
fi

# Strip trailing blank lines from the section we're appending to, so we end
# up with exactly one blank line between the previous content and the new block.
# Walk backwards from end_line to find the last non-blank line in the section.
last_non_blank="$end_line"
while [[ "$last_non_blank" -gt "$header_line" ]]; do
  line_content="$(sed -n "${last_non_blank}p" "$tasks_file")"
  if [[ -n "$line_content" ]]; then
    break
  fi
  last_non_blank=$((last_non_blank-1))
done

tmp="$(mktemp "${tasks_file}.tmp.XXXXXX")"
trap 'rm -f "$tmp"; release_lock' EXIT
{
  # Print lines 1..last_non_blank
  sed -n "1,${last_non_blank}p" "$tasks_file"
  printf '\n'
  printf '%s\n' "$block"
  # Print lines (last_non_blank+1)..EOF, but skip leading blank lines
  # (we already emitted exactly one blank line above)
  awk -v skip_until=$((last_non_blank+1)) '
    NR < skip_until { next }
    !started && /^[[:space:]]*$/ { next }
    { started=1; print }
  ' "$tasks_file"
} > "$tmp"

mv "$tmp" "$tasks_file"
trap release_lock EXIT  # restore release-only trap

# --- Bump counter in state.json (atomic temp+rename) ---
state_tmp="$(mktemp "${state_file}.tmp.XXXXXX")"
jq --argjson next $((next_id+1)) '.counters.next_task_id = $next' "$state_file" > "$state_tmp"
mv "$state_tmp" "$state_file"

# --- Output ---
printf '%s\n' "$task_id"
