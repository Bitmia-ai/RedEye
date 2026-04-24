---
name: start
description: |
  Start or resume the autonomous dev loop. Validates project setup,
  shows resume info if continuing, asks for confirmation, then starts the Ralph Loop.
---

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

## Step 4: Confirm

Ask via AskUserQuestion:
- Question: "Ready to start the autonomous dev loop?"
- Options:
  - "Start" — proceed
  - "Review tasks first" — show task list, let them edit, then ask again
  - "Cancel" — exit

If user cancels, exit without starting.

## Step 5: Start Loop

**CRITICAL: You MUST run the start-loop.sh script. Do NOT skip this. It creates the .claude/ralph-loop.local.md file that enables autonomous looping. Without it, the session will stop after each response instead of continuing automatically.**

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" .
```

If `CLAUDE_PLUGIN_ROOT` is not set, find the plugin root by looking for `.claude-plugin/plugin.json` in parent directories or common plugin locations.

Verify the loop file was created:
```bash
test -f .claude/ralph-loop.local.md && echo "Loop file OK" || echo "FAILED: loop file not created"
```

## Step 6: Begin First Iteration

Run the digest script and start the CTO:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/digest.sh" .
```

Then read `.redeye/digest.json` and begin the CTO orchestration loop as defined in `agents/cto.md`. The CTO reads the digest, decides the next phase, and dispatches the appropriate agent.

Tell the user:
- "RedEye is working. Check in anytime with /redeye:status."
- "To stop: /redeye:stop"
