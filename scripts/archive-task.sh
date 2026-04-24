#!/usr/bin/env bash
set -euo pipefail

# archive-task.sh — Move a completed task's full body from `.redeye/tasks.md`
# to `docs/tasks-archive/YYYY-MM.md` and remove it from tasks.md entirely.
#
# Why: tasks.md grows unbounded as RedEye merges work. TRIAGE reads the file
# every iteration; bloated done-history eats context. After archival the
# task block is gone from tasks.md — no stub, no marker — and the full body
# lives in the dated archive file. Dedup of "this task already shipped"
# isn't a TRIAGE concern: the rare case where the user re-files an already-
# done task is caught downstream in PLAN, which marks it done with a
# Summary noting the duplicate.
#
# Usage:
#   archive-task.sh <project_root> <task_id>
#
# Behavior:
#   - No-op if the task is not Status: done (refuses to archive in-progress work).
#   - No-op if the task is not in tasks.md (it's already been archived).
#   - Atomic: writes to .tmp + mv for both tasks.md and the archive file.
#   - Idempotent under retry: a second invocation after success exits 0.

usage() {
  echo "Usage: archive-task.sh <project_root> <task_id>" >&2
  exit 2
}

[ $# -eq 2 ] || usage
PROJECT_ROOT="$(cd "$1" && pwd)"
TASK_ID="$2"

if ! [[ "$TASK_ID" =~ ^T[0-9]+$ ]]; then
  echo "ERROR: invalid task_id '$TASK_ID' — expected T<digits>" >&2
  exit 1
fi

TASKS_FILE="$PROJECT_ROOT/.redeye/tasks.md"
[ -f "$TASKS_FILE" ] || { echo "ERROR: $TASKS_FILE not found" >&2; exit 1; }

# Find the line range of the task block: from `### TASK_ID:` to the next
# `### ` heading (or `## ` section heading) or EOF. Absent = already archived.
start_line=$(grep -nE "^### ${TASK_ID}:" "$TASKS_FILE" | head -1 | cut -d: -f1 || true)
if [ -z "$start_line" ]; then
  echo "skip: $TASK_ID not in tasks.md (already archived or never existed)" >&2
  exit 0
fi

# Next heading line after start_line (### or ## but not ###).
next_heading=$(awk -v start="$start_line" '
  NR > start && (/^### / || /^## [^#]/) { print NR; exit }
' "$TASKS_FILE")

if [ -z "$next_heading" ]; then
  end_line=$(wc -l < "$TASKS_FILE" | tr -d ' ')
else
  end_line=$((next_heading - 1))
fi

# Extract the block.
block="$(sed -n "${start_line},${end_line}p" "$TASKS_FILE")"

# Refuse to archive in-progress work.
if ! echo "$block" | grep -qE "^- \*\*Status:\*\*[[:space:]]+done"; then
  echo "skip: $TASK_ID is not Status: done — not archiving" >&2
  exit 0
fi

# Pull the Merged date so we can bucket the archive file by month.
pickfield() {
  local field="$1"
  echo "$block" | sed -n "s/^- \*\*${field}:\*\*[[:space:]]*\(.*\)$/\1/p" | head -1
}
merged="$(pickfield Merged)"
if [ -z "$merged" ]; then
  merged="$(date -u +%Y-%m-%d)"
fi

# Bucket: YYYY-MM. Accept either "2026-04-28 (iter 145)" or "iteration 145"
# format. If we can't extract a date, fall back to current month.
month=$(echo "$merged" | grep -oE '^[0-9]{4}-[0-9]{2}' || echo "")
if [ -z "$month" ]; then
  month="$(date -u +%Y-%m)"
fi

ARCHIVE_DIR="$PROJECT_ROOT/docs/tasks-archive"
ARCHIVE_FILE="$ARCHIVE_DIR/${month}.md"
mkdir -p "$ARCHIVE_DIR"

# Serialize the create-or-append step with a per-month mkdir lock.
# Two concurrent invocations for the same month would both pass the
# `[ ! -f ]` check below and the second `mv` would clobber the first
# task's body. mkdir is atomic on POSIX filesystems.
ARCHIVE_LOCK="$PROJECT_ROOT/.redeye-archive-${month}.lock"
_lock_held=false
_lock_waited=0
while ! mkdir "$ARCHIVE_LOCK" 2>/dev/null; do
  sleep 0.1
  _lock_waited=$((_lock_waited + 1))
  if [ "$_lock_waited" -ge 300 ]; then
    echo "ERROR: lock timeout after 30s on $ARCHIVE_LOCK" >&2
    exit 1
  fi
done
_lock_held=true
trap 'if [ "$_lock_held" = true ]; then rmdir "$ARCHIVE_LOCK" 2>/dev/null || true; fi' EXIT

# Inside the lock: test once, init header if missing, then append.
if [ ! -f "$ARCHIVE_FILE" ]; then
  cat > "$ARCHIVE_FILE.tmp.$$" <<EOF
# Tasks archive — ${month}

Completed and won't-do task bodies, moved here at MERGE time from
\`.redeye/tasks.md\`.

EOF
  mv "$ARCHIVE_FILE.tmp.$$" "$ARCHIVE_FILE"
fi
{
  printf '%s\n\n' "$block"
} >> "$ARCHIVE_FILE"

# Remove the task block from tasks.md entirely. Atomic via tmp+mv.
# IMPORTANT: keep the lock held through this rewrite. Two concurrent
# invocations on different tasks both read tasks.md before this point
# and compute their own line ranges; without the lock they would each
# write tasks.md from stale line numbers, with the second mv potentially
# losing the first task's removal.
TASKS_TMP="$TASKS_FILE.tmp.$$"
{
  if [ "$start_line" -gt 1 ]; then
    sed -n "1,$((start_line - 1))p" "$TASKS_FILE"
  fi
  total_lines=$(wc -l < "$TASKS_FILE" | tr -d ' ')
  if [ "$end_line" -lt "$total_lines" ]; then
    sed -n "$((end_line + 1)),${total_lines}p" "$TASKS_FILE"
  fi
} > "$TASKS_TMP"

mv "$TASKS_TMP" "$TASKS_FILE"

# Release the lock now that both archive append AND tasks.md rewrite
# are committed.
rmdir "$ARCHIVE_LOCK" 2>/dev/null || true
_lock_held=false

echo "archived: $TASK_ID → $ARCHIVE_FILE"
