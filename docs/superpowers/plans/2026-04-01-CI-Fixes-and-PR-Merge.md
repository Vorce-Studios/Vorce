# CI Fixes and PR Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve CI/CD "hanging" and failure issues, fix duplicate markdown headings, and manually resolve PR conflicts to enable auto-merging.

**Architecture:**
1. Surgical updates to GitHub Workflow YAML files to adjust timeouts and concurrency.
2. Content modification in `JULES_ISSUES.md` to satisfy linting rules.
3. Manual git operations to resolve conflicts in open PRs.

**Tech Stack:** YAML, GitHub Actions, Git, Markdown.

---

### Task 1: Fix JULES_ISSUES.md Duplicate Headings

**Files:**
- Modify: `JULES_ISSUES.md`

- [ ] **Step 1: Identify and rename duplicate headings**
Modify `JULES_ISSUES.md` to append the issue ID to the sub-headings.
Example: `### 📝 Description (#129)`, `### 🛠️ Tasks (#129)`, `### ✅ Acceptance Criteria (#129)`.

- [ ] **Step 2: Run local lint check (if possible) or commit to trigger CI**
Run: `pre-commit run markdownlint-fix --files JULES_ISSUES.md` (assuming pre-commit is installed locally).
Expected: PASS

- [ ] **Step 3: Commit changes**
```bash
git add JULES_ISSUES.md
git commit -m "docs: resolve duplicate headings in JULES_ISSUES.md for markdownlint"
```

### Task 2: Update Windows Validation Timeout

**Files:**
- Modify: `.github/workflows/CICD-DevFlow_Job01_Validation.yml`

- [ ] **Step 1: Increase build-windows timeout**
Change `timeout-minutes: 45` to `timeout-minutes: 90` for the `build-windows` job.

- [ ] **Step 2: Commit changes**
```bash
git add .github/workflows/CICD-DevFlow_Job01_Validation.yml
git commit -m "ci: increase build-windows timeout to 90 minutes"
```

### Task 3: Stabilize Pre-Commit CI Concurrency

**Files:**
- Modify: `.github/workflows/CICD-DevFlow_Job00_PreCommitLite.yml`

- [ ] **Step 1: Disable cancel-in-progress for pre-commit-lite**
Change `cancel-in-progress: true` to `cancel-in-progress: false`.

- [ ] **Step 2: Commit changes**
```bash
git add .github/workflows/CICD-DevFlow_Job00_PreCommitLite.yml
git commit -m "ci: disable cancel-in-progress for pre-commit-lite to prevent blocked merges"
```

### Task 4: Resolve Conflicts in PR #145

**Files:**
- Resolve: `sentinel/fix-unwrap-expect-init-render-14254874753770820148` (PR #145)

- [ ] **Step 1: Checkout the PR branch**
Run: `gh pr checkout 145`

- [ ] **Step 2: Merge main into the branch**
Run: `git merge main`
Expected: Conflict notification.

- [ ] **Step 3: Resolve conflicts manually**
Examine conflicting files, resolve according to `main`'s latest state while preserving the PR's intent.

- [ ] **Step 4: Commit the merge**
Run: `git add . && git commit -m "chore: merge main and resolve conflicts"`

- [ ] **Step 5: Push the branch**
Run: `git push origin sentinel/fix-unwrap-expect-init-render-14254874753770820148`

### Task 5: Final Verification and Auto-Merge Trigger

- [ ] **Step 1: Re-evaluate PR #143 (Hue Node Conflicts)**
Run: `gh pr view 143`
Check if it's mergeable. If not, resolve conflicts as in Task 4.

- [ ] **Step 2: Manually trigger Auto-Merge workflow for problematic PRs**
Run: `gh workflow run "CICD-DevFlow: Job02 Auto-Merge" --field pr_number=143`
Run: `gh workflow run "CICD-DevFlow: Job02 Auto-Merge" --field pr_number=145`

- [ ] **Step 3: Verify successful merges**
Run: `gh pr list` to see if PRs are closing/merging.
