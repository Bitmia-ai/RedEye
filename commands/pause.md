---
description: "Pause the team after the current task cycle completes"
---

Write `PAUSE — CEO directed pause at {current ISO timestamp}` to the `## Directives` section of .redeye/steering.md.

The CTO will:
1. Finish the current task cycle (through MERGE)
2. Then output the completion promise and stop

Tell the user: "Pause directive written to .redeye/steering.md. The team will finish the current task cycle and pause cleanly. This may take several iterations depending on the current phase."

Note: Use /redeye:stop for immediate stop (finishes current phase only, not the full cycle).
