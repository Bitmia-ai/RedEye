---
description: "Add a steering directive for the team"
argument-hint: "<directive>"
---

Read the arguments provided as the directive text.

If no arguments provided, ask the user: "What directive should I add to .redeye/steering.md?"

Append a timestamped entry to the `## Directives` section of .redeye/steering.md:

```
{ISO timestamp} — {directive text}
```

Tell the user: "Directive added to .redeye/steering.md. The team will see it at the start of the next phase (usually within 5-15 minutes)."
