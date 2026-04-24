#!/usr/bin/env bash
set -euo pipefail

# archive-wontdo.sh — Sweep every `Status: wontdo` task from `.redeye/tasks.md`
# to `docs/tasks-archive/YYYY-MM.md` (the same archive as done tasks) and
# remove them from tasks.md entirely.
#
# Why: like done tasks, wontdo tasks accumulate in tasks.md and bloat every
# TRIAGE read of the file. Unlike done tasks (archived at MERGE time per
# task-id), wontdo tasks don't have a single trigger point — they get marked
# wontdo by PLAN, by INCORPORATE, by CTO directly when a CEO answer says
# "skip this", or sometimes by the CEO via the dashboard. A sweep at MERGE
# time is the cleanest moment to collect them all.
#
# Bucket: current UTC month. Wontdo tasks usually don't carry a date field
# (no "Merged:" line), so we file them under the month the sweep runs in.
#
# Usage:
#   archive-wontdo.sh <project_root>
#
# Behavior:
#   - Sweeps every task block in tasks.md whose Status field is `wontdo`
#     (canonical) OR `wont-do` / `won't do` (legacy variants the parser
#     accepts).
#   - Buckets all swept tasks under YYYY-MM == current UTC month.
#   - Atomic: writes via tmp + mv for both tasks.md and archive files.
#   - Idempotent: re-runs after success are no-ops (no wontdo entries left).

usage() {
  echo "Usage: archive-wontdo.sh <project_root>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
PROJECT_ROOT="$(cd "$1" && pwd)"

TASKS_FILE="$PROJECT_ROOT/.redeye/tasks.md"
[ -f "$TASKS_FILE" ] || { echo "skip: $TASKS_FILE not found" >&2; exit 0; }

CURRENT_MONTH="$(date -u +%Y-%m)"
ARCHIVE_DIR="$PROJECT_ROOT/docs/tasks-archive"
ARCHIVE_FILE="$ARCHIVE_DIR/${CURRENT_MONTH}.md"

# Use awk to split tasks.md into:
#   - lines to keep (active)
#   - blocks to archive (Status: wontdo / wont-do / won't do)
#
# A "task block" runs from `### T<id>:` to the next `### ` heading or `## `
# section heading or EOF. Lines outside any task block (section headers,
# preamble) pass through to the keep file verbatim.

WORK_DIR="$(mktemp -d)"
# Combined EXIT trap: clean up scratch dir AND release the per-month archive
# lock if it was acquired below. Single trap so the second `trap ... EXIT`
# call later in the script does not silently overwrite this cleanup.
_lock_held=false
ARCHIVE_LOCK=""
cleanup() {
  rm -rf "$WORK_DIR"
  if [ "$_lock_held" = true ] && [ -n "$ARCHIVE_LOCK" ]; then
    rmdir "$ARCHIVE_LOCK" 2>/dev/null || true
  fi
}
trap cleanup EXIT

KEEP_FILE="$WORK_DIR/keep.md"
INDEX_FILE="$WORK_DIR/index.txt"  # one line per archived block: <block_file>

# Pre-create the keep file so the final `mv` always has something to move,
# even when EVERY task in tasks.md was wontdo (awk would otherwise never
# `>>` to keepfile and the file wouldn't exist on disk).
: > "$KEEP_FILE"

awk -v workdir="$WORK_DIR" -v indexfile="$INDEX_FILE" -v keepfile="$KEEP_FILE" '
  function flush_block() {
    if (block == "") return
    if (is_wontdo) {
      file = workdir "/block-" (++blockcount) ".md"
      printf "%s", block > file
      close(file)
      print file >> indexfile
    } else {
      printf "%s", block >> keepfile
    }
    block = ""
    is_wontdo = 0
  }

  # Top-level section header (## Foo, not ### Foo) terminates the current
  # task block (if any) and falls through to keepfile.
  /^## [^#]/ {
    flush_block()
    print $0 >> keepfile
    next
  }

  # Block-start: `### T<id>: ...` or `### CRED-<n>: ...` etc. The wontdo
  # status applies only to T<id>; other ID prefixes are passed through.
  /^### / {
    flush_block()
    block = $0 "\n"
    next
  }

  # Inside a block (or top-level prose between sections)
  {
    if (block != "") {
      block = block $0 "\n"
      # Match Status: wontdo, wont-do, or wont do (case-insensitive — the
      # parser at lib/redeye-parsers.ts:normalizeStatus accepts all three).
      if (tolower($0) ~ /^- \*\*status:\*\*[[:space:]]+(wontdo|wont-do|won'\''t do)([[:space:]]|$)/) {
        is_wontdo = 1
      }
    } else {
      print $0 >> keepfile
    }
  }

  END {
    flush_block()
  }
' "$TASKS_FILE"

if [ ! -s "$INDEX_FILE" ]; then
  echo "skip: no wontdo tasks to archive"
  exit 0
fi

# Append swept blocks to the current-month archive. Create with a header on
# first write of the month.
mkdir -p "$ARCHIVE_DIR"

# Serialize the create-or-append step with a per-month mkdir lock.
# Two concurrent invocations for the same month would both pass the
# `[ ! -f ]` check below and race on tmp+mv, potentially clobbering each
# other or interleaving the tasks.md rewrite with another archiver's read.
# mkdir is atomic on POSIX filesystems. Held through both archive append
# AND the source tasks.md replacement so neither side sees a half-state.
# Lock release on success is below; release on failure is via EXIT trap.
ARCHIVE_LOCK="$PROJECT_ROOT/.redeye-archive-${CURRENT_MONTH}.lock"
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

if [ ! -f "$ARCHIVE_FILE" ]; then
  cat > "$ARCHIVE_FILE.tmp.$$" <<EOF
# Tasks archive — ${CURRENT_MONTH}

Completed and won't-do task bodies, moved here at MERGE time from
\`.redeye/tasks.md\`. Both \`Status: done\` and \`Status: wontdo\` entries
are filed in this single per-month archive.

EOF
  mv "$ARCHIVE_FILE.tmp.$$" "$ARCHIVE_FILE"
fi

while IFS= read -r block_file; do
  cat "$block_file" >> "$ARCHIVE_FILE"
  printf '\n' >> "$ARCHIVE_FILE"
done < "$INDEX_FILE"

# Replace tasks.md with the kept content (atomic). Lock still held —
# another archiver iterating tasks.md must not see a half-rewritten file.
mv "$KEEP_FILE" "$TASKS_FILE.tmp.$$"
mv "$TASKS_FILE.tmp.$$" "$TASKS_FILE"

# Release the lock now that both archive append AND tasks.md rewrite
# are committed.
rmdir "$ARCHIVE_LOCK" 2>/dev/null || true
_lock_held=false

archived_count=$(wc -l < "$INDEX_FILE" | tr -d ' ')
echo "archived: $archived_count wontdo tasks → $ARCHIVE_FILE"
