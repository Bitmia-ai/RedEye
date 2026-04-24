#!/usr/bin/env bash
# Shared bats helpers.

REDEYE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REDEYE_ROOT

setup_tmp_project() {
  TMP_PROJECT="$(mktemp -d)"
  export TMP_PROJECT
  mkdir -p "$TMP_PROJECT/.redeye"
  (cd "$TMP_PROJECT" && git init -q && git config user.email t@t && git config user.name t)
}

teardown_tmp_project() {
  if [[ -n "${TMP_PROJECT:-}" && -d "$TMP_PROJECT" ]]; then
    rm -rf "$TMP_PROJECT"
  fi
}

write_state() {
  cat > "$TMP_PROJECT/.redeye/state.json"
}

write_file() {
  local rel="$1"
  cat > "$TMP_PROJECT/.redeye/$rel"
}

run_digest() {
  run "$REDEYE_ROOT/scripts/digest.sh" "$TMP_PROJECT"
}

digest_json() {
  cat "$TMP_PROJECT/.redeye/digest.json"
}
