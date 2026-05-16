## Context

The user wants one fast, stable UI test that verifies basic Vorce UI functionality with a fixed path using known mouse movement/click behavior. This should be the baseline guardrail for obvious UI breakage.

Existing prototype inputs:

- `scripts/gemini-cli/UI-Test_ComputerUse/vorce_automation.py`
- `scripts/gemini-cli/UI-Test_ComputerUse/wait_for_vorce.py`
- `scripts/gemini-cli/UI-Test_ComputerUse/vorce_master_test.py`

## Goal

Implement a deterministic Vorce UI smoke test that runs quickly and exercises core UI flows without relying on open-ended AI decisions.

## Suggested Flow

Keep the first version small and reliable:

1. Launch Vorce and wait until the main window is visible.
2. Verify screenshot capture and main window bounds.
3. Execute a fixed set of normalized mouse moves/clicks for core UI controls, for example:
   - open/close settings or equivalent menu/dialog,
   - select a stable panel/tool area,
   - trigger one basic create/add action only if it is safe and reversible,
   - close or reset any transient dialog/state.
4. Capture before/after screenshots and a JSON result.
5. Fail with a useful artifact bundle if an expected UI state cannot be reached.

## Constraints

- Prefer deterministic actions over Gemini decisions.
- Keep the test short enough for frequent local validation.
- Avoid destructive project/file changes.
- Use normalized coordinates or window-relative coordinates so the flow survives common display resolutions.
- Include a visible safety escape and timeout.

## Acceptance Criteria

- A documented command runs the smoke test locally.
- The test produces pass/fail plus screenshots/logs.
- The test does not require manual input after start.
- Failures are actionable enough for a coding agent to inspect.
- The test can be called by future CI/manual QA orchestration, even if it remains Windows-local initially.

## Dependency

Depends on the shared UI automation harness issue.
