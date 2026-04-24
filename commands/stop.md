---
description: "Gracefully stop the autonomous dev loop"
---

Write `STOP — CEO directed stop at {current ISO timestamp}` to the `## Directives` section of .redeye/steering.md in the project root. The CTO checks .redeye/steering.md at the start of every phase and will finish the current phase cleanly before stopping.

Tell the user: "Stop directive written to .redeye/steering.md. The team will finish the current phase and shut down cleanly (usually within 1 iteration, ~5-15 minutes)."
