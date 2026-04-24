#!/usr/bin/env bash
set -euo pipefail

# digest.sh — Pre-compute a compact JSON summary of all redeye control files.
# Output: PROJECT_ROOT/.redeye/digest.json (written atomically).
#
# Failure policy:
#   Fatal (non-zero exit, prior digest.json preserved):
#     state.json missing/unparseable, or assembled JSON fails jq validation.
#   Warning (emitted in digest.validation_warnings[], digest still produced):
#     other control files missing/malformed. Warning codes are stable strings
#     (CTO may key off them): file.missing, file.parse_failed,
#     state.schema_missing_field, tasks.missing_status, tasks.malformed_id,
#     tasks.unknown_status, legacy.

PROJECT_ROOT="${1:-.}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found in PATH" >&2
  exit 1
fi

warn_entries=()

warn() {
  local entry
  entry="$(jq -nc --arg c "$1" --arg d "${2:-}" '{code: $c, detail: $d}')"
  warn_entries+=("$entry")
}

safe_jq_strict() {
  local file="$1"; shift
  jq "$@" "$file" 2>/dev/null || {
    echo "ERROR: failed to parse $file with jq (fatal; state.json must be valid JSON)" >&2
    exit 1
  }
}

STATE_FILE="$PROJECT_ROOT/.redeye/state.json"
STEERING_FILE="$PROJECT_ROOT/.redeye/steering.md"
TASKS_FILE="$PROJECT_ROOT/.redeye/tasks.md"
INBOX_FILE="$PROJECT_ROOT/.redeye/inbox.md"
SCHEDULES_FILE="$PROJECT_ROOT/.redeye/schedules.md"
TESTER_FILE="$PROJECT_ROOT/.redeye/tester-reports.md"
CONFIG_FILE="$PROJECT_ROOT/.redeye/config.md"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: $STATE_FILE not found" >&2
  exit 1
fi

if ! jq empty "$STATE_FILE" 2>/dev/null; then
  echo "ERROR: $STATE_FILE is not valid JSON (fatal)" >&2
  exit 1
fi

# state.json mtime → how long since the loop last advanced. The CTO uses this
# to detect a dead loop whose worktree should be abandoned rather than resumed.
# BSD stat (macOS) and GNU stat have different flags. Naive `||` chaining is
# unsafe: GNU stat's `-f` switches to filesystem-info mode and emits a
# multi-line `File: ...` block to stdout WITHOUT failing, which then gets
# parsed by bash arithmetic as a variable name and trips `set -u`. Try GNU
# first, BSD second, validate numeric, default 0.
state_mtime=0
if _mt=$(stat -c %Y "$STATE_FILE" 2>/dev/null) && [[ "$_mt" =~ ^[0-9]+$ ]]; then
  state_mtime=$_mt
elif _mt=$(stat -f %m "$STATE_FILE" 2>/dev/null) && [[ "$_mt" =~ ^[0-9]+$ ]]; then
  state_mtime=$_mt
fi
unset _mt
now_epoch=$(date +%s)
state_age_seconds=$((now_epoch - state_mtime))
if [[ $state_age_seconds -lt 0 ]]; then state_age_seconds=0; fi

for field in phase iteration; do
  if ! jq -e "has(\"$field\")" "$STATE_FILE" >/dev/null 2>&1; then
    warn "state.schema_missing_field" "$field"
  fi
done

phase="$(safe_jq_strict "$STATE_FILE" -r '.phase // "UNKNOWN"')"
phase_status="$(safe_jq_strict "$STATE_FILE" -r '.phase_status // "unknown"')"
iteration="$(safe_jq_strict "$STATE_FILE" '.iteration // 0')"
confidence="$(safe_jq_strict "$STATE_FILE" -r '.health.confidence // "UNKNOWN"')"
env_status="$(safe_jq_strict "$STATE_FILE" -r '.health.env_status // "unknown"')"
iterations_since_deploy="$(safe_jq_strict "$STATE_FILE" '.health.iterations_since_last_deploy // 0')"
review_cycles="$(safe_jq_strict "$STATE_FILE" '.review_cycles // 0')"
task_id="$(safe_jq_strict "$STATE_FILE" -r '.task_id // ""')"
task_title="$(safe_jq_strict "$STATE_FILE" -r '.task_title // ""')"
spec_file="$(safe_jq_strict "$STATE_FILE" -r '.spec_file // ""')"
worktree_path="$(safe_jq_strict "$STATE_FILE" -r '.worktree_path // ""')"
worktree_branch="$(safe_jq_strict "$STATE_FILE" -r '.worktree_branch // ""')"

[[ "$env_status" == "healthy" ]] && env_healthy="true" || env_healthy="false"

# --- steering.md ---

stop_directive="false"
pause_directive="false"
steering_directives="[]"

if [[ -f "$STEERING_FILE" ]]; then
  in_directives=0
  directives_lines=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+Directives ]]; then
      in_directives=1
      continue
    fi
    if [[ $in_directives -eq 1 && "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
      break
    fi
    if [[ $in_directives -eq 1 ]]; then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      if [[ -z "$trimmed" || "$trimmed" == _* ]]; then
        continue
      fi
      # Match case-insensitively to mirror stop-hook.sh (`grep -qiE '^\s*STOP\b'`).
      # Earlier version was case-sensitive — a `Stop` written via `/redeye:stop`
      # would deactivate the loop via stop-hook but leave `stop_directive=false`
      # in the digest, so the CTO would dispatch a phase against a "stopped"
      # session. Split-brain kill switch. Lowercase via `tr` rather than
      # bash's `shopt -s nocasematch` for portability across bash 3.2/4/5.
      trimmed_lc="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
      [[ "$trimmed_lc" =~ ^stop ]] && stop_directive="true"
      [[ "$trimmed_lc" =~ ^pause ]] && pause_directive="true"
      directives_lines+=("$trimmed")
    fi
  done < "$STEERING_FILE"
  if [[ ${#directives_lines[@]} -gt 0 ]]; then
    steering_directives="$(printf '%s\n' "${directives_lines[@]}" | jq -R . | jq -s .)"
  fi
else
  warn "file.missing" ".redeye/steering.md"
fi

worktree_enabled="true"
if [ -f "$CONFIG_FILE" ]; then
  wt_line=$(grep -A1 '## Worktree Isolation' "$CONFIG_FILE" 2>/dev/null | grep 'Enabled:' | head -1 || true)
  if [ -n "$wt_line" ]; then
    wt_val=$(echo "$wt_line" | sed 's/.*Enabled:[[:space:]]*//' | tr '[:upper:]' '[:lower:]')
    [[ "$wt_val" == "false" ]] && worktree_enabled="false"
  fi
fi

# --- tasks.md ---
#
# Count `### T` headings per section. Status lines reclassify items
# (blocked, done, wont-do). Terminal items (done, wont-do) are excluded
# from active counts. Items inside fenced code blocks are ignored.

ceo_pending=0
triaged_planned=0
discovered_pending=0
blocked=0

if [[ -f "$TASKS_FILE" ]]; then
  current_section=""
  in_fence=0
  current_item_section=""
  current_item_id=""
  current_item_has_status=0
  current_item_terminal=0
  current_item_blocked=0

  flush_item() {
    if [[ -z "$current_item_section" ]]; then
      return
    fi
    if [[ $current_item_terminal -eq 1 ]]; then
      return
    fi
    if [[ $current_item_blocked -eq 1 ]]; then
      blocked=$((blocked + 1))
      return
    fi
    if [[ $current_item_has_status -eq 0 && -n "$current_item_id" ]]; then
      warn "tasks.missing_status" "$current_item_id"
    fi
    case "$current_item_section" in
      ceo)        ceo_pending=$((ceo_pending + 1)) ;;
      discovered) discovered_pending=$((discovered_pending + 1)) ;;
      triaged)    triaged_planned=$((triaged_planned + 1)) ;;
    esac
  }

  while IFS= read -r line; do
    if [[ "$line" =~ ^\`\`\` ]]; then
      in_fence=$((1 - in_fence))
      continue
    fi
    if [[ $in_fence -eq 1 ]]; then
      continue
    fi

    if [[ "$line" =~ ^##[[:space:]]+CEO[[:space:]]+Requests ]]; then
      flush_item; current_item_section=""; current_section="ceo"; continue
    elif [[ "$line" =~ ^##[[:space:]]+Discovered ]]; then
      flush_item; current_item_section=""; current_section="discovered"; continue
    elif [[ "$line" =~ ^##[[:space:]]+Triaged ]]; then
      flush_item; current_item_section=""; current_section="triaged"; continue
    elif [[ "$line" =~ ^##[[:space:]]+"Won't Do" ]] || [[ "$line" =~ ^##[[:space:]]+Won\'t[[:space:]]+Do ]]; then
      flush_item; current_item_section=""; current_section="wontdo"; continue
    elif [[ "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
      flush_item; current_item_section=""; current_section="other"; continue
    fi

    if [[ "$line" =~ ^###[[:space:]]+T([A-Za-z0-9_-]+) ]]; then
      flush_item
      local_id="${BASH_REMATCH[1]}"
      current_item_section="$current_section"
      current_item_id="T$local_id"
      current_item_has_status=0
      current_item_terminal=0
      current_item_blocked=0
      if ! [[ "$local_id" =~ ^[0-9]+$ ]]; then
        warn "tasks.malformed_id" "T$local_id"
      fi
      if [[ "$current_section" == "wontdo" ]]; then
        current_item_terminal=1
      fi
      continue
    fi

    # Match `**Status:**` only at line start (optionally after list marker) to
    # avoid matching inline prose like Rationale quoting the status keyword.
    if [[ -n "$current_item_section" && "$line" =~ ^[[:space:]]*[-*]?[[:space:]]*\*\*Status:\*\*[[:space:]]*(.*) ]]; then
      raw_status="${BASH_REMATCH[1]}"
      status_word="$(printf '%s' "$raw_status" | awk '{print tolower($1)}')"
      current_item_has_status=1
      case "$status_word" in
        done|wont-do|wontdo) current_item_terminal=1 ;;
        blocked) current_item_blocked=1 ;;
        pending|pending-triage|planned|in-progress|"") ;;
        *) warn "tasks.unknown_status" "$current_item_id=$status_word" ;;
      esac
    fi
  done < "$TASKS_FILE"
  flush_item
else
  warn "file.missing" ".redeye/tasks.md"
fi

# --- inbox.md ---

ceo_answers_pending=0

if [[ -f "$INBOX_FILE" ]]; then
  in_answered=0
  has_answer=0
  has_incorporated=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+Answered ]]; then
      in_answered=1
      continue
    fi
    if [[ $in_answered -eq 1 && "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
      if [[ $has_answer -eq 1 && $has_incorporated -eq 0 ]]; then
        ceo_answers_pending=$((ceo_answers_pending + 1))
      fi
      in_answered=0; has_answer=0; has_incorporated=0
      continue
    fi
    if [[ $in_answered -eq 1 ]]; then
      if [[ "$line" =~ ^###[[:space:]] ]]; then
        if [[ $has_answer -eq 1 && $has_incorporated -eq 0 ]]; then
          ceo_answers_pending=$((ceo_answers_pending + 1))
        fi
        has_answer=0; has_incorporated=0
      fi
      [[ "$line" =~ \*\*Answer:\*\* ]] && has_answer=1
      [[ "$line" =~ \*\*Incorporated:\*\* ]] && has_incorporated=1
    fi
  done < "$INBOX_FILE"
  if [[ $in_answered -eq 1 && $has_answer -eq 1 && $has_incorporated -eq 0 ]]; then
    ceo_answers_pending=$((ceo_answers_pending + 1))
  fi

  open_questions=0
  in_open=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+Questions[[:space:]]*\(Open\) ]]; then
      in_open=1
      continue
    fi
    if [[ $in_open -eq 1 && "$line" =~ ^##[[:space:]] && ! "$line" =~ ^### ]]; then
      break
    fi
    if [[ $in_open -eq 1 && "$line" =~ ^###[[:space:]] ]]; then
      open_questions=$((open_questions + 1))
    fi
  done < "$INBOX_FILE"
  ceo_answers_pending=$((ceo_answers_pending + open_questions))
else
  warn "file.missing" ".redeye/inbox.md"
fi

# --- schedules.md (optional) ---
#
# A schedule is overdue if it has never run, OR if the time since its last
# run exceeds its frequency. Earlier code only handled the never-run case,
# so once a schedule fired once it could never re-fire.

# Convert "every N (hour|day|week|month)s?" into seconds. Returns 0 on parse
# failure (treats as "never overdue" rather than "always overdue"). Caps N at
# 10000 to avoid 64-bit signed overflow on `n * 31536000` (a hostile or
# typo'd `every 9999999999 years` would wrap negative and fire every iteration).
_freq_to_seconds() {
  local freq="$1"
  local n unit
  if [[ "$freq" =~ every[[:space:]]+([0-9]+)[[:space:]]+([a-zA-Z]+) ]]; then
    n="${BASH_REMATCH[1]}"
    [[ "$n" -gt 10000 ]] && n=10000
    # macOS ships bash 3.2, which doesn't support ${var,,}. Use tr for portability.
    unit="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    case "$unit" in
      second|seconds) echo "$n" ;;
      minute|minutes) echo $((n * 60)) ;;
      hour|hours)     echo $((n * 3600)) ;;
      day|days)       echo $((n * 86400)) ;;
      week|weeks)     echo $((n * 604800)) ;;
      month|months)   echo $((n * 2592000)) ;;  # 30-day approximation
      year|years)     echo $((n * 31536000)) ;;
      *)              echo 0 ;;
    esac
  else
    echo 0
  fi
}

# Trim leading + trailing whitespace from a string. Used on schedule
# Last-run timestamps so a trailing space (common when humans hand-edit
# schedules.md) doesn't make `_iso_to_epoch` fail and silently disable the
# overdue check.
_trim() {
  local s="$1"
  # leading
  s="${s#"${s%%[![:space:]]*}"}"
  # trailing
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Convert an ISO-8601 timestamp into epoch seconds. macOS BSD `date` and
# GNU `date` parse `-d`/`-j` differently. Try GNU first, BSD second,
# validate numeric to avoid one platform's stdout being parsed as the other's
# (same hazard as the stat block above).
_iso_to_epoch() {
  local iso="$1" epoch
  if epoch=$(date -d "$iso" +%s 2>/dev/null) && [[ "$epoch" =~ ^[0-9]+$ ]]; then
    echo "$epoch"
    return
  fi
  if epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) && [[ "$epoch" =~ ^[0-9]+$ ]]; then
    echo "$epoch"
    return
  fi
  echo 0
}

overdue_schedules=0

if [[ -f "$SCHEDULES_FILE" ]]; then
  in_sched=0
  sched_freq=""
  sched_last_run=""
  flush_schedule() {
    [[ $in_sched -eq 1 ]] || return 0
    if [[ -z "$sched_last_run" ]] || [[ "$sched_last_run" =~ ^[Nn]ever$ ]]; then
      overdue_schedules=$((overdue_schedules + 1))
      return 0
    fi
    local interval
    interval=$(_freq_to_seconds "$sched_freq")
    [[ "$interval" -gt 0 ]] || return 0
    local last_epoch
    last_epoch=$(_iso_to_epoch "$sched_last_run")
    [[ "$last_epoch" -gt 0 ]] || return 0
    if (( now_epoch - last_epoch >= interval )); then
      overdue_schedules=$((overdue_schedules + 1))
    fi
  }
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+SCHED- ]]; then
      flush_schedule
      in_sched=1; sched_freq=""; sched_last_run=""
      continue
    fi
    if [[ $in_sched -eq 1 && "$line" =~ \*\*Frequency:\*\*[[:space:]]*(.*) ]]; then
      sched_freq="$(_trim "${BASH_REMATCH[1]}")"
    fi
    if [[ $in_sched -eq 1 && "$line" =~ \*\*Last[[:space:]]+run:\*\*[[:space:]]*(.*) ]]; then
      sched_last_run="$(_trim "${BASH_REMATCH[1]}")"
    fi
  done < "$SCHEDULES_FILE"
  flush_schedule
fi

# --- tester-reports.md (optional) ---

tester_reports_new=0
if [[ -f "$TESTER_FILE" ]]; then
  tester_reports_new="$(grep -c '^### BUG-[0-9]' "$TESTER_FILE" 2>/dev/null)" || true
fi

# --- Crash recovery ---

crash_recovery="null"
if [[ "$phase_status" == "in-progress" ]]; then
  recent_commits="$(cd "$PROJECT_ROOT" && git log --oneline -3 2>/dev/null | jq -R . | jq -s .)" || recent_commits="[]"
  crash_recovery="$(jq -n --arg p "$phase" --argjson rc "$recent_commits" \
    '{phase: $p, recent_commits: $rc}')"
fi

# --- Degenerate-loop detector ---
#
# If the last 3 assistant turns in session-cto.jsonl have identical text and
# zero tool_use blocks between them, the model is wedged. Real symptoms we've
# seen:
#   • Slash-command → skill bridge regression (model prints `Invoke the
#     redeye:start skill` every turn but never calls the Skill tool).
#   • Idle without `<promise>` emission (model writes "All signals zero.
#     Exiting cleanly." every turn but ralph-loop's regex doesn't match).
# In both cases the loop burns tokens forever. Surfacing this as a
# validation_warnings entry makes the dashboard show a red flag and gives
# the CTO a deterministic signal to break out (e.g. force-emit STOP promise
# or hard-stop the session).

CTO_JSONL="$PROJECT_ROOT/.redeye/session-cto.jsonl"
if [[ -f "$CTO_JSONL" ]] && command -v jq >/dev/null 2>&1; then
  # Read the last 200 KB only — full file scan would dominate digest cost.
  # jq:
  #   - filter to assistant messages
  #   - tag each with whether it has any tool_use block
  #   - extract concatenated text content (so multi-text-block turns dedup correctly)
  #   - take the last 3, compare
  loop_repeats=$(
    tail -c 200000 "$CTO_JSONL" 2>/dev/null \
      | jq -rcs '
          [
            .[]
            | select(type == "object")
            | select(.type == "assistant")
            | select(.message.content)
            | {
                has_tool: (any(.message.content[]; .type == "tool_use")),
                text: ( [ .message.content[] | select(.type == "text") | .text ] | join("") )
              }
            | select(.has_tool == false)
            | select((.text | length) > 0)
          ]
          | (if length < 3 then 0
             else .[length-3:length]
                  | (if (.[0].text == .[1].text and .[1].text == .[2].text) then 1 else 0 end)
             end)
        ' 2>/dev/null
  )
  if [[ "$loop_repeats" == "1" ]]; then
    # Don't put the repeated text itself in the warning — it can be hundreds
    # of bytes and bloat the digest. The dashboard / a tail of the jsonl
    # surfaces the actual content.
    warn "loop.degenerate" "last 3 assistant turns identical with no tool calls — model is wedged"
  fi
fi

# --- Legacy free-text warnings (CTO prompts key off these strings) ---

if [[ "$phase" == "REVIEW" && "$review_cycles" -eq 0 ]]; then
  warn "legacy" "REVIEW phase entered with review_cycles=0"
fi
if [[ "$iterations_since_deploy" -gt 10 ]]; then
  warn "legacy" "iterations_since_last_deploy is $iterations_since_deploy (>10)"
fi

if [[ ${#warn_entries[@]} -eq 0 ]]; then
  validation_warnings="[]"
else
  validation_warnings="$(printf '%s\n' "${warn_entries[@]}" | jq -s .)"
fi

current_task="null"
if [[ -n "$task_id" ]]; then
  current_task="$(jq -n \
    --arg id "$task_id" \
    --arg title "$task_title" \
    --arg spec "$spec_file" \
    --argjson rc "$review_cycles" \
    '{id: $id, title: $title, spec_file: $spec, review_cycles: $rc}')"
fi

OUTPUT_FILE="$PROJECT_ROOT/.redeye/digest.json"
TMP_FILE="$OUTPUT_FILE.tmp"

jq -n \
  --arg phase "$phase" \
  --arg phase_status "$phase_status" \
  --argjson iteration "$iteration" \
  --argjson stop_directive "$stop_directive" \
  --argjson pause_directive "$pause_directive" \
  --argjson steering_directives "$steering_directives" \
  --argjson env_healthy "$env_healthy" \
  --arg confidence "$confidence" \
  --argjson ceo_pending "$ceo_pending" \
  --argjson triaged_planned "$triaged_planned" \
  --argjson discovered_pending "$discovered_pending" \
  --argjson blocked "$blocked" \
  --argjson overdue_schedules "$overdue_schedules" \
  --argjson ceo_answers_pending "$ceo_answers_pending" \
  --argjson tester_reports_new "$tester_reports_new" \
  --argjson current_task "$current_task" \
  --argjson iterations_since_last_deploy "$iterations_since_deploy" \
  --argjson crash_recovery "$crash_recovery" \
  --argjson validation_warnings "$validation_warnings" \
  --argjson state_age_seconds "$state_age_seconds" \
  --arg worktree_path "$worktree_path" \
  --arg worktree_branch "$worktree_branch" \
  --argjson worktree_enabled "$worktree_enabled" \
  '{
    phase: $phase,
    phase_status: $phase_status,
    iteration: $iteration,
    stop_directive: $stop_directive,
    pause_directive: $pause_directive,
    steering_directives: $steering_directives,
    env_healthy: $env_healthy,
    confidence: $confidence,
    tasks_summary: {
      ceo_pending: $ceo_pending,
      triaged_planned: $triaged_planned,
      discovered_pending: $discovered_pending,
      blocked: $blocked
    },
    overdue_schedules: $overdue_schedules,
    ceo_answers_pending: $ceo_answers_pending,
    tester_reports_new: $tester_reports_new,
    current_task: $current_task,
    iterations_since_last_deploy: $iterations_since_last_deploy,
    state_age_seconds: $state_age_seconds,
    crash_recovery: $crash_recovery,
    validation_warnings: $validation_warnings,
    worktree_path: (if $worktree_path == "" then null else $worktree_path end),
    worktree_branch: (if $worktree_branch == "" then null else $worktree_branch end),
    worktree_enabled: $worktree_enabled
  }' > "$TMP_FILE"

if ! jq empty "$TMP_FILE" 2>/dev/null; then
  echo "ERROR: assembled digest failed jq empty validation; prior digest preserved" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

mv "$TMP_FILE" "$OUTPUT_FILE"

echo "Digest written to $OUTPUT_FILE"
