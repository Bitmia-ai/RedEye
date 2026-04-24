## Summary

What this PR does in 1-3 sentences.

## Linked issue

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation
- [ ] Refactor / code cleanup
- [ ] Agent prompt change (affects runtime behavior)
- [ ] Other:

## Checklist

- [ ] I opened an issue first (for anything larger than a typo)
- [ ] Shell scripts use `set -euo pipefail`
- [ ] User-supplied values go through `jq --arg`, not string interpolation
- [ ] `.redeye/state.json` writes are atomic (temp file + `mv`)
- [ ] Agent prompt changes respect scope boundaries and untrusted-data warnings
- [ ] Commit message follows conventional format (`feat:`, `fix:`, `docs:`, etc.)

## Testing

How you verified the change works. Manual steps are fine if automated tests aren't available.
