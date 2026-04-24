---
description: "Start or resume the autonomous dev loop"
---

<!--
  This slash command is self-contained: do NOT change the body to a stub
  like "Invoke the redeye:start skill". Claude Code 2.1.122 has a resolver
  collision where `Skill({skill: "redeye:start"})` dispatches to *this slash
  command*, creating an infinite re-injection loop. Even after that upstream
  bug is fixed, the bridge pattern adds a turn per iteration with no benefit.
  Keep the steps inline.
-->

# Start RedEye

Validate the project is ready and start the Ralph Loop.

## Step 1: Validate Setup

Check that these files exist in the project root:
- `.redeye/config.md` — if missing, tell user to run `/redeye:init` first
- `.redeye/config.md` must contain a `## Vision` section with content (not just the placeholder). If missing or empty, tell user to add a vision.
- `.redeye/tasks.md` — if no items, tell user to add at least one item
- `.redeye/state.json` — if missing, tell user to run `/redeye:init`

If any validation fails, stop and guide the user.

## Step 2: Check Resume State

Read `.redeye/state.json`:
- If `iteration` > 0: this is a resume
  - Show: "Resuming from iteration {n} ({phase})"
  - Show last 3 entries from `iteration_log`
  - Show health/confidence
- If `iteration` = 0: this is a fresh start
  - Show: "Starting fresh"

## Step 3: Show Summary

Present to the user:
- **Vision:** first 100 chars of ## Vision section in .redeye/config.md
- **Tasks:** count of items (CEO Requests + Discovered + Triaged)
- **Health:** confidence level, env status
- **Next:** what the team will work on first (highest-priority planned item, or first CEO Request if nothing triaged)

## Step 4: Start Loop

**CRITICAL: You MUST run the start-loop.sh script. Do NOT skip this. It creates the .claude/ralph-loop.local.md file that enables autonomous looping. Without it, the session will stop after each response instead of continuing automatically.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" .
```

If `CLAUDE_PLUGIN_ROOT` is not set, find the plugin root by looking for `.claude-plugin/plugin.json` in parent directories or common plugin locations.

Verify the loop file was created:
```bash
test -f .claude/ralph-loop.local.md && echo "Loop file OK" || echo "FAILED: loop file not created"
```

## Step 5: Begin First Iteration

Run the digest script:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/digest.sh" .
```

Read `.redeye/digest.json`.

### Step 5a: Idle short-circuit — STOP without dispatching

**Before doing anything else**, evaluate the digest. If ALL of the following hold, your **only output for this turn** is the literal completion-promise tag — byte-for-byte, on its own line, with nothing else:

- `phase` == `"triage"` AND `phase_status` == `"complete"`
- `tasks_summary.ceo_pending` == 0
- `tasks_summary.triaged_planned` == 0
- `tasks_summary.discovered_pending` == 0
- `overdue_schedules` == 0
- `ceo_answers_pending` == 0
- `env_healthy` == true
- `stop_directive` == false AND `pause_directive` == false

When all these hold, the loop has nothing to do. **Output exactly:**

```
<promise>CEO DIRECTED STOP</promise>
```

Do NOT:
- Dispatch any phase agent (no Task call to triage / plan / build / etc.)
- Increment any counter
- Write `.redeye/status.md` or `iteration_log`
- Run any other Bash command
- Add prose like "All signals zero" or "Exiting cleanly" or "Stopping" — the literal promise tag is the ONLY acceptable output

This rule fires on **every** iteration that meets the idle conditions, not only the first. Re-emit the promise tag every time. ralph-loop's stop-hook matches this exact string and it is the only way to halt the loop. Anything else and you create an infinite re-injection loop that burns tokens forever — that is the bug from 2026-04-29 that you must NOT recreate.

### Step 5b: Otherwise — begin the CTO orchestration loop

If the idle conditions do NOT all hold (some actionable task, overdue schedule, pending CEO answer, or unhealthy env), defer to `agents/cto.md`. Follow its Step 0 → Step 5 logic to pick the next phase and dispatch the appropriate agent. The CTO reads the digest, decides, and dispatches.

Tell the user (only after dispatching, not on the STOP path):
- "RedEye is working. Check in anytime with /redeye:status."
- "To stop: /redeye:stop"
