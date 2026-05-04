# PR Guidelines Extended

This document extends the core PR Guidelines (DOC-C1) by providing explicit details on ownership, response expectations, and the workflow for achieving merge readiness.

## 1. PR Reviewer Responsibilities

Reviewers are critical to maintaining code quality and ensuring timely delivery.

- **Designated Reviewers:** Each PR should have at least one designated reviewer, typically a team lead or a peer with expertise in the affected area.
- **Review Cadence:**
    - Initial review should commence within **24 business hours** of the PR being marked "ready for review".
    - Subsequent reviews after updates from the PR author should also aim for a **24 business hours** turnaround.
- **Feedback Quality:** Provide clear, constructive, and actionable feedback. Reference specific lines of code or architectural patterns where applicable.
- **Approval:** Approve the PR only when all concerns are addressed, tests pass, and the changes align with project standards.
- **Communication:** If a review is blocked or delayed, communicate proactively with the PR author and other stakeholders.

## 2. PR Author Responsibilities

PR authors are responsible for driving their changes to completion.

- **Responsiveness:** Respond to reviewer comments and feedback within **24 business hours**.
- **Addressing Feedback:** Thoughtfully address all review comments. If a suggestion is not taken, provide a clear rationale.
- **Conflict Resolution:** Actively monitor for and resolve merge conflicts promptly. Currently, automatic branch updates are disabled, so manual intervention is required.
- **Keeping PRs Up-to-Date:** Rebase or merge from the target branch (`main`) regularly, especially for long-lived branches, to minimize conflicts and ensure compatibility.
- **Test Coverage:** Ensure all changes are adequately covered by tests, and all local tests pass before pushing updates.

## 3. Merge Readiness Workflow

A PR is considered merge-ready when it meets the following criteria, which are largely operationalized by the `CICD-DevFlow: Job02 Auto-Merge` workflow:

- **All Required Status Checks Pass:** The following checks must pass with a 'success' conclusion:
    - `Quality Gate (Format & Lint)`
    - `Security Scan`
    - `Build & Test (Linux)`
    - `Build & Test (Windows)`
    - `Build (macOS Beta)`
    - `Rust Autofix`
    - `Validation Success`
- **No Merge Conflicts:** The PR must be mergeable without conflicts. If conflicts arise, the PR author must resolve them manually.
- **Up-to-Date with Target Branch:** The PR branch should be up-to-date with `main`. If it's behind, the PR author is responsible for updating it.
- **Approved by Reviewer:** At least one designated reviewer must approve the PR.
- **No Draft Status:** The PR must not be in "draft" status.

## 4. Handling Stale or Blocked PRs

"Olivia" (the GitHub PR Monitor) actively monitors PRs and will provide automated feedback. In cases where manual intervention is required:

- **Stale PRs:** If a PR remains unaddressed for **3 business days** after feedback or if it falls significantly behind `main` (and automatic updates are disabled), Olivia may flag it. The PR author or designated reviewer should then take action to unblock it or close it if no longer relevant.
- **Blocked PRs:** If a PR is blocked by external factors (e.g., waiting for another team, dependency issues), the blocking issue should be clearly communicated in the PR comments, and the PR should be marked as "blocked" using appropriate labels.
- **Escalation:** If a PR is persistently blocked or stale, Olivia may escalate to designated team leads via Telegram or other channels, prompting human intervention.
