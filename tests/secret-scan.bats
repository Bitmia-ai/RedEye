#!/usr/bin/env bats

load test_helper

setup() {
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

@test "secret-scan passes a clean text file" {
  echo "just some normal code" > "$TMP_DIR/clean.txt"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/clean.txt"
  [ "$status" -eq 0 ]
}

@test "secret-scan blocks Stripe live key" {
  echo 'apiKey = "sk_live_abc123XYZdef456ABC789"' > "$TMP_DIR/leak.js"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/leak.js"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks AWS access key" {
  echo "AWS_KEY=AKIAIOSFODNN7EXAMPLE" > "$TMP_DIR/aws.env"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/aws.env"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks GitHub PAT (ghp_)" {
  echo "token = ghp_abcdefghijklmnopqrstuvwxyz0123456789" > "$TMP_DIR/cfg.toml"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/cfg.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks Anthropic key" {
  echo 'KEY="sk-ant-abc123-DEF-456-ghi789-jkl"' > "$TMP_DIR/anth.txt"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/anth.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks PEM private key block" {
  cat > "$TMP_DIR/key.pem" <<'EOF'
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAxxxxxx
-----END RSA PRIVATE KEY-----
EOF
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/key.pem"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan skips lockfiles" {
  echo "ghp_abcdefghijklmnopqrstuvwxyz0123456789" > "$TMP_DIR/package-lock.json"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/package-lock.json"
  [ "$status" -eq 0 ]
}

@test "secret-scan skips test files for entropy heuristic" {
  printf 'const fixture = "%s";\n' "abcdefABCDEF0123456789abcdefABCDEF0123456789abcdef" > "$TMP_DIR/foo.test.js"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/foo.test.js"
  [ "$status" -eq 0 ]
}

@test "secret-scan blocks Stripe restricted key (rk_live_)" {
  echo 'apiKey = "rk_live_abcdef0123456789ABCDEFGHIJKL"' > "$TMP_DIR/leak.js"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/leak.js"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks GitLab token (glpat-)" {
  echo "token = glpat-abcdefghijklmnopqrstuvwxyz" > "$TMP_DIR/cfg.toml"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/cfg.toml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks HuggingFace token (hf_)" {
  echo "HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz0123456789" > "$TMP_DIR/.env.txt"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/.env.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks npm token (npm_)" {
  echo "//registry.npmjs.org/:_authToken=npm_abcdefghijklmnopqrstuvwxyz0123456789" > "$TMP_DIR/.npmrc.txt"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/.npmrc.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan blocks OpenAI project key (sk-proj-)" {
  echo 'OPENAI_KEY="sk-proj-abcdefghijklmnopqrstuvwxyz0123456789"' > "$TMP_DIR/cfg.txt"
  run "$REDEYE_ROOT/scripts/secret-scan.sh" "$TMP_DIR/cfg.txt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret-scan exits 0 when no files are passed" {
  run env -i HOME="$HOME" PATH="$PATH" "$REDEYE_ROOT/scripts/secret-scan.sh"
  [ "$status" -eq 0 ]
}
