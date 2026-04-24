---
description: "Initialize RedEye in current project"
argument-hint: "[--full]"
---

<!--
  This slash command is self-contained: do NOT change the body to a stub
  like "Invoke the redeye:init skill". Claude Code 2.1.122 has a resolver
  collision where `Skill({skill: "redeye:init"})` dispatches to *this slash
  command*, creating an infinite re-injection loop. Even after that upstream
  bug is fixed, the bridge pattern adds a turn per iteration with no benefit.
  Keep the steps inline.
-->

# Initialize RedEye

Set up the autonomous dev team framework in this project.

## Pre-flight Check

Before anything else, check if `.redeye/state.json` exists in the current directory:
- If it exists: tell the user "This project is already initialized with RedEye. Use `/redeye:start` to resume, or run `/redeye:init --force` to reinitialize (this will overwrite all control files and reset state)." Then STOP — do not proceed.
- If `--force` is passed alongside an existing project: warn the user that all control files will be overwritten and state will be reset. Ask for confirmation via AskUserQuestion before proceeding.

## Detect Mode

Check if arguments include `--full`:
- If `--full`: run Full Setup (all steps below)
- Otherwise: run Quick Start (steps 1-5 only)

## Quick Start (~2 minutes)

### Step 1: Project Name
Ask via AskUserQuestion:
- Question: "What's the project name?"
- Default: basename of the current working directory

### Step 2: Product Vision
Ask via AskUserQuestion:
- Question: "Describe your product vision in one sentence"
- This becomes the ## Vision section in .redeye/config.md

### Step 3: First Task
Ask via AskUserQuestion:
- Question: "What should we build first?"
- This becomes the first CEO Request in .redeye/tasks.md (T001)

### Step 4: Deploy Command
Ask via AskUserQuestion:
- Question: "What's your deploy command?"
- Options: common patterns like `./scripts/deploy.sh deploy`, `npm run deploy`, `git push heroku main`, custom
- Default: "echo 'No deploy command configured'"

### Step 5: Scaffold

**CRITICAL: You MUST run the init-project.sh script. Do NOT create control files manually. The script creates state.json, sets up gitignore entries, installs the pre-commit hook, and makes the initial commit. Without it, /redeye:start will not work.**

**Pass the answers via `--answers-file`, never inline-interpolate them into bash.** A CEO answer can contain quotes, backticks, `$`, or newlines; constructing a bash command line that embeds raw answer text invites quoting bugs and command injection. The `--answers-file` flag lets you put all four answers in one JSON file (using the Write tool, which takes raw bytes), then call the script with a fixed argv where the only variable byte is the file path itself.

1. Use the Write tool to create `/tmp/redeye-init-answers.json` with this exact shape:
   ```json
   {
     "project_name":   "<answer 1 verbatim>",
     "vision_text":    "<answer 2 verbatim>",
     "first_task":     "<answer 3 verbatim>",
     "deploy_command": "<answer 4 verbatim>"
   }
   ```
   The Write tool takes raw bytes — no quoting tricks, no escape rules to follow. Multi-line answers, embedded quotes, `$`, backticks all work as-is.

2. Run the script:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh" \
     --answers-file /tmp/redeye-init-answers.json .
   ```
   The script reads the JSON via `jq`, deletes the file when done, and proceeds with scaffolding. If the JSON is malformed, `jq empty` fails cleanly and the script aborts before scaffolding anything.

If `CLAUDE_PLUGIN_ROOT` is not set, find the plugin root by looking for `.claude-plugin/plugin.json` in parent directories or common plugin locations.

After the script completes, verify `.redeye/state.json` exists:
```bash
test -f .redeye/state.json && echo "OK" || echo "FAILED: state.json not created"
```

Tell the user:
- "Project initialized. Run /redeye:start to begin."

## Full Setup (--full, ~15 minutes)

All Quick Start steps PLUS:

### Step 6: Brainstorm Vision
Invoke `superpowers:brainstorming` to help the CEO articulate their product vision in more detail. Write the result to the ## Vision section in .redeye/config.md.

### Step 7: Additional Tasks
Ask: "What else should we build? (You can add more later with /redeye:tasks)"
Add each item as a CEO Request in .redeye/tasks.md with incrementing T{id}.

### Step 8: User Tester Personas
Ask: "Describe 1-3 target user personas for testing. For each, tell me: who they are, their job, why they use this product, and their tech comfort level."
Write personas to the `### User Tester Personas` section of .redeye/config.md.

### Step 9: Model Configuration
Show default model assignments (from Roles table in .redeye/config.md).
Ask: "Want to customize any model assignments? (opus is smarter but slower/costlier, sonnet is fast and capable)"
If yes: update the Roles table in .redeye/config.md.

### Step 10: Command Configuration
Ask for: verify command, test command, E2E test command, app URL.
Update .redeye/config.md config section.

### Step 11: Wiki Sync
Ask: "Enable Notion wiki sync?"
If yes: ask for Notion page ID, update .redeye/config.md wiki config.

### Step 12: Final Commit
Commit any changes from full setup:
```bash
git add .redeye/config.md .redeye/tasks.md .redeye/state.json
git commit -m "redeye: full setup complete"
```

Tell the user: "Full setup complete. Run /redeye:start to begin."
