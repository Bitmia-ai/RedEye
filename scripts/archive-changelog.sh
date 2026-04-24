#!/usr/bin/env bash
set -euo pipefail

# archive-changelog.sh — Move prior-month iteration entries from
# `.redeye/changelog.md` to `docs/changelog-archive/YYYY-MM.md`.
#
# Why: changelog.md is append-only (VERIFY adds an entry every iteration).
# It's not read by RedEye agents, but Control Tower polls and parses it
# every 10s, and the file grows monotonically. Bucketing by month keeps
# the active file at ~30 entries max, with full history preserved in
# dated archive files.
#
# Usage:
#   archive-changelog.sh <project_root>
#
# Behavior:
#   - Identifies each `## Iteration N — ISO-TIMESTAMP` block.
#   - Moves any block whose YYYY-MM is BEFORE the current UTC month to
#     `docs/changelog-archive/YYYY-MM.md`.
#   - Header lines (lines before the first `## Iteration`) and the current
#     month's blocks are kept in active changelog.md.
#   - Idempotent: re-runs do nothing if no prior-month entries remain.
#   - Atomic: tmp + mv for both files.

usage() {
  echo "Usage: archive-changelog.sh <project_root>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
PROJECT_ROOT="$(cd "$1" && pwd)"

CHANGELOG_FILE="$PROJECT_ROOT/.redeye/changelog.md"
[ -f "$CHANGELOG_FILE" ] || { echo "skip: $CHANGELOG_FILE not found" >&2; exit 0; }

CURRENT_MONTH="$(date -u +%Y-%m)"
ARCHIVE_DIR="$PROJECT_ROOT/docs/changelog-archive"

WORK_DIR="$(mktemp -d)"
# Combined EXIT trap: clean up scratch dir AND release the per-month archive
# lock if one was acquired (and not yet released) when we exit early or fail.
# Single trap so neither side silently overwrites the other.
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
INDEX_FILE="$WORK_DIR/index.txt"

# Pre-create keep file so the final `mv` succeeds even if every block
# was archived (awk would otherwise never `>>` to keepfile).
: > "$KEEP_FILE"

awk -v workdir="$WORK_DIR" -v indexfile="$INDEX_FILE" -v keepfile="$KEEP_FILE" \
    -v current="$CURRENT_MONTH" '
  function flush_block() {
    if (block == "") return
    if (block_bucket != "" && block_bucket < current) {
      file = workdir "/block-" (++blockcount) ".md"
      printf "%s", block > file
      close(file)
      print block_bucket "\t" file >> indexfile
    } else {
      printf "%s", block >> keepfile
    }
    block = ""
    block_bucket = ""
  }

  /^## Iteration / {
    flush_block()
    block = $0 "\n"
    # Match YYYY-MM in the rest of the line (typically `— 2026-04-24T...`)
    if (match($0, /[0-9]{4}-[0-9]{2}/)) {
      block_bucket = substr($0, RSTART, 7)
    } else {
      # No date in header — keep in active file (cannot bucket safely).
      block_bucket = current
    }
    next
  }

  {
    if (block != "") {
      block = block $0 "\n"
    } else {
      print $0 >> keepfile
    }
  }

  END {
    flush_block()
  }
' "$CHANGELOG_FILE"

if [ ! -s "$INDEX_FILE" ]; then
  echo "skip: no prior-month iterations to archive"
  exit 0
fi

# Group blocks by bucket and append to archive files. For each bucket,
# acquire a per-month mkdir lock around the archive create-or-append so two
# concurrent invocations writing into the same month don't both pass the
# `[ ! -f ]` check, race on tmp+mv, and clobber each other. mkdir is atomic
# on POSIX. Lock is per-bucket (released before moving to the next bucket)
# because each bucket has its own archive file. EXIT trap above releases on
# failure mid-loop.
mkdir -p "$ARCHIVE_DIR"
buckets="$(sort -u "$INDEX_FILE" | awk -F'\t' '{print $1}' | sort -u)"
while IFS= read -r bucket; do
  [ -n "$bucket" ] || continue
  ARCHIVE_LOCK="$PROJECT_ROOT/.redeye-archive-${bucket}.lock"
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

  archive_file="$ARCHIVE_DIR/${bucket}.md"
  if [ ! -f "$archive_file" ]; then
    cat > "$archive_file.tmp.$$" <<EOF
# Changelog archive — ${bucket}

Iteration entries from ${bucket}, moved here at MERGE time from
\`.redeye/changelog.md\`.

EOF
    mv "$archive_file.tmp.$$" "$archive_file"
  fi
  grep -F "${bucket}	" "$INDEX_FILE" | cut -f2 | while read -r block_file; do
    cat "$block_file" >> "$archive_file"
    printf '\n' >> "$archive_file"
  done

  # Release this bucket's lock before moving on to the next one.
  rmdir "$ARCHIVE_LOCK" 2>/dev/null || true
  _lock_held=false
  ARCHIVE_LOCK=""
done <<EOF
$buckets
EOF

mv "$KEEP_FILE" "$CHANGELOG_FILE.tmp.$$"
mv "$CHANGELOG_FILE.tmp.$$" "$CHANGELOG_FILE"

archived_count=$(wc -l < "$INDEX_FILE" | tr -d ' ')
echo "archived: $archived_count prior-month iterations → $ARCHIVE_DIR/"
