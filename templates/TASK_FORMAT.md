# Task Format (STRICT — parser contract)

The Control Tower UI and the digest.sh state machine both parse `.redeye/tasks.md` with a single, brittle regex grammar. Tasks that don't match the canonical shape are **silently dropped or truncated**. There is no warning, no log line, no UI badge — they just disappear.

**Use `scripts/create-task.sh` to create tasks.** It is the only path that mechanically enforces this contract: it allocates IDs atomically from `state.json.counters.next_task_id`, writes the canonical block, rejects non-canonical bullets that would truncate the `Description` field, and inserts into the correct section. The agents (TRIAGE / PLAN / BUILD / REVIEW / SCHEDULES / INCORPORATE) and the user-facing slash commands (`/redeye:tasks`, `/redeye:brainstorm`) all call the same script. This document describes the contract the script enforces — read it when you need to *understand* the parser, not when you need to *create* a task.

Hand-edits to `tasks.md` are accepted only for: status flips (e.g. `pending` → `in-progress`), moving an item between sections (e.g. Discovered → Triaged), and the `- **Summary:**` append at MERGE. Never hand-author a new `### T<NNN>:` block.

## Canonical task block

```
### T<NNN>: <title>
- **Type:** <one line — feature | bug | tech-debt | docs | infra | ux | security | test | ...>
- **Priority:** <one line — P0 | P1 | P2 | P3 (case-insensitive; see legacy mapping below)>
- **Status:** <one of: pending | pending-triage | planned | in-progress | done | blocked | wontdo>
- **Spec:** docs/specs/T<NNN>-<slug>.md            ← optional, single line
- **Summary:** <one line — set by MERGE when work ships>   ← optional, single line
- **Description:**
  <Free-form markdown. ALL auxiliary content goes here: source, proposal,
  acceptance criteria, risk, rationale, notes, method, owner, files-touched,
  not-in-scope, etc. Use plain markdown sub-headers (e.g. `**Acceptance**`)
  inside the description — NOT as `- **Xxx:**` bullets at task level.>
```

## Priority — canonical alphabet

Only `P0`, `P1`, `P2`, `P3` (case-insensitive, normalised to upper). `scripts/create-task.sh` rejects the legacy word forms (`critical`/`high`/`medium`/`low`) with a hint to the equivalent P-tier:

| Legacy | Canonical |
|--------|-----------|
| critical | P0 |
| high     | P1 |
| medium   | P2 |
| low      | P3 |

The Control Tower UI parser still reads the legacy forms in tasks that pre-date the conversion (the field is a free-form string), but no agent or human path emits them anymore.

## Allow-listed field markers

ONLY these `- **Field:**` bullets are recognised by the parser:

```
Type   Priority   Status   Spec   Summary   Description   Details   Reason   Merged
```

Anything else (`- **Source:**`, `- **Proposal:**`, `- **Acceptance:**`, `- **Risk:**`, `- **Owner:**`, `- **Notes:**`, `- **Rationale:**`, `- **Current state:**`, `- **Not in scope:**`, `- **Method.**`, `- **Token budget.**`, `- **RoI guardrails.**`, `- **Files to refresh:**`, ...) is **silently dropped** from the UI.

Worse: the parser uses `\n- **` as the boundary of the multi-line `Description` capture. So a single stray `- **Xxx:**` bullet after `- **Description:**` **truncates the description at that point**. Everything from that bullet onward disappears from the UI's rendered task page.

## Header rules

- **Format is exactly `### T<NNN>: <title>`.** Single colon, no qualifier in parens, no trailing period. The parser regex is `/^### (T\d+):\s*(.+)$/m` — `### T004 (P1): Foo`, `### T004.1:`, `### t004:`, `### T4:` will all be silently skipped.
- **`T<NNN>` is zero-padded to ≥3 digits.**
- **IDs come from `state.json.counters.next_task_id`.** Allocate sequentially, bump the counter atomically (temp-file + rename), commit `state.json` + `tasks.md` in the same commit. No sub-task IDs like `T003a` / `T003b` — every new entry is a first-class task.

## Status values

The parser's `normalizeStatus()` recognises (case-insensitive):

- `pending` (default — anything unknown falls back here, hiding bugs)
- `pending-triage` / `pending triage`
- `planned`
- `in-progress` / `in progress`
- `done` / `complete` / `completed`
- `blocked`
- `wont-do` / `wontdo` / `won't do`

Avoid creative variants — they silently degrade to `pending`.

## Sections

`tasks.md` has exactly four `## ` sections, in this order:

1. `## CEO Requests` — only the human user adds here. Agents NEVER modify this section.
2. `## Discovered` — agents append here as `pending-triage`. VP Product triages during PLAN.
3. `## Triaged` — VP Product moves entries here after triage, in priority order, marked `planned`.
4. `## Won't Do` — optional; triaged-out entries land here with `Status: wontdo` and a `Reason:` line.

Section headers must be `## ` (two hashes). The parser stops scanning a section at the next `## ` (it rejects `### ` so sub-items don't escape).

## Putting auxiliary content inside `Description`

What used to be top-level `- **Acceptance:**` becomes inline `**Acceptance**` inside Description. Example:

```markdown
### T042: Replace ad-hoc retry with exponential backoff
- **Type:** tech-debt
- **Priority:** P2
- **Status:** pending
- **Description:**
  **Source.** Discovered during T037 build — three call sites copy-paste a 3×100ms retry loop.

  **Proposal**

  1. Add `lib/retry.ts` with `withBackoff(fn, opts)`.
  2. Replace the three call sites.
  3. Add a unit test that exercises the backoff schedule.

  **Acceptance**

  - No retry literal `for (let i = 0; i < 3; i++)` in the affected files.
  - Unit test covers success, transient-failure, exhausted-retries.

  **Risk.** Low — additive helper, three local call sites.
```

This renders correctly in the UI because Description is one multi-line capture that contains markdown — the parser only cares that no `\n- **` appears between `Description:` and the next task / section boundary.

## Pre-commit checklist (for every agent that writes to tasks.md)

Before staging `.redeye/tasks.md`:

1. Each `### ` heading matches `^### T\d{3,}: \S` — single colon, no parens, real title.
2. Every `- **Field:**` bullet directly under a `### ` heading is in the allow-list above.
3. Long-form content is under exactly one `- **Description:**` (or `- **Details:**` for legacy bullet lists).
4. `state.json.counters.next_task_id` was bumped if any new IDs were minted, in the same commit.
5. Status strings match `normalizeStatus()` exactly.

If any check fails, restructure before committing. Do NOT commit a broken `tasks.md` — the UI will silently lose visibility into your work and the digest will misroute the next iteration.
