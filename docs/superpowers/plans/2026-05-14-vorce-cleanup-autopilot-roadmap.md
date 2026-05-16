# Vorce Cleanup And Autopilot Roadmap

Date: 2026-05-14

## Operating Mode

- Treat Paperclip output as historical context, not as the source of truth.
- Freeze new Jules dispatch until the current PR and session backlog is drained.
- Keep the local Autopilot running in monitoring mode only by using a long planning interval.
- Use GitHub PR state, CI checks, local Autopilot state, and dashboard exports as the current control plane.

## Current State

- Open PRs: 11
- Merge conflicts: 9
- Mergeable but blocked:
  - PR #449: CI green and mergeable, but stale `CHANGES_REQUESTED` review remains.
  - PR #482: mergeable, but `Quality Gate (Format & Lint)` and `Validation Success` fail.
- Conflict PRs:
  - Security/stability: #479, #471, #467, #459
  - Performance: #490, #468, #462
  - Feature/cleanup: #473, #455
- Open issues: 30
- Paperclip-synced issues: 24
- Jules sampled state: high stale backlog; use drain-only policy.

## Immediate Priorities

1. Convert PR #449 from stale-review-blocked to merge-ready or explicitly reopen the security review.
2. Triage PR #482 CI failure; merge if the failure is mechanical, park if the dependency bump has broader fallout.
3. Resolve or close security/stability conflict PRs before performance and feature PRs.
4. Replace issue #478's stale PR list with a current operational comment trail.
5. Keep local Autopilot and dashboard alive, but do not let Planning create issues or Jules sessions.

## Autopilot Guardrails

- One Autopilot process only.
- One dashboard sync loop only.
- One Vite dashboard server only.
- Wake trigger: `scripts/codex-cli/autopilot.wakeup`.
- Current safe launch shape:

```powershell
pwsh -NoExit -NoProfile -File scripts\codex-cli\autopilot.ps1 -PlanningIntervalOverride 10080
```

This preserves monitoring and manual wakeups while preventing routine Planning dispatches for roughly one week.

## Gemini UI QA Track

Existing prototype files:

- `C:\Users\Vinyl\Desktop\VJMapper\vorce_automation.py`
- `C:\Users\Vinyl\Desktop\VJMapper\vorce_pilot.py`
- `C:\Users\Vinyl\Desktop\VJMapper\vorce_ui_test.py`

Before production use:

- Replace JSON `eval()` fallback with strict parsing and repair prompts.
- Add max-step and timeout limits per goal.
- Save screenshot, decision JSON, action, and result per step.
- Add explicit pass/fail assertions instead of open-ended `done`.
- Add app lifecycle control for Vorce startup/shutdown.
- Build first smoke flow: launch app, detect main window, open/load project, verify canvas visible.

## Stop Criteria

Escalate to the user only when:

- a PR requires product/security tradeoff acceptance,
- merge conflict resolution would rewrite broad unrelated code,
- CI failure indicates a real dependency/API break,
- an automation wants to create new external sessions or spend quota outside the current limits.
