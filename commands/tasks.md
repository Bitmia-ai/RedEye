---
description: "Add to or manage the project task list"
argument-hint: "[vague idea or full title]"
---

**Task creation MUST go through `scripts/create-task.sh`.** Hand-authored markdown blocks in `.redeye/tasks.md` bypass the parser contract (see `templates/TASK_FORMAT.md`) and silently disappear from the Control Tower UI. This command is a thin user-facing wrapper around the script — never edit `tasks.md` directly to add an entry.

**If arguments were provided** (a vague idea, a sentence, or a full title):

You expand the input into structured flags for `scripts/create-task.sh`. The user should NOT have to write a spec — their one-liner is enough.

1. Read `.redeye/tasks.md` and `.redeye/config.md` to understand the project context (stack, conventions, vision) and avoid duplicating an existing item.

2. Interpret the user's input:
   - Pull a short imperative **title** from it (e.g., "dark mode would be nice" → "Add dark mode toggle")
   - Infer the **type** from the wording: feature / bug / security / tech-debt / infra / ux / test / docs
   - Infer a **priority** (P0 / P1 / P2 / P3) from urgency words ("critical", "nice to have", "ASAP", etc.) — default P2 if unclear
   - Sketch a 2–4 sentence **description** with concrete acceptance criteria the TRIAGE/PLAN agents can use. Do NOT invent constraints the user didn't imply. If something is truly ambiguous, write it as a question PLAN will resolve (e.g., "Decision: which icon library to use for the toggle").

3. Write the description to a temp file:
   ```bash
   cat > /tmp/redeye-task-desc.md <<'EOF'
   <free-form 2–4 sentences>

   **Acceptance**

   - <criterion 1>
   - <criterion 2>
   EOF
   ```

4. Call the script with `--section ceo` (freeform human input lands in `## CEO Requests` so the human can review before TRIAGE picks it up):
   ```bash
   bash scripts/create-task.sh \
     --section ceo \
     --title "<inferred title>" \
     --type "<inferred type>" \
     --priority "<inferred priority>" \
     --description-file /tmp/redeye-task-desc.md
   ```

5. The script handles atomic ID allocation, the canonical block format, and the `state.json.counters.next_task_id` bump. It prints the allocated ID to stdout.

6. Stage and commit:
   ```bash
   git add .redeye/tasks.md .redeye/state.json
   git commit -m "redeye: ceo request — <title>"
   ```

7. Show the user the allocated ID and confirm: "Added T{id}. TRIAGE will pick it up next iteration. You can `/redeye:tasks` again to tweak it."

**If no arguments provided** (interactive mode):

1. Read `.redeye/tasks.md` and show a compact summary:
   - CEO Requests (count + titles)
   - Discovered items pending triage (count + titles)
   - Triaged/planned items (count + titles)
   - In-progress item (if any)
2. Offer via AskUserQuestion:
   - **Add new item** — ask for the idea in plain words, then expand-and-invoke-script as above
   - **Reprioritize** — show planned items, let user reorder (hand-edit OK for reordering — no new entries created)
   - **Done** — exit

## Why the wrapper

`scripts/create-task.sh` enforces the parser contract: it allocates IDs from `state.json` atomically, writes the block in the exact shape the Control Tower UI parses, refuses non-canonical bullets that would truncate the `Description` field, and rejects malformed headers like `### T004 (P1):` that the parser silently skips. There is no other supported path — agents (TRIAGE/PLAN/BUILD/REVIEW/SCHEDULES/INCORPORATE) all call the same script. See `commands/create-task.md` and `templates/TASK_FORMAT.md` for the full contract.
