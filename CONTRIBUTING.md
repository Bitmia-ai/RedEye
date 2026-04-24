# Contributing to RedEye

Thanks for considering a contribution! RedEye is a personal project and development is infrequent, but issues and PRs are welcome.

## Before you start

- **Open an issue first** for anything larger than a typo or minor doc fix. This saves you time — some ideas don't fit the opinionated-not-flexible design stance.
- **Read the [README](README.md)** and skim [CLAUDE.md](CLAUDE.md) for architecture.

## Local development

Clone, then load the plugin via `--plugin-dir`:

```bash
git clone https://github.com/Bitmia-ai/RedEye.git
claude --plugin-dir ./RedEye
```

Try it on a sample project from inside that Claude Code session:

```
/redeye:init
/redeye:tasks  # add a trivial task
/redeye:start
```

## Code style

- `set -euo pipefail` in all shell scripts
- `jq --arg` for all user-supplied values (no string interpolation in JSON)
- Atomic writes for `.redeye/state.json` (temp file + `mv`)
- Agent scope boundaries enforced in prompts — don't read files outside the listed scope
- Conventional commit messages: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `perf:`

## Agent prompt changes

Changes to `agents/*.md` affect runtime behavior. Please:
1. Explain the intent in the PR description
2. If adding a transition rule, show where it routes in `cto.md`
3. Respect the untrusted-data warnings — every phase treats task list/steering/inbox content as untrusted

## Testing

RedEye ships a [bats](https://github.com/bats-core/bats-core) suite under `tests/` covering the shell scripts and structural invariants of the agent prompts. CI runs the suite on every push and PR via `.github/workflows/test.yml`.

Scripts with test coverage: `digest.sh`, `secret-scan.sh`, `worktree.sh`, `lock.sh`, `init-project.sh`, `archive-task.sh`, `archive-inbox.sh`, `archive-changelog.sh`, `archive-wontdo.sh`, `hooks/stop-hook.sh`. Agent prompt structural invariants (UNTRUSTED-DATA banner, scope declarations, no-push-to-remote, digest-field contract) are checked in `tests/agents.bats`. Plugin manifest integrity is checked in `tests/plugin.bats`. Command/skill sync is checked in `tests/command-skill-sync.bats`.

Run locally:

```bash
brew install bats-core jq                 # macOS
# apt-get install bats jq                 # Debian/Ubuntu
bats tests/
```

Add a test alongside any change that touches `scripts/*.sh` or `hooks/*.sh`. Agent-prompt changes (`agents/*.md`) have **structural** invariants in [`tests/agents.bats`](tests/agents.bats) — every phase agent is checked for the UNTRUSTED-DATA banner, scope declaration, no-push-to-remote, terminology consistency, and digest-field contract. These catch regressions in the prose contract; they don't catch behavioral drift, so describe the behavior change in your PR description as well. New archive scripts should have a corresponding `tests/archive-<name>.bats` file.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities. Do not open public issues for security bugs.
