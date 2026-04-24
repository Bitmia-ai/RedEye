#!/usr/bin/env bats

# Agent-prompt invariants. The agent prompts are RedEye's product surface —
# the autonomous loop is only as correct as what cto.md / triage.md / merge.md
# instruct the LLM to do. Unit-testing prompts deterministically isn't
# possible, but we CAN pin the load-bearing claims: every named bug-class
# this prose was written to prevent should have a corresponding grep here.
#
# When a reviewer asks "show me the test for the Turbopack 80 GB blow-up
# guidance" or "show me the test for the stale-loop teardown rule," the
# answer is in this file.

load test_helper

agents_dir="$REDEYE_ROOT/agents"

# ------------------------------------------------------------------ frontmatter

@test "every agent has YAML frontmatter with name + description" {
  for f in "$agents_dir"/*.md; do
    head -1 "$f" | grep -q "^---$" || { echo "$f missing frontmatter"; return 1; }
    grep -q "^name:" "$f" || { echo "$f missing name:"; return 1; }
    grep -q "^description:" "$f" || { echo "$f missing description:"; return 1; }
  done
}

@test "no agent frontmatter has duplicate model: key" {
  # Earlier bug: documenter.md had two model: lines (haiku, sonnet) — YAML
  # parsers picked one non-deterministically. Reject any frontmatter with
  # more than one model: directive.
  for f in "$agents_dir"/*.md; do
    n="$(awk '/^---$/{c++; next} c==1 && /^model:/' "$f" | wc -l)"
    [ "$n" -le 1 ] || { echo "$f has $n model: lines"; return 1; }
  done
}

@test "every shell-running phase agent has the worktree CWD-discipline note" {
  # Bug class: agent dispatches into a worktree (`cd $WORKTREE_PATH`) in one
  # Bash tool call, then runs `npm run build` in a SEPARATE Bash tool call.
  # Each Bash invocation is a fresh shell — `cd` doesn't persist. The build
  # lands in main's CWD, contaminates main's `.next/` (or equivalent), and
  # breaks any dev server reading from it. Real incident: Control Tower's
  # T123 DEPLOY rebuilt main's `.next/` while CT's prod server was reading
  # from it; chunk references went stale; UI 404s.
  #
  # Fix: every agent that runs shell commands inside a worktree must tell
  # the LLM to inline `cd "$WORKTREE_PATH" && …` in EVERY Bash call.
  for f in build review deploy verify stabilize; do
    grep -qE 'cd[[:space:]]+.*WORKTREE_PATH.*&&|cd.*does NOT persist|cd doesn'"'"'t persist' \
      "$agents_dir/$f.md" \
      || { echo "$f.md missing CWD-discipline note"; return 1; }
  done
}

@test "every phase agent has the UNTRUSTED-DATA banner" {
  # Bug class: an agent reads task titles / inbox text / git diff content
  # without explicit untrusted-data framing, then either substitutes it
  # into a shell command or follows an adversarial instruction inline.
  for f in plan build review deploy verify merge stabilize incorporate \
           schedules triage documenter; do
    grep -q "UNTRUSTED" "$agents_dir/$f.md" \
      || { echo "$f.md missing UNTRUSTED banner"; return 1; }
  done
}

@test "every agent that touches code or config declares its scope" {
  # The "Do NOT read files outside your listed scope" line is the untrusted-
  # data containment per agent. Phase agents that act on the project should
  # all have it. (cto.md is the orchestrator and is scope-by-dispatch.)
  for f in plan build review deploy verify merge stabilize incorporate \
           schedules triage; do
    grep -q "Do NOT read files outside your listed scope" \
      "$agents_dir/$f.md" \
      || { echo "$f.md missing scope-restriction line"; return 1; }
  done
}

# ----------------------------------------------------------------- cto.md core

@test "cto.md tells worktree creation to run BEFORE the in-progress commit" {
  # Bug class: PLAN→BUILD with no worktree because Step 4 (commit "start
  # BUILD") executed before Step 3 (create worktree). Result: BUILD runs on
  # main, contaminates the working tree. The fix renumbered + added an
  # explicit STOP guard.
  grep -q "Run this step BEFORE Step 4" "$agents_dir/cto.md"
  grep -q "STOP" "$agents_dir/cto.md"
}

@test "cto.md uses \$T_ID not \$BL_ID for worktree creation" {
  # \$BL_ID was a stale variable name from the Backlog→Task rename.
  ! grep -q '\$BL_ID' "$agents_dir/cto.md"
  grep -q '\$T_ID' "$agents_dir/cto.md"
}

@test "cto.md has the stale-loop teardown block" {
  # Bug class: a phase died with worktree_path set; next iteration's
  # crash-recovery resumes the dead worktree, leaking work. cto.md Step 1
  # should detect state_age_seconds > 14400 (4h) and reset to TRIAGE.
  grep -qE "state_age_seconds.*14400|14400.*state_age_seconds" \
    "$agents_dir/cto.md"
  grep -q "TRIAGE" "$agents_dir/cto.md"
}

@test "cto.md gates worktree creation on worktree_enabled" {
  # Bug class: agents create worktrees even when the user disabled them
  # in config.md. cto.md must check worktree_enabled before invoking
  # worktree.sh.
  grep -q "worktree_enabled" "$agents_dir/cto.md"
}

@test "cto.md routes via tasks_summary, not raw tasks.md reads" {
  # Bug class: CTO reading tasks.md directly bloats prompt + drifts from
  # digest. cto.md must route via tasks_summary fields the digest emits.
  grep -q "tasks_summary" "$agents_dir/cto.md"
  ! grep -qE 'cat .*\.redeye/tasks\.md' "$agents_dir/cto.md"
}

# ---------------------------------------------------------- triage / push gate

@test "triage.md preserves local STOP/PAUSE directives through sync" {
  # Bug class: triage.md overwrites local steering.md with origin/main's
  # version. If the CEO just ran /redeye:stop and the STOP line isn't yet
  # pushed, sync clobbers the kill switch. The prose must call this out
  # explicitly and instruct the agent to re-append unpushed STOP/PAUSE.
  grep -qE "STOP.*PAUSE|preserve.*STOP|STOP.*preserve" \
    "$agents_dir/triage.md"
}

@test "triage.md does not instruct any push to a remote" {
  # README promises "never pushes to a remote." triage.md previously had a
  # Step 6 that pushed claims to origin/main. The fix made claims local-only.
  ! grep -qE 'git push|push to (remote|origin)' "$agents_dir/triage.md"
}

@test "triage.md reads .active-claims.json from the local working tree" {
  # Pair with the no-push rule above: claims read must NOT use
  # `git show origin/main:` (which fails when there's no remote).
  ! grep -q "origin/main:.active-claims.json" "$agents_dir/triage.md"
  grep -q ".active-claims.json" "$agents_dir/triage.md"
}

# ---------------------------------------------------------- merge / claim file

@test "merge.md does not push to a remote" {
  ! grep -qE 'git push|push to (remote|origin)' "$agents_dir/merge.md"
}

@test "no phase agent instructs a push to a remote" {
  # README promises "never pushes to a remote." All phase agents — not
  # just triage/merge — must respect that.
  for f in plan build review deploy verify merge stabilize incorporate \
           schedules triage documenter; do
    if grep -qE 'git push|push to (remote|origin)' "$agents_dir/$f.md"; then
      echo "$f.md instructs a remote push"; return 1
    fi
  done
}

@test "merge.md uses bash scripts/lock.sh, not bare flock" {
  # macOS has no flock(1). All git-on-main writes must go through the
  # portable lock.sh wrapper, not `flock` directly.
  ! grep -qE '^\s*flock |\bflock "' "$agents_dir/merge.md"
  grep -q "scripts/lock.sh" "$agents_dir/merge.md"
}

@test "every agent's model: value is a known Claude model" {
  # Catches typos like `model: sonet` or `model: haku` that would silently
  # leave the agent on the platform default.
  for f in "$agents_dir"/*.md; do
    model="$(awk '/^---$/{c++; next} c==1 && /^model:/' "$f" | head -1 \
             | sed 's/^model:[[:space:]]*//')"
    [ -z "$model" ] && continue
    case "$model" in
      haiku|sonnet|opus) ;;
      *) echo "$f has unknown model: $model"; return 1 ;;
    esac
  done
}

@test "merge.md scope includes .active-claims.json" {
  grep -q ".active-claims.json" "$agents_dir/merge.md"
}

# ---------------------------------------------------- incorporate / answer-loop

@test "incorporate.md instructs the agent to write **Incorporated:**" {
  # Bug class: digest counts ceo_answers_pending by absence of this field.
  # If the prompt forgets to write it, INCORPORATE re-runs forever.
  grep -q "Incorporated:" "$agents_dir/incorporate.md"
}

# -------------------------------------------------------- review / circuit-break

@test "review.md enforces max_review_cycles park-and-route" {
  # After 3 failed review cycles a task must be parked, not endlessly
  # re-built. review.md owns the circuit breaker.
  grep -qE "review_cycles.*max_review_cycles|max_review_cycles.*review_cycles" \
    "$agents_dir/review.md"
  grep -q "park" "$agents_dir/review.md"
}

# ----------------------------------------------------- terminology consistency

@test "no source file has legacy terminology (HARDEN / BL- / backlog / feature cycle)" {
  # Combined rename-migration guard. HARDEN was removed; BL_ prefix and
  # "backlog" were renamed to T_ and "tasks"; "feature cycle" / "park
  # feature" / "the planned feature" / "next feature" / "Current feature"
  # all became "task" variants. Also catches dead schema fields:
  # `current_feature`, `feature_id`, `feature_title`, `next_bl_id`.
  #
  # Scope is broad — every place a contributor might leave drift:
  #   agents/, commands/, skills/, scripts/, hooks/, templates/, tests/,
  #   plus root .md files (README, CLAUDE, CONTRIBUTING, SECURITY,
  #   CHANGELOG) and examples/.
  while IFS= read -r -d '' f; do
    # Skip the test file itself — it quotes the legacy terms in the regex.
    [[ "$f" == */tests/agents.bats ]] && continue
    if grep -qE "\\bHARDEN\\b|\\bBL[-_][0-9]|\\bBL_ID\\b|\\bbacklog\\b|\\bBacklog\\b|feature cycle|park feature|the planned feature|next feature|Current feature|\\bcurrent_feature\\b|\\bfeature_id\\b|\\bfeature_title\\b|\\bnext_bl_id\\b" "$f"; then
      echo "$f has legacy terminology"
      return 1
    fi
  done < <(find \
    "$REDEYE_ROOT/agents" \
    "$REDEYE_ROOT/commands" \
    "$REDEYE_ROOT/skills" \
    "$REDEYE_ROOT/scripts" \
    "$REDEYE_ROOT/hooks" \
    "$REDEYE_ROOT/templates" \
    "$REDEYE_ROOT/tests" \
    "$REDEYE_ROOT/examples" \
    -type f \( -name "*.md" -o -name "*.sh" -o -name "*.tmpl" -o -name "*.bats" -o -name "*.json" \) \
    -print0)
  for f in "$REDEYE_ROOT"/README.md "$REDEYE_ROOT"/CLAUDE.md \
           "$REDEYE_ROOT"/CONTRIBUTING.md "$REDEYE_ROOT"/SECURITY.md \
           "$REDEYE_ROOT"/CHANGELOG.md; do
    [ -f "$f" ] || continue
    if grep -qE "\\bHARDEN\\b|\\bBL[-_][0-9]|\\bBL_ID\\b|\\bbacklog\\b|\\bBacklog\\b|feature cycle|park feature|the planned feature|next feature|Current feature|\\bcurrent_feature\\b|\\bfeature_id\\b|\\bfeature_title\\b|\\bnext_bl_id\\b" "$f"; then
      echo "$f has legacy terminology"
      return 1
    fi
  done
}

# ---------------------------------------------------- worktree path convention

@test "worktree path convention uses T<id> not T-<id>" {
  # The hyphen was a leftover from BL-NNN. UI/state.json/tasks.md all use
  # T<id>; the worktree path/branch should match.
  ! grep -lE '\\.worktrees/T-[0-9]|redeye/T-[0-9]' \
    "$REDEYE_ROOT/scripts/worktree.sh" "$REDEYE_ROOT/agents"/*.md \
    "$REDEYE_ROOT/README.md" "$REDEYE_ROOT/CLAUDE.md"
}

# ----------------------------------------------- CLAUDE.md bundler-blowup note

@test "CLAUDE.md keeps the JS/TS-bundler worktree warning" {
  # Real bug class: Next.js 16 / Turbopack hit 80+ GB indexing
  # .worktrees/T<id>/ on Control Tower three separate times. The note
  # documents the root cause AND the mitigation. This is the kind of
  # institutional knowledge a staff reviewer asks "where's the test?" for.
  grep -qE "(Turbopack|bundler|directory-exclude)" \
    "$REDEYE_ROOT/CLAUDE.md"
  grep -qE "watchOptions\\.ignored|server\\.watch\\.ignored" \
    "$REDEYE_ROOT/CLAUDE.md"
}

# -------------------------------------------------- digest <-> agent contracts

@test "fields agents read from the digest are emitted by digest.sh" {
  # If cto.md tells the orchestrator to consult `phase` / `tasks_summary` /
  # `worktree_enabled` / `stop_directive` / `pause_directive`, digest.sh must
  # actually emit those keys. Drift here breaks the orchestration silently.
  for field in phase phase_status iteration stop_directive pause_directive \
               steering_directives env_healthy confidence tasks_summary \
               overdue_schedules ceo_answers_pending tester_reports_new \
               current_task worktree_path worktree_branch worktree_enabled \
               state_age_seconds validation_warnings; do
    grep -q "$field:" "$REDEYE_ROOT/scripts/digest.sh" \
      || { echo "digest.sh missing field $field"; return 1; }
  done
}
