---
name: Bug report
about: Something doesn't work as expected
title: ''
labels: bug
---

**What happened?**
A clear description of what went wrong.

**Expected behavior**
What you expected to happen instead.

**Reproduction steps**
1. Ran `/redeye:init` in `...`
2. Added task `...`
3. Ran `/redeye:start`
4. After N iterations, saw `...`

**Logs / state**
- Relevant lines from `.redeye/status.md` or `.redeye/changelog.md`
- Output of `cat .redeye/state.json | jq '.phase, .phase_status, .iteration'`
- Last CTO commit: `git log --oneline -5`

**Environment**
- OS:
- Claude Code version:
- `ralph-loop` plugin version:
- RedEye version (from `plugin.json`):
- `jq` version: `jq --version`
- `git` version: `git --version`

**Additional context**
Anything else that might help diagnose the issue.
