---
description: "Manage scheduled recurring tasks"
---

Read .redeye/schedules.md from the project root.

**Show current schedules:**
List all SCHED-{id} entries with title, frequency, and last run time.

**Offer interactive management via AskUserQuestion:**

- **Add new schedule** — ask for: title, frequency, steps, assigned role(s). Then create the entry via `scripts/create-schedule.sh` (the ONLY supported path for creating schedules — it enforces the 1-hour floor, validates the frequency syntax `every <N><h|d|w>`, atomically allocates the next SCHED-NNN ID from `state.json.counters.next_sched_id`, and inserts the entry at the end of the file):
  ```bash
  bash scripts/create-schedule.sh \
    --title "<title>" \
    --frequency "every <N><h|d|w>" \
    --task-step "<step 1>" \
    --task-step "<step 2>" \
    [--assigned-to "<roles>"] \
    [--last-run "<ISO timestamp>"]
  ```
  Do NOT hand-author `### SCHED-NNN:` blocks — malformed entries (bad frequency, missing fields) are silently skipped by the dashboard's overdue-detection.
- **Edit schedule** — hand-editing existing fields (frequency, steps, assigned-to, last-run) is fine; do not create new entries this way.
- **Remove schedule** — delete the entire `### SCHED-NNN:` block.
- **Done** — exit.

After any changes:
```bash
git add .redeye/schedules.md .redeye/state.json
git commit -m "redeye: update schedules"
```
