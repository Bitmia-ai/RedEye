#!/usr/bin/env bash
set -euo pipefail

# secret-scan.sh — Pre-commit hook that scans staged files for secret patterns.
#
# When installed as .git/hooks/pre-commit, scans all staged files.
# Can also be invoked directly with file paths for testing:
#   ./secret-scan.sh path/to/file1 path/to/file2

PATTERNS=(
  'sk_live_[a-zA-Z0-9]+'
  'sk_test_[a-zA-Z0-9]+'
  'rk_live_[a-zA-Z0-9]+'
  'rk_test_[a-zA-Z0-9]+'
  'AKIA[A-Z0-9]{16}'
  'ghp_[a-zA-Z0-9]{36}'
  'gho_[a-zA-Z0-9]+'
  'github_pat_[a-zA-Z0-9_]+'
  'glpat-[a-zA-Z0-9_-]{20,}'
  'xox[bpsare]-[a-zA-Z0-9-]+'
  'AIza[A-Za-z0-9_-]{35}'
  'hf_[a-zA-Z0-9]{30,}'
  'npm_[a-zA-Z0-9]{30,}'
  '-----BEGIN.*PRIVATE KEY-----'
  'sk-ant-[a-zA-Z0-9-]+'
  'sk-proj-[a-zA-Z0-9_-]{20,}'
  'sk-[a-zA-Z0-9]{20,}'
  'password\s*=\s*['"'"'"][^'"'"'"]+['"'"'"]'
  'secret\s*=\s*['"'"'"][^'"'"'"]+['"'"'"]'
  'token\s*=\s*['"'"'"][^'"'"'"]+['"'"'"]'
)

FOUND=0

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  while IFS= read -r file; do
    [ -n "$file" ] && FILES+=("$file")
  done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

for file in "${FILES[@]}"; do
  [ -f "$file" ] || continue

  # Only scan text files.
  mime_type="$(file -b --mime "$file" 2>/dev/null || echo "unknown")"
  case "$mime_type" in
    text/*|application/json*|application/xml*|application/javascript*) ;;
    *) continue ;;
  esac

  # Skip lockfiles (integrity hashes), CLAUDE.md (may document test keys),
  # SECURITY.md (long GitHub advisory URLs trigger entropy false positives),
  # the scanner itself (its pattern definitions self-match), the scanner's
  # bats tests (fixtures must contain fake credentials to exercise the rules),
  # and `.github/` config (issue templates, workflows — full of GitHub URLs
  # that look high-entropy but never contain secrets).
  case "$file" in
    *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*Gemfile.lock) continue ;;
    CLAUDE.md|SECURITY.md|README.md|CHANGELOG.md|CONTRIBUTING.md) continue ;;
    *scripts/secret-scan.sh|*tests/secret-scan.bats) continue ;;
    .github/*.yml|.github/*.yaml) continue ;;
  esac

  for pattern in "${PATTERNS[@]}"; do
    # `--` separates options from pattern (some patterns start with `-----`).
    if grep -nEq -e "$pattern" -- "$file" 2>/dev/null; then
      echo "BLOCKED: Potential secret found in $file matching pattern: $pattern"
      grep -nE -e "$pattern" -- "$file" 2>/dev/null | head -3
      echo ""
      FOUND=1
    fi
  done

  # Skip entropy check on test files/fixtures (mock data triggers false positives).
  if [[ "$file" == *.test.* || "$file" == *.spec.* || "$file" == */e2e/fixtures/* ]]; then
    continue
  fi

  # High-entropy base64-like strings: 3+ character classes mixed in 40+ chars.
  if grep -nEq '[A-Za-z0-9+/=_-]{40,}' "$file" 2>/dev/null; then
    while IFS= read -r line; do
      line_num="${line%%:*}"
      line_content="${line#*:}"
      match="$(echo "$line_content" | grep -oE '[A-Za-z0-9+/=_-]{40,}' | head -1)"
      [ -z "$match" ] && continue
      classes=0
      [[ "$match" =~ [a-z] ]] && classes=$((classes + 1))
      [[ "$match" =~ [A-Z] ]] && classes=$((classes + 1))
      [[ "$match" =~ [0-9] ]] && classes=$((classes + 1))
      [[ "$match" =~ [+/=_-] ]] && classes=$((classes + 1))
      if [ "$classes" -ge 3 ]; then
        echo "BLOCKED: High-entropy string (possible secret) in $file:$line_num"
        echo "  ${line_content:0:100}..."
        echo ""
        FOUND=1
        # No `break` — keep scanning so a real secret on a later line in
        # the same file still gets reported (earlier code stopped after
        # the first hit, so a base64 image followed by an actual key on a
        # subsequent line would silently pass).
      fi
    done < <(grep -nE '[A-Za-z0-9+/=_-]{40,}' "$file" 2>/dev/null || true)
  fi
done

if [ "$FOUND" -eq 1 ]; then
  echo "========================================="
  echo "Commit blocked: potential secrets detected."
  echo "Remove secrets or add files to .gitignore."
  echo "========================================="
  exit 1
fi

exit 0
