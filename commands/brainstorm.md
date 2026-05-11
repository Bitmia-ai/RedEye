---
description: "Brainstorm a feature idea into a brief and task"
argument-hint: "[idea]"
---

If arguments provided, use them as the starting idea. Otherwise, ask: "What would you like to brainstorm?"

1. Invoke `superpowers:brainstorming` to explore the idea with the user
2. When the brainstorm produces a design/brief, save it to `docs/briefs/{date}-{slug}.md`
3. Read `.redeye/state.json` to get `counters.next_task_id`
4. Add a CEO Request to .redeye/tasks.md `## CEO Requests` using the canonical Task Format (see `templates/TASK_FORMAT.md`):
   ```
   ### T{id}: {title from brainstorm}
   - **Type:** feature
   - **Priority:** P2
   - **Status:** pending
   - **Description:**
     **Brief:** [docs/briefs/{filename}](docs/briefs/{filename})

     {one-paragraph summary of the brainstorm outcome — what the feature is and why it matters>
   ```

   **Parser contract reminder.** Do NOT use `- **Brief:**` as a top-level bullet — it is not in the parser allow-list (`Type`, `Priority`, `Status`, `Spec`, `Summary`, `Description`, `Details`, `Reason`, `Merged`) and would be silently dropped. The brief reference belongs inside `Description` as a markdown link.
5. Increment `counters.next_task_id` in `.redeye/state.json`
6. Commit: `git add docs/briefs/ .redeye/tasks.md .redeye/state.json && git commit -m "redeye: brainstorm — {title}"`
7. Tell the user: "Added T{id}: {title} to task list with brief at docs/briefs/{filename}."
