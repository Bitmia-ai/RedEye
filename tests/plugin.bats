#!/usr/bin/env bats

# Plugin manifest invariants. A typo in plugin.json or marketplace.json
# breaks `claude /plugin install` for every user.

load test_helper

@test ".claude-plugin/plugin.json is valid JSON" {
  jq empty "$REDEYE_ROOT/.claude-plugin/plugin.json"
}

@test ".claude-plugin/marketplace.json is valid JSON" {
  jq empty "$REDEYE_ROOT/.claude-plugin/marketplace.json"
}

@test "plugin.json declares name, version, license, repository" {
  for k in name version license repository; do
    val="$(jq -r --arg k "$k" '.[$k] // empty' "$REDEYE_ROOT/.claude-plugin/plugin.json")"
    [ -n "$val" ] || { echo "plugin.json missing $k"; return 1; }
  done
}

@test "plugin.json declares an explicit permissions allowlist" {
  # Surfaces blast radius. Without this declaration the plugin inherits
  # the user's full tool surface — security reviewers should be able to
  # see what RedEye uses without reading every script.
  count="$(jq -r '.permissions.allow | length // 0' "$REDEYE_ROOT/.claude-plugin/plugin.json")"
  [ "$count" -gt 0 ]
}

@test "plugin.json permissions scope Read/Write/Edit to the project tree" {
  for tool in Read Write Edit; do
    found="$(jq -r --arg t "$tool" '.permissions.allow[] | select(startswith($t + "("))' \
             "$REDEYE_ROOT/.claude-plugin/plugin.json" | head -1)"
    [ -n "$found" ] || { echo "$tool not in permissions.allow"; return 1; }
    # Must scope to ./** (project tree), not ** (anywhere).
    [[ "$found" == *"./**"* ]] || { echo "$tool not scoped to ./**: $found"; return 1; }
  done
}
