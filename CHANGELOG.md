# Changelog

## [Unreleased]

### Added
- **Archive scripts** — four scripts sweep done/incorporated/old content out of active control files at each MERGE, keeping the files TRIAGE reads every iteration from growing unbounded:
  - `scripts/archive-task.sh` — moves `Status: done` task bodies from `tasks.md` to `docs/tasks-archive/YYYY-MM.md` (atomic, per-month mkdir lock for concurrency safety)
  - `scripts/archive-wontdo.sh` — sweeps `Status: wontdo` tasks (and legacy `wont-do` / `won't do` variants) into the same monthly archive
  - `scripts/archive-inbox.sh` — moves incorporated Q-XXX entries from `inbox.md` to `docs/inbox-archive/YYYY-MM.md`
  - `scripts/archive-changelog.sh` — moves prior-month iteration blocks from `changelog.md` to `docs/changelog-archive/YYYY-MM.md`
  All four run from MERGE step 6e alongside each other; each is idempotent.
- **Idle short-circuit in `commands/start.md`** — Step 5a checks the digest immediately after loop start and emits `<promise>CEO DIRECTED STOP</promise>` when no work is available, so headless spawns halt cleanly without dispatching a no-op TRIAGE agent.
- **Stop-hook upward-traversal guard** — `hooks/stop-hook.sh` now exits cleanly when the upward search for `.redeye/state.json` reaches `/` without finding a project, preventing stray file writes at the filesystem root.

### Changed
- **`commands/` are now self-contained** — `skills/start/` and `skills/init/` have been removed. The 10 slash commands (`commands/*.md`) contain their logic inline and no longer bridge to a separate skills layer.
- **`init-project.sh` gitignores all `.redeye/*` control files** — previously only `state.json` and `digest.json` were gitignored by default; now every control file (config, tasks, steering, inbox, status, changelog, feedback, schedules, tester-reports, specs, gate files, session logs) is added to the project's `.gitignore` on init. The plugin assumes single-machine, filesystem-shared state.
- **TRIAGE "Sync from main" step removed** — `agents/triage.md` no longer has a sync step; the plugin assumes `.redeye/*` is gitignored and filesystem-local.
- **CTO idle short-circuit is authoritative** — `agents/triage.md` returns `Next phase: IDLE` instead of emitting the `<promise>CEO DIRECTED STOP</promise>` tag directly; the CTO orchestrator in `agents/cto.md` emits the tag, keeping the kill-signal emission in a single place.

## [0.1.0] — 2026-04-28

Initial public release. See [README.md](README.md) and the [Limitations](README.md#limitations) section for scope.
