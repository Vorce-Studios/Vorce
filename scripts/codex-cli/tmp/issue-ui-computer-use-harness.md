## Context

Existing prototype scripts live in `scripts/gemini-cli/UI-Test_ComputerUse`:

- `vorce_automation.py`: pyautogui-based macro recording/playback and normalized click helpers.
- `vorce_pilot.py`: Gemini Vision loop using screenshots and JSON actions.
- `vorce_master_test.py`: Vorce-specific launch plus multi-step UI goals.
- `wait_for_vorce.py`: build/start watcher for the Vorce app.
- `test_vorce.py` / `vorce_ui_test.py`: basic environment and prototype UI checks.

The prototypes prove the direction, but they are not yet a reliable test harness. Before adding real UI test scenarios, the runner needs predictable startup, artifact capture, timeouts, and a safe failure mode.

## Goal

Create a maintainable Vorce UI automation harness for Gemini Computer Use and deterministic mouse/keyboard checks.

## Scope

- Add a documented test entrypoint for Windows local runs.
- Standardize app startup/wait logic for Vorce.
- Add structured run artifacts:
  - screenshots on failure and optional step screenshots,
  - JSON run report,
  - captured stdout/stderr or launch log,
  - final pass/fail status.
- Add hard timeouts and clear abort behavior.
- Keep root checkout assumptions explicit; tests must not depend on random local window state.
- Reuse the existing prototype code where useful, but reorganize only as much as needed for a clean runner.

## Acceptance Criteria

- A single command can start a Vorce UI test harness locally on Windows.
- Missing prerequisites are reported clearly: API key, Python dependencies, Vorce launch failure, no window found, screenshot failure.
- The harness writes artifacts under a predictable ignored output folder.
- The harness can run a no-op/environment check without modifying app data.
- README instructions explain how Jules/Gemini/Codex should invoke the harness.

## Notes

This issue is the foundation for deterministic smoke tests and exploratory Gemini Computer Use tests.
