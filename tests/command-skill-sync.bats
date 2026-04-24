#!/usr/bin/env bats

# tests/command-skill-sync.bats — pin the contract that the entrypoint slash
# commands (start, init) stay self-contained instead of degenerating into
# stubs that "invoke the redeye:X skill". Claude Code 2.1.122 has a resolver
# collision where the Skill tool, called with a plugin-namespaced name,
# dispatches to a same-named slash command — which creates an infinite
# re-injection loop and wedges the autonomous CTO. The skill files were
# removed on 2026-04-29; this test prevents the bridge pattern from creeping
# back in via slash command body changes.

load test_helper

# Strip frontmatter and any leading HTML comment so we test the actual
# instruction body, not the metadata wrapper or the do-not-do warning.
strip_metadata() {
  local file="$1"
  awk '
    BEGIN { in_fm = 0; fm_done = 0 }
    /^---$/ {
      if (!fm_done) { in_fm = !in_fm; if (!in_fm) fm_done = 1; next }
    }
    in_fm { next }
    !comment_done && /^<!--/ { in_comment = 1 }
    in_comment {
      if ($0 ~ /-->/) { in_comment = 0; comment_done = 1 }
      next
    }
    !content_started && /^[[:space:]]*$/ { next }
    { content_started = 1; print }
  ' "$file"
}

REDEYE_ROOT_FOR_THIS_REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "commands/start.md is self-contained (no 'invoke skill' bridge stub)" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  echo "$body" | grep -iqE 'invoke[[:space:]]+the[[:space:]]+`?redeye:start`?[[:space:]]+skill' && {
    echo "commands/start.md regressed to the brittle skill-bridge pattern."
    echo "This breaks Claude Code 2.1.122 (namespace collision Skill→command)."
    return 1
  }
  return 0
}

@test "commands/init.md is self-contained (no 'invoke skill' bridge stub)" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/init.md")"
  echo "$body" | grep -iqE 'invoke[[:space:]]+the[[:space:]]+`?redeye:init`?[[:space:]]+skill' && {
    echo "commands/init.md regressed to the brittle skill-bridge pattern."
    return 1
  }
  return 0
}

@test "commands/start.md retains the canonical Step 1 'Validate Setup' header" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  echo "$body" | grep -qF "## Step 1: Validate Setup" || {
    echo "commands/start.md is missing its canonical Step 1 header."
    echo "Either the body got rewritten unrecognizably or it lost its content."
    return 1
  }
}

@test "commands/start.md retains the start-loop.sh invocation step" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  # start-loop.sh creates .claude/ralph-loop.local.md — without it the
  # session won't auto-loop. This is the load-bearing step.
  echo "$body" | grep -qF "start-loop.sh" || {
    echo "commands/start.md no longer invokes start-loop.sh — the autonomous"
    echo "loop will not start without it. See Step 5 of the original body."
    return 1
  }
}

@test "commands/init.md retains the canonical 'Pre-flight Check' section" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/init.md")"
  echo "$body" | grep -qF "## Pre-flight Check" || {
    echo "commands/init.md is missing its canonical Pre-flight Check header."
    return 1
  }
}

@test "commands/init.md retains the init-project.sh invocation step" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/init.md")"
  echo "$body" | grep -qF "init-project.sh" || {
    echo "commands/init.md no longer invokes init-project.sh — initialization"
    echo "will silently produce a broken project."
    return 1
  }
}

@test "commands/start.md contains the idle short-circuit STOP path" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  # Without an explicit STOP-on-idle check in the start command body, the
  # model interprets `/redeye:start` as "always begin an iteration" and
  # dispatches TRIAGE even when all queues are empty — which is the bug we
  # hit on 2026-04-29 (iter 188-190 spinning despite digest reporting idle).
  echo "$body" | grep -qF "Idle short-circuit" || {
    echo "commands/start.md is missing the 'Idle short-circuit' section."
    echo "Without it, the model dispatches TRIAGE on empty backlogs and"
    echo "the loop never stops on its own."
    return 1
  }
}

@test "commands/start.md does NOT use AskUserQuestion (runs in headless mode)" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  # `/redeye:start` is the entrypoint that ControlTower invokes via
  # `claude --print --plugin-dir ... -p "Run /redeye:start ..."`. Headless
  # mode has no terminal for the user to answer prompts; AskUserQuestion
  # errors and the model loops trying to "fix the format" — the bug we hit
  # on 2026-04-29 (Step 4 "Confirm: Ready to start?"). Invoking the start
  # command IS the user's confirmation; do not re-ask.
  echo "$body" | grep -qiE 'AskUserQuestion' && {
    echo "commands/start.md uses AskUserQuestion. This wedges in headless"
    echo "spawns (CT-managed CTO loops) where there is no user to answer."
    return 1
  }
  return 0
}

@test "commands/start.md spells out the literal CEO DIRECTED STOP promise tag" {
  body="$(strip_metadata "$REDEYE_ROOT_FOR_THIS_REPO/commands/start.md")"
  # The promise tag has to appear verbatim in the prompt so the model
  # emits it byte-for-byte — ralph-loop's stop-hook regex matches the
  # exact string `<promise>CEO DIRECTED STOP</promise>` and nothing else.
  echo "$body" | grep -qF '<promise>CEO DIRECTED STOP</promise>' || {
    echo "commands/start.md no longer contains the literal completion-promise"
    echo "tag <promise>CEO DIRECTED STOP</promise>. Without it the model has"
    echo "no reference for what string to emit, and ralph-loop never halts."
    return 1
  }
}

@test "skills/ directory does not contain start or init (collision sources removed)" {
  # If anyone re-creates skills/start/ or skills/init/, the namespace
  # collision is back. The cleanup on 2026-04-29 deleted both.
  [ ! -e "$REDEYE_ROOT_FOR_THIS_REPO/skills/start" ]
  [ ! -e "$REDEYE_ROOT_FOR_THIS_REPO/skills/init" ]
}
