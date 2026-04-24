---
description: "Add to or manage the project task list"
argument-hint: "[vague idea or full title]"
---

Read `.redeye/state.json` to get the current `counters.next_task_id` value.

**If arguments were provided** (a vague idea, a sentence, or a full title):

You expand the input into a proper task entry. The user should NOT have to write a spec — their one-liner is enough.

1. Read `.redeye/tasks.md` and `.redeye/config.md` to understand the project context (stack, conventions, vision).

2. Interpret the user's input:
   - Pull a short imperative **title** from it (e.g., "dark mode would be nice" → "Add dark mode toggle")
   - Infer the **type** from the wording: feature / bug / security / tech-debt / infra / ux / test
   - Infer a **priority** (P0 / P1 / P2 / P3) from urgency words ("critical", "nice to have", "ASAP", etc.) — default P2 if unclear
   - Sketch 2–5 concrete **details** the TRIAGE/PLAN agents can use: acceptance criteria, likely files touched, edge cases, anything the user implied but didn't say

3. Append to the `## CEO Requests` section:
   ```
   ### T{next_task_id}: {inferred title}
   - **Type:** {inferred type}
   - **Priority:** {inferred priority}
   - **Status:** pending
   - **Details:**
     - {specific detail 1}
     - {specific detail 2}
     - {specific detail 3}
   ```

   Keep the details concise and factual. Do NOT invent constraints the user didn't imply. If something is truly ambiguous, write it as a question the PLAN phase will resolve (e.g., "Decision: which icon library to use for the toggle").

4. Increment `counters.next_task_id` in `.redeye/state.json` (atomic write).

5. Show the user the final entry and confirm: "Added T{id}. TRIAGE will pick it up next iteration. You can `/redeye:tasks` again to tweak it."

**If no arguments provided** (interactive mode):
1. Read `.redeye/tasks.md` and show a compact summary:
   - CEO Requests (count + titles)
   - Discovered items pending triage (count + titles)
   - Triaged/planned items (count + titles)
   - In-progress item (if any)
2. Offer via AskUserQuestion:
   - **Add new item** — ask for the idea in plain words, then expand as above
   - **Reprioritize** — show planned items, let user reorder
   - **Done** — exit
