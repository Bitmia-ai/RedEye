#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Lock helper — delegate to scripts/lock.sh, the single owner of lock semantics.
_lock() {
  local lockdir="$1"; shift
  bash "$SCRIPT_DIR/lock.sh" "$lockdir" "$@"
}

usage() {
  echo "Usage: worktree.sh {create|teardown} <project_root> [task_id]" >&2
  exit 1
}

[ $# -ge 2 ] || usage
COMMAND="$1"
PROJECT_ROOT="$(cd "$2" && pwd)"
STATE_FILE="$PROJECT_ROOT/.redeye/state.json"

[ -f "$STATE_FILE" ] || { echo "ERROR: $STATE_FILE not found" >&2; exit 1; }

case "$COMMAND" in
  create)
    [ $# -ge 3 ] || { echo "ERROR: create requires task_id argument" >&2; exit 1; }
    T_ID="$3"

    if ! [[ "$T_ID" =~ ^[0-9]+$ ]]; then
      echo "ERROR: invalid task_id '$T_ID': must be numeric" >&2
      exit 1
    fi

    WORKTREE_DIR="$PROJECT_ROOT/.worktrees/T$T_ID"
    BRANCH="redeye/T$T_ID"

    cleanup_failed_create() {
      _lock "$PROJECT_ROOT/.redeye-git.lock" bash -c '
        git -C "$1" worktree remove --force -- "$2" 2>/dev/null || true
        git -C "$1" branch -D -- "$3" 2>/dev/null || true
      ' _ "$PROJECT_ROOT" "$WORKTREE_DIR" "$BRANCH"
    }

    if [ -d "$WORKTREE_DIR" ]; then
      echo "ERROR: worktree directory already exists: $WORKTREE_DIR" >&2
      exit 1
    fi

    mkdir -p "$PROJECT_ROOT/.worktrees"

    if ! grep -qF '.worktrees/' "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
      echo '.worktrees/' >> "$PROJECT_ROOT/.gitignore"
      echo "  Added .worktrees/ to .gitignore"
    fi

    _lock "$PROJECT_ROOT/.redeye-git.lock" bash -c '
      git -C "$1" branch -- "$2" 2>/dev/null || true
      git -C "$1" worktree add -- "$3" "$2"
    ' _ "$PROJECT_ROOT" "$BRANCH" "$WORKTREE_DIR"

    if [ ! -d "$WORKTREE_DIR" ] || [ ! -f "$WORKTREE_DIR/.git" ]; then
      echo "ERROR: worktree creation failed verification" >&2
      cleanup_failed_create
      exit 1
    fi

    jq --arg wp "$WORKTREE_DIR" --arg wb "$BRANCH" \
      '.worktree_path = $wp | .worktree_branch = $wb' \
      "$STATE_FILE" > "$STATE_FILE.tmp.$$" && mv "$STATE_FILE.tmp.$$" "$STATE_FILE" || {
      echo "ERROR: state.json update failed, cleaning up worktree" >&2
      cleanup_failed_create
      exit 1
    }

    echo "Created worktree at $WORKTREE_DIR on branch $BRANCH"
    ;;

  teardown)
    BRANCH=$(jq -r '.worktree_branch // empty' "$STATE_FILE")
    WORKTREE_DIR=$(jq -r '.worktree_path // empty' "$STATE_FILE")

    [ -n "$BRANCH" ] || [ -n "$WORKTREE_DIR" ] || { echo "No worktree to tear down"; exit 0; }

    if [ -n "$BRANCH" ] && [[ ! "$BRANCH" == redeye/T* ]]; then
      echo "ERROR: refusing to delete branch '$BRANCH' — expected redeye/T* prefix" >&2
      exit 1
    fi

    if [ -n "$WORKTREE_DIR" ] && [[ ! "$WORKTREE_DIR" == "$PROJECT_ROOT/.worktrees/"* ]]; then
      echo "ERROR: refusing to remove worktree '$WORKTREE_DIR' — outside .worktrees/" >&2
      exit 1
    fi

    _lock "$PROJECT_ROOT/.redeye-git.lock" git -C "$PROJECT_ROOT" worktree prune 2>/dev/null || true

    if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
      _lock "$PROJECT_ROOT/.redeye-git.lock" \
        git -C "$PROJECT_ROOT" worktree remove --force -- "$WORKTREE_DIR" 2>/dev/null || true
    fi

    if [ -n "$BRANCH" ]; then
      _lock "$PROJECT_ROOT/.redeye-git.lock" \
        git -C "$PROJECT_ROOT" branch -D -- "$BRANCH" 2>/dev/null || true
    fi

    jq '.worktree_path = null | .worktree_branch = null' \
      "$STATE_FILE" > "$STATE_FILE.tmp.$$" && mv "$STATE_FILE.tmp.$$" "$STATE_FILE"

    echo "Worktree torn down"
    ;;

  *)
    usage
    ;;
esac
