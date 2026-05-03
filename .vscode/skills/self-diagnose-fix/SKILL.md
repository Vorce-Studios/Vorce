---
name: self-diagnose-fix
description: >
  Automated syntax and health check for code changes. Use before finishing a task
  to ensure no syntax errors or regressions were introduced.
---

# Self-Diagnose & Fix Skill

Use this skill before marking a task as done, especially after editing configuration files or core logic.

## Workflow

1. Identify modified files.

```sh
git status --short
```

2. For each modified file, run a syntax check or linter.

### TypeScript / JavaScript
```sh
npx tsc --noEmit # Project-wide check
# OR file-specific (requires tsx or node)
npx tsx --check <file-path>
```

### Rust
```sh
cargo check
```

3. Check for obvious syntax markers in modified files.

```sh
grep -E \"\\\\\\\"|\\\\\\\\n|\\\\\\\\t\" <file-path> # Check for escaped characters in raw output
```

4. Fix any identified issues before submission.

## Quality Bar

- No syntax errors in modified files.
- Linter passes (if available).
- Escaping matches the target file format (e.g., raw strings vs JSON strings).
