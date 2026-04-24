---
description: "Initialize RedEye in current project"
argument-hint: "[--full]"
---

Invoke the redeye:init skill and follow it exactly.

**CRITICAL REMINDER**: Step 5 of the init skill requires running `${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh`. You MUST run this script — do NOT create control files manually. The script creates `.redeye/state.json` which is required for the loop to work. Without it, `/redeye:start` will fail silently.
