#!/usr/bin/env bash
set -euo pipefail

# archive-inbox.sh — Move incorporated Q-XXX entries from `.redeye/inbox.md`
# to `docs/inbox-archive/YYYY-MM.md` and remove them from inbox.md.
#
# Why: inbox.md grows unbounded as INCORPORATE marks each answered question
# with `**Incorporated:**`. TRIAGE and digest re-scan the whole file every
# iteration; the only entries those readers actually care about are open
# questions (under `## Questions (Open)`) and answered-but-not-yet-incorporated
# entries (Answer present, Incorporated absent). Once `**Incorporated:**` is
# set, the entry is dead weight in the active file.
#
# Usage:
#   archive-inbox.sh <project_root>
#
# Behavior:
#   - Sweeps every Q-XXX block in `## Answered / Provided` that has an
#     `**Incorporated:**` line.
#   - Buckets by the YYYY-MM extracted from the Incorporated value (falls
#     back to current UTC month if unparseable).
#   - Atomic: writes via tmp + mv for both inbox.md and archive files.
#   - Idempotent: re-runs after success are no-ops (no incorporated entries left).

usage() {
  echo "Usage: archive-inbox.sh <project_root>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
PROJECT_ROOT="$(cd "$1" && pwd)"

INBOX_FILE="$PROJECT_ROOT/.redeye/inbox.md"
[ -f "$INBOX_FILE" ] || { echo "skip: $INBOX_FILE not found" >&2; exit 0; }

ARCHIVE_DIR="$PROJECT_ROOT/docs/inbox-archive"

# Use awk to split inbox.md into:
#   - lines to keep (active)
#   - blocks to archive, grouped by YYYY-MM bucket
#
# A block is `### Q-...` (or `### CRED-...`) inside `## Answered / Provided`
# that contains a `**Incorporated:**` line. Open questions (under
# `## Questions (Open)`) and un-incorporated answered entries are kept.

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
INDEX_FILE="$WORK_DIR/index.txt"  # one line per archived block: <bucket>\t<block_file>

# Pre-create keep file so the final `mv` succeeds even if every block
# was archived (awk would otherwise never `>>` to keepfile).
: > "$KEEP_FILE"

awk -v workdir="$WORK_DIR" -v indexfile="$INDEX_FILE" -v keepfile="$KEEP_FILE" '
  function flush_block() {
    if (block == "") return
    if (in_answered && has_incorporated) {
      # Pick bucket: YYYY-MM from incorporated value
      bucket = ""
      n = split(incorporated_val, parts, /[^0-9-]/)
      for (i = 1; i <= n; i++) {
        if (parts[i] ~ /^[0-9]{4}-[0-9]{2}/) {
          bucket = substr(parts[i], 1, 7)
          break
        }
      }
      if (bucket == "") {
        "date -u +%Y-%m" | getline bucket
        close("date -u +%Y-%m")
      }
      file = workdir "/block-" (++blockcount) ".md"
      printf "%s", block > file
      close(file)
      print bucket "\t" file >> indexfile
    } else {
      printf "%s", block >> keepfile
    }
    block = ""
    has_incorporated = 0
    incorporated_val = ""
  }

  # Top-level section header: `## Foo` (not `### ...`)
  /^## [^#]/ {
    flush_block()
    print $0 >> keepfile
    if ($0 ~ /^##[[:space:]]+Answered/) {
      in_answered = 1
    } else {
      in_answered = 0
    }
    next
  }

  # Block-start: `### ...`
  /^### / {
    flush_block()
    block = $0 "\n"
    next
  }

  # Inside a block (or top-level prose between sections)
  {
    if (block != "") {
      block = block $0 "\n"
      if ($0 ~ /^- \*\*Incorporated:\*\*/) {
        has_incorporated = 1
        sub(/^- \*\*Incorporated:\*\*[[:space:]]*/, "", $0)
        incorporated_val = $0
      }
    } else {
      print $0 >> keepfile
    }
  }

  END {
    flush_block()
  }
' "$INBOX_FILE"

# If no entries were archived, exit early (idempotent no-op).
if [ ! -s "$INDEX_FILE" ]; then
  echo "skip: no incorporated entries to archive"
  exit 0
fi

# Group blocks by bucket and append to archive files. For each bucket,
# acquire a per-month mkdir lock around the archive create-or-append so two
# concurrent invocations writing into the same month don't both pass the
# `[ ! -f ]` check, race on tmp+mv, and clobber each other. mkdir is atomic
# on POSIX. Lock is per-bucket (released before moving to the next bucket)
# because each bucket has its own archive file. EXIT trap below releases on
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
# Inbox archive — ${bucket}

Incorporated CEO answers, moved here at MERGE time from \`.redeye/inbox.md\`.

EOF
    mv "$archive_file.tmp.$$" "$archive_file"
  fi
  # Append every block tagged with this bucket
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

# Replace inbox.md with the kept content (atomic).
mv "$KEEP_FILE" "$INBOX_FILE.tmp.$$"
mv "$INBOX_FILE.tmp.$$" "$INBOX_FILE"

archived_count=$(wc -l < "$INDEX_FILE" | tr -d ' ')
echo "archived: $archived_count incorporated inbox entries → $ARCHIVE_DIR/"
