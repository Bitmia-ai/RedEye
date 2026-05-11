---
description: "Brainstorm a feature idea into a brief and task"
argument-hint: "[idea]"
---

If arguments provided, use them as the starting idea. Otherwise, ask: "What would you like to brainstorm?"

1. Invoke `superpowers:brainstorming` to explore the idea with the user
2. When the brainstorm produces a design/brief, save it to `docs/briefs/{date}-{slug}.md`
3. Read `.redeye/state.json` to get `counters.next_task_id`
4. Write a description body to a temp file (Markdown OK — sub-headers as `**bold**`, NOT as `- **Xxx:**` bullets):
   ```bash
   cat > /tmp/redeye-brainstorm-{id}.md <<'EOF'
   **Brief:** [docs/briefs/{filename}](docs/briefs/{filename})

   {one-paragraph summary of the brainstorm outcome — what the feature is and why it matters}
   EOF
   ```

5. File the CEO Request via `scripts/create-task.sh` (the ONLY supported path for creating tasks):
   ```bash
   bash scripts/create-task.sh \
     --section ceo \
     --title "{title from brainstorm}" \
     --type feature \
     --priority P2 \
     --description-file /tmp/redeye-brainstorm-{id}.md
   ```
   The script allocates the next `T<NNN>` ID atomically, writes the canonical block, and bumps `state.json.counters.next_task_id`. See `templates/TASK_FORMAT.md` for the parser contract.
5. Increment `counters.next_task_id` in `.redeye/state.json`
6. Commit: `git add docs/briefs/ .redeye/tasks.md .redeye/state.json && git commit -m "redeye: brainstorm — {title}"`
7. Tell the user: "Added T{id}: {title} to task list with brief at docs/briefs/{filename}."
