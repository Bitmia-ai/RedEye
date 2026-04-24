---
description: "Manage scheduled recurring tasks"
---

Read .redeye/schedules.md from the project root.

**Show current schedules:**
List all SCHED-{id} entries with title, frequency, and last run time.

**Offer interactive management via AskUserQuestion:**
- "Add new schedule" — ask for: title, frequency (minimum 1 hour), steps, assigned role(s). Create SCHED-{id} entry.
- "Edit schedule" — show list, let user select, edit fields
- "Remove schedule" — show list, let user select, remove entry
- "Done" — exit

**Validation:**
- Minimum frequency is 1 hour. If user enters less, warn: "Minimum frequency is 1 hour to control costs. Please enter a longer frequency."

After any changes:
```bash
git add .redeye/schedules.md .redeye/state.json
git commit -m "redeye: update schedules"
```
