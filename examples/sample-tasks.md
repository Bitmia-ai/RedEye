# Adding Tasks — Examples

You don't write specs. You write sentences. RedEye expands them into full entries.

## Just say what you want

```
/redeye:tasks dark mode would be cool
/redeye:tasks the login page is broken on Safari
/redeye:tasks add passkeys, keep passwords as fallback
/redeye:tasks we have no regression tests on checkout — fix that
/redeye:tasks critical: secrets leak in error logs
```

Each of these becomes a structured task entry with an inferred type (feature / bug / security / test / ...), a priority, and concrete details — without you lifting a finger.

## What the plugin produces

Input: `/redeye:tasks dark mode would be cool`

Expanded entry added to `.redeye/tasks.md`:

```
### T042: Add dark mode toggle
- **Type:** feature
- **Priority:** P2
- **Status:** pending
- **Details:**
  - Default to system preference (prefers-color-scheme)
  - Persist user override in localStorage
  - Toggle control in the header
  - Apply to all pages in the app
```

The PLAN phase will pick it up, write a full spec, and BUILD will implement it.

## When you DO want to be specific

You can write the full entry yourself if you prefer — the structure is just markdown:

```markdown
### T099: <title>
- **Type:** feature | bug | security | tech-debt | infra | ux | test
- **Priority:** P0 | P1 | P2 | P3
- **Status:** pending
- **Details:**
  - <bullet>
  - <bullet>
```

But for most items, a single sentence is enough.
