# RedEye

A Claude Code plugin that continues your development work overnight. Leave a task list, walk away, come back to shipped features.

## Commands

| Command | Description |
|---------|-------------|
| `/redeye:init` | Scaffold `.redeye/` control files in your project |
| `/redeye:start` | Start (or resume) the autonomous dev loop |
| `/redeye:stop` | Gracefully stop after the current phase |
| `/redeye:status` | What's done, what's next, open questions |
| `/redeye:tasks` | View or add tasks |
| `/redeye:steer` | Add a directive ("focus on tests", "skip mobile") |
| `/redeye:brainstorm` | Think through an idea, turn it into a task |
| `/redeye:log` | Recent iteration history |
| `/redeye:schedules` | Manage recurring tasks |
| `/redeye:pause` | Pause after the current task cycle |

## How It Works

RedEye pre-computes a `.redeye/digest.json` from all control files (zero LLM tokens — pure bash+jq). The CTO agent reads this digest each iteration, decides which phase to run, and dispatches an isolated sub-agent. One phase per iteration, sequentially.

**Main cycle:** TRIAGE → PLAN → BUILD → REVIEW → DEPLOY → VERIFY → MERGE → next item

**Side phases** (triggered by conditions in the digest):
- STABILIZE — environment broken, focuses on restoring health (max 3 attempts)
- INCORPORATE — user answered questions in `.redeye/inbox.md`, adjusts existing work
- SCHEDULES — recurring tasks overdue

**On empty task list:** RedEye stops and waits for new tasks.

**On review failure:** Routes back to BUILD. After 3 failed cycles, parks the task and moves on.

**On needing user input:** Writes question to `.redeye/inbox.md` with a sensible default. Either proceeds with the default or blocks the task and picks up the next one. Never hallucinates an answer.

## Control Files

All live in `.redeye/` in the user's project. `/redeye:init` adds every entry below to the project's `.gitignore` — the control files are runtime state and are never committed.

| File | Purpose |
|------|---------|
| `config.md` | Project config — name, stack, deploy commands, vision |
| `tasks.md` | Task list, worked top-down |
| `steering.md` | Tactical directives |
| `inbox.md` | Questions from RedEye, answers from the user |
| `status.md` | Current progress |
| `changelog.md` | What shipped |
| `feedback.md` | RedEye's retros on its own work |
| `schedules.md` | Recurring tasks |
| `state.json` | Runtime state |
| `digest.json` | Pre-computed digest (regenerated each iteration) |

Edit control files directly. The digest is regenerated before each phase.

Completed content is swept out of the active control files at each MERGE into `docs/tasks-archive/`, `docs/inbox-archive/`, and `docs/changelog-archive/` (monthly bucketed files) so the active files stay lean.

**Task format is a parser contract — not a suggestion.** Every entry in `.redeye/tasks.md` must conform to the canonical shape documented in `templates/TASK_FORMAT.md`. The Control Tower UI parser and `digest.sh` both use a brittle regex grammar. Non-canonical `- **Field:**` bullets (e.g. `- **Source:**`, `- **Proposal:**`, `- **Acceptance:**`, `- **Notes:**`, `- **Rationale:**`) are **silently dropped from the UI and truncate the multi-line `Description` capture**. Headers like `### T004 (P1): Foo` are silently skipped. Every task-creating agent (TRIAGE, PLAN, BUILD, REVIEW, SCHEDULES) inlines this contract; if you add a new agent that writes to `tasks.md`, copy the "Task Format" section from `agents/triage.md` into it.

## Architecture

| Directory | Contains |
|-----------|---------|
| `agents/` | 13 phase agent definitions |
| `commands/` | 10 slash commands (self-contained — no bridge to a separate skills layer) |
| `scripts/` | Loop runner, digest, archive scripts, secret scanner, project initializer |
| `hooks/` | Stop hook (extends Ralph Loop for iteration management) |
| `templates/` | Control file templates scaffolded by `/redeye:init` |
| `docs/` | (per-project, scaffolded by `/redeye:init`) `docs/briefs/`, `docs/specs/`, `docs/decisions/`, `docs/tasks-archive/`, `docs/specs-archive/` |

## Requirements

- Claude Code with plugin and Agent tool support
- `ralph-loop` plugin (provides the infinite loop mechanism)
- `jq` (used by digest.sh for zero-token state parsing)

## Troubleshooting

- **Task blocked?** Check `.redeye/inbox.md` for questions that need answers
- **Environment broken?** RedEye enters STABILIZE — check `.redeye/status.md`
- **Task parked after 3 reviews?** Review the feedback, adjust the task, or steer with directives
- **Loop not starting?** Verify `.redeye/state.json` exists (run `/redeye:init`) and `ralph-loop` plugin is installed

## Development Conventions

- `set -euo pipefail` in all shell scripts
- `jq --arg` for all user-supplied values (injection prevention)
- Atomic writes: temp file + `mv` for `.redeye/state.json`
- `bash scripts/lock.sh` for concurrent git operations between instances (portable wrapper; macOS has no `flock(1)`)
- Agent scope boundaries enforced at prompt level
- Conventional commits: `redeye: {description}`

## Note for consumers using JS/TS bundlers

RedEye creates per-task worktrees at `<project>/.worktrees/T<id>/` — full project-tree clones. Bundlers without a directory-exclude API will index these and blow up memory (Next.js 16 / Turbopack hit 80+ GB on Control Tower three times before the workaround). If your project's dev server walks the project root, mask `**/.worktrees/**` in its watcher config or run dev on a bundler that honors ignores (webpack `watchOptions.ignored`, Vite `server.watch.ignored`).
