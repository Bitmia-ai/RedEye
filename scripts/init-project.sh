#!/usr/bin/env bash
set -euo pipefail

# init-project.sh — Initialize a project with redeye control files.
#
# Usage:
#   ./init-project.sh [PROJECT_ROOT]
#   ./init-project.sh --force [PROJECT_ROOT]
#   ./init-project.sh --answers-file /path/to/answers.json [PROJECT_ROOT]
#
# Placeholder defaults can be overridden via environment variables (see the
# `: "${VAR:=default}"` block below) or by passing `--answers-file` (the
# preferred path; the init skill writes a JSON file the LLM populates with
# the four CEO answers, keeping user-controlled bytes off argv).

FORCE=false
ANSWERS_FILE=""
PROJECT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=true ;;
    --answers-file)
      # JSON file written by /redeye:init's skill containing CEO answers.
      # Reading from a file (instead of interpolating raw answers into the
      # bash command line) keeps user-controlled bytes off argv — the only
      # variable bytes in the invocation are the script and the file path.
      [ $# -gt 1 ] || { echo "ERROR: --answers-file requires a path" >&2; exit 1; }
      shift; ANSWERS_FILE="$1" ;;
    *) PROJECT_ROOT="$1" ;;
  esac
  shift
done

# Pull answers from the JSON file (if provided) before the env-var defaults
# below so file values win, env vars are a fallback, and `:` defaults are
# the final fallback.
if [ -n "$ANSWERS_FILE" ]; then
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: --answers-file requires jq" >&2; exit 1;
  }
  # Defend against symlink-based arbitrary-unlink: a hostile prompt that
  # induced the agent to call this script with --answers-file pointing at
  # ~/.ssh/known_hosts (via a symlink) would, after the read, hit our
  # `rm -f` and remove the target. Require a regular non-symlink file.
  if [ -L "$ANSWERS_FILE" ] || [ ! -f "$ANSWERS_FILE" ]; then
    echo "ERROR: --answers-file must be a regular file (not a symlink): $ANSWERS_FILE" >&2
    exit 1
  fi
  jq empty "$ANSWERS_FILE" >/dev/null 2>&1 || {
    echo "ERROR: $ANSWERS_FILE is not valid JSON" >&2; exit 1;
  }
  for key in project_name vision_text first_task deploy_command; do
    val="$(jq -r --arg k "$key" '.[$k] // empty' "$ANSWERS_FILE")"
    [ -z "$val" ] && continue
    case "$key" in
      project_name)   PROJECT_NAME="$val" ;;
      vision_text)    VISION_TEXT="$val" ;;
      first_task)     FIRST_TASK="$val" ;;
      deploy_command) DEPLOY_COMMAND="$val" ;;
    esac
  done
  rm -f "$ANSWERS_FILE"  # one-shot — don't leave answers on disk
fi

# Escape special chars for sed replacement strings.
# We also collapse newlines/CRs to spaces so a multi-line CEO answer can't
# break out of the substitution and inject forged STOP / fake-task entries
# into steering.md / tasks.md.
_sed_escape() {
  printf '%s' "$1" | tr '\n\r' '  ' | sed 's/[&/|\\]/\\&/g'
}
PROJECT_ROOT="${PROJECT_ROOT:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

: "${PROJECT_NAME:=$(basename "$PROJECT_ROOT")}"
: "${REPO_PATH:=$PROJECT_ROOT}"
: "${STARTED_AT:=$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
: "${DEPLOY_COMMAND:=echo 'No deploy command configured'}"
: "${VERIFY_COMMAND:=echo 'No verify command configured'}"
: "${TEST_COMMAND:=echo 'No test command configured'}"
: "${E2E_COMMAND:=echo 'No e2e command configured'}"
: "${APP_URL:=http://localhost:3000}"
: "${WIKI_ENABLED:=false}"
: "${WIKI_PAGE_ID:=}"
: "${USER_TESTER_PERSONAS:=_(No personas configured. Run /redeye:init --full to set up.)_}"
: "${MAX_REVIEW_CYCLES:=3}"
: "${MAX_ITERATIONS:=100}"
: "${NEXT_TASK_ID:=2}"
: "${FIRST_TASK:=First feature}"
: "${VISION_TEXT:=_(No vision set. Edit this file or run /redeye:init --full.)_}"

if [ "$FORCE" = false ] && [ -f "$PROJECT_ROOT/.redeye/state.json" ]; then
  echo "ERROR: This project is already initialized (found .redeye/state.json)."
  echo "  Pass --force to overwrite, or remove the existing control files first."
  exit 1
fi

echo "Initializing redeye in: $PROJECT_ROOT"
echo "  Project name: $PROJECT_NAME"

mkdir -p "$PROJECT_ROOT/.redeye"

# Template-based initialization: *.tmpl → .redeye/* with placeholder substitution.
for tmpl in "$PLUGIN_ROOT/templates/"*.tmpl; do
  [ -f "$tmpl" ] || continue
  filename=".redeye/$(basename "$tmpl" .tmpl)"
  sed -e "s|{{PROJECT_NAME}}|$(_sed_escape "$PROJECT_NAME")|g" \
      -e "s|{{REPO_PATH}}|$(_sed_escape "$REPO_PATH")|g" \
      -e "s|{{STARTED_AT}}|$(_sed_escape "$STARTED_AT")|g" \
      -e "s|{{DEPLOY_COMMAND}}|$(_sed_escape "$DEPLOY_COMMAND")|g" \
      -e "s|{{VERIFY_COMMAND}}|$(_sed_escape "$VERIFY_COMMAND")|g" \
      -e "s|{{TEST_COMMAND}}|$(_sed_escape "$TEST_COMMAND")|g" \
      -e "s|{{E2E_COMMAND}}|$(_sed_escape "$E2E_COMMAND")|g" \
      -e "s|{{APP_URL}}|$(_sed_escape "$APP_URL")|g" \
      -e "s|{{WIKI_ENABLED}}|$(_sed_escape "$WIKI_ENABLED")|g" \
      -e "s|{{WIKI_PAGE_ID}}|$(_sed_escape "$WIKI_PAGE_ID")|g" \
      -e "s|{{USER_TESTER_PERSONAS}}|$(_sed_escape "$USER_TESTER_PERSONAS")|g" \
      -e "s|{{MAX_REVIEW_CYCLES}}|$(_sed_escape "$MAX_REVIEW_CYCLES")|g" \
      -e "s|{{MAX_ITERATIONS}}|$(_sed_escape "$MAX_ITERATIONS")|g" \
      -e "s|{{NEXT_TASK_ID}}|$(_sed_escape "$NEXT_TASK_ID")|g" \
      -e "s|{{FIRST_TASK}}|$(_sed_escape "$FIRST_TASK")|g" \
      -e "s|{{VISION_TEXT}}|$(_sed_escape "$VISION_TEXT")|g" \
      "$tmpl" > "$PROJECT_ROOT/$filename"
  echo "  Created: $filename"
done

# Copy any non-.tmpl template files as-is.
for file in "$PLUGIN_ROOT/templates/"*; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in
    *.tmpl|.gitkeep) continue ;;
  esac
  cp "$file" "$PROJECT_ROOT/.redeye/$(basename "$file")"
  echo "  Copied: .redeye/$(basename "$file")"
done

mkdir -p \
  "$PROJECT_ROOT/docs/briefs" \
  "$PROJECT_ROOT/docs/specs" \
  "$PROJECT_ROOT/docs/decisions" \
  "$PROJECT_ROOT/docs/tasks-archive" \
  "$PROJECT_ROOT/docs/specs-archive"
echo "  Created: docs/{briefs,specs,decisions,tasks-archive,specs-archive}"

# .redeye/state.json is tracked in git (source of truth for worktree model).
for entry in '.env.test' '.redeye/digest.json' '.redeye/gate-*'; do
  if ! grep -qF "$entry" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    echo "$entry" >> "$PROJECT_ROOT/.gitignore"
    echo "  Added $entry to .gitignore"
  fi
done

# Install pre-commit hook. Refuse to overwrite a non-RedEye user hook
# (Husky / lefthook / lint-staged / custom). In a worktree (.git is a file)
# hooks are shared with main, so skip installation there.
if [ -d "$PROJECT_ROOT/.git" ]; then
  hook_path="$PROJECT_ROOT/.git/hooks/pre-commit"
  mkdir -p "$PROJECT_ROOT/.git/hooks"
  if [ -e "$hook_path" ] && ! grep -q "redeye/secret-scan" "$hook_path" 2>/dev/null; then
    # Existing hook does not look like ours (we tag our installs with a
    # comment header — see secret-scan.sh's marker line). Refuse to clobber.
    echo "  Skipped pre-commit hook: $hook_path already exists (chain manually or remove first)"
  else
    {
      echo "#!/usr/bin/env bash"
      echo "# redeye/secret-scan installed by /redeye:init"
      echo "exec \"$PLUGIN_ROOT/scripts/secret-scan.sh\" \"\$@\""
    } > "$hook_path"
    chmod +x "$hook_path"
    echo "  Installed pre-commit hook (redeye/secret-scan)"
  fi
elif [ -f "$PROJECT_ROOT/.git" ]; then
  echo "  Worktree detected — skipping hook installation (hooks inherited from main)"
else
  echo "  Warning: No .git found; skipping pre-commit hook installation"
fi

cd "$PROJECT_ROOT"
git add \
  .redeye/config.md \
  .redeye/reference.md \
  .redeye/state.json \
  .redeye/steering.md \
  .redeye/inbox.md \
  .redeye/tasks.md \
  .redeye/status.md \
  .redeye/changelog.md \
  .redeye/feedback.md \
  .redeye/schedules.md \
  .redeye/tester-reports.md \
  .gitignore

for dir in docs/briefs docs/specs docs/decisions docs/tasks-archive docs/specs-archive; do
  [ -f "$PROJECT_ROOT/$dir/.gitkeep" ] || touch "$PROJECT_ROOT/$dir/.gitkeep"
  git add "$dir/.gitkeep"
done

git commit -m "redeye: initialize project framework"
echo ""
echo "Done! Project initialized with redeye framework."
