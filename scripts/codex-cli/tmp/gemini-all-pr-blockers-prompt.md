You are the Vorce PR blocker resolution runner.

Repository: Vorce-Studios/Vorce
Local root: C:\Users\Vinyl\Desktop\VJMapper\VjMapper

The root checkout is dirty and must not be modified. Do all PR work in isolated git worktrees under:
C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli\tmp\pr-worktrees

Goal:
Handle all currently open pull requests that are blocked by merge conflicts or failed required checks, using GitHub CLI and git.

Current high-priority blockers from `gh pr list`:
- PR #543: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #538: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #536: CONFLICTING, pre-commit.ci - pr=PENDING
- PR #532: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #531: CONFLICTING, Quality Gate (Format & Lint)=FAILURE, Validation Success=FAILURE
- PR #526: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #479: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #473: CONFLICTING, pre-commit.ci - pr=PENDING
- PR #468: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #467: CONFLICTING, pre-commit.ci - pr=ERROR
- PR #462: CONFLICTING, pre-commit.ci - pr=SUCCESS but merge conflicts remain
- PR #459: CONFLICTING, pre-commit.ci - pr=PENDING
- PR #540: MERGEABLE, but Quality Gate (Format & Lint)=FAILURE and Validation Success=FAILURE
- PR #506: MERGEABLE, but pre-commit.ci - pr=ERROR
- PR #505: MERGEABLE, but pre-commit.ci - pr=FAILURE

Important:
- There is already a partially started isolated worktree for PR #543 at:
  C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\codex-cli\tmp\pr-worktrees\pr-543-20260516-025812
  Inspect it first. If it is usable, continue from it. If it is not usable, create a new separate worktree and leave the old one untouched.
- For every PR, fetch the current PR head and origin/main before working.
- For conflict PRs, check out the PR head in an isolated worktree, merge origin/main, resolve conflicts conservatively, preserving the PR intent and main changes.
- For check-only PRs, inspect logs/check output enough to identify the actual fix, then make minimal changes in an isolated worktree.
- Do not edit unrelated files.
- Do not use `git reset --hard` or destructive cleanup on the root checkout.
- Do not touch untracked or dirty files in the root checkout.
- After resolving a PR, run the smallest relevant verification you can reasonably run locally.
- Commit changes in the PR worktree with a clear message.
- Push the commit back to the PR head branch only if the PR head repository is Vorce-Studios/Vorce and push is possible.
- If a blocker cannot be safely fixed, do not guess. Leave a concise blocker note in your final report.

Output requirements:
For each PR attempted, report:
- PR number and branch
- Worktree path
- Action taken
- Files changed
- Verification run and result
- Whether pushed
- Remaining blocker if any

Start with PR #543, then #538, #536, #532, #531, #540, #506, #505, then older security/perf conflict PRs in descending practical priority.
