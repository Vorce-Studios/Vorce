---
name: github-operations
description: >
  Native control of GitHub Pull Requests, Issues, and Labels. Use for triage,
  reviewing contributions, or preparing releases.
---

# GitHub Operations Skill

Use this skill to manage the project lifecycle on GitHub.

## Preconditions

- GitHub CLI (`gh`) installed and authenticated.

## Workflow

1. List and triage issues.

```sh
gh issue list --limit 10
gh issue view <issue-number>
```

2. Manage labels.

```sh
gh issue edit <issue-number> --add-label \"bug\", \"priority-high\"
```

3. Review Pull Requests.

```sh
gh pr list
gh pr checkout <pr-number>
gh pr diff
```

4. Automate PR merging.

```sh
gh pr merge <pr-number> --auto --merge
```

## Quality Bar

- Issues are correctly labeled.
- PRs are reviewed before merging.
- Descriptions are updated with references to Paperclip task IDs.
