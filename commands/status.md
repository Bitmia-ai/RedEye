---
description: "Check team status — what happened, what needs you, what's next"
---

You are presenting the CEO's status dashboard. Follow these steps:

## Step 1: Read State Files

Read these files from the project root:
1. `.redeye/state.json` — for health, confidence, iteration count, phase, blocked items
2. `.redeye/status.md` — for the full dashboard
3. `.redeye/inbox.md` — for pending questions and credential requests

## Step 2: Present Summary

Show the user a concise status summary in this order:

**Health at a glance:**
- Team confidence: {HIGH/MEDIUM/LOW} from state
- Dev environment: {healthy/unhealthy}
- Current iteration: {n}, phase: {phase}
- Iterations since last deploy: {n}

**What happened** (from .redeye/status.md "Just Completed" section):
- Recent completions from last 3 iterations

**What needs your attention** (from .redeye/inbox.md):
- Count of open questions and credential requests
- List the highest-priority items with their defaults

**What's coming next** (from .redeye/status.md "Up Next"):
- Current work in progress
- Next planned items

## Step 3: Interactive Follow-up

After presenting the summary, offer the user choices via AskUserQuestion:
- "Answer pending questions" — if there are open questions, walk through each using AskUserQuestion with the options from .redeye/inbox.md
- "Add a task" — ask for a title and description, append as CEO Request to .redeye/tasks.md
- "Steer the team" — ask for a directive, append timestamped to .redeye/steering.md
- "Done" — exit

If the user chooses to answer questions, walk through each open question in .redeye/inbox.md one at a time using AskUserQuestion, presenting the options listed in the question. Write the CEO's answers back to .redeye/inbox.md.

If there are pending credential requests, mention them and explain that the CEO should add secret values to `.env.test` manually.
