# Spec: 2026-04-01-CI-Fixes-and-PR-Merge

## 📝 Problem
The current CI/CD configuration for pull requests has several issues:
1. `markdownlint-fix` fails on `JULES_ISSUES.md` due to duplicate headings (Rule MD024).
2. The `build-windows` step in the validation workflow hangs and exceeds the 45-minute timeout.
3. `Rust Autofix` (Job00 Pre-Commit Lite) is often cancelled due to concurrency settings (`cancel-in-progress: true`), blocking the `Auto-Merge` job which requires it.
4. Several PRs (e.g., #145) have merge conflicts that prevent automated merging.

## 🚀 Proposed Approach

### 1. Fix JULES_ISSUES.md Linting
Modify `JULES_ISSUES.md` to make sub-headings unique by appending the issue ID (e.g., `### 📝 Description (#129)`). This ensures the `markdownlint-fix` hook passes.

### 2. Increase Windows Build Reliability
Modify `.github/workflows/CICD-DevFlow_Job01_Validation.yml` to increase the `timeout-minutes` for `build-windows` to 90 minutes.

### 3. Stabilize Pre-Commit CI Checks
Modify `.github/workflows/CICD-DevFlow_Job00_PreCommitLite.yml` to set `cancel-in-progress: false` for the concurrency group. This prevents the "hanging" state where `Auto-Merge` waits for a cancelled mandatory check.

### 4. Resolve PR Conflicts
- Manually merge `main` into the head branches of conflicting PRs (starting with #145).
- Push the resolved branches to trigger final validation.
- Verify mergeability for all other PRs and perform manual merges if needed to ensure "endgültig per Auto merge" can succeed.

## ✅ Acceptance Criteria
- [ ] `JULES_ISSUES.md` passes `markdownlint-fix`.
- [ ] Windows build completes within the new timeout.
- [ ] `Auto-Merge` successfully merges PRs once all 6 required checks pass.
- [ ] PR #145 is mergeable and conflict-free.
