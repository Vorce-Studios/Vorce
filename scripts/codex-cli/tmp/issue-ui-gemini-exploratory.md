## Context

The user also wants a second test mode that is not a fixed click path. It should use Gemini Computer Use plus screenshots to validate targeted UI changes or new features interactively, while still producing structured results.

Existing prototype inputs:

- `scripts/gemini-cli/UI-Test_ComputerUse/vorce_pilot.py`
- `scripts/gemini-cli/UI-Test_ComputerUse/vorce_master_test.py`
- `scripts/gemini-cli/UI-Test_ComputerUse/README_VORCE.md`

## Goal

Implement an exploratory Gemini Computer Use test runner for targeted Vorce UI validation.

## Scope

- Add a runner that accepts a goal/prompt, for example:
  - "Verify the settings dialog opens and contains audio/device controls."
  - "Validate the new media browser can be opened and visually shows an empty/loading/content state."
- Use screenshots as the observation source.
- Require Gemini to respond in a strict JSON action schema.
- Add guardrails:
  - max step count,
  - max runtime,
  - allowed actions,
  - no destructive file/project operations unless explicitly enabled,
  - stop on uncertainty instead of guessing.
- Save step screenshots, model decisions, and final summary.
- Return a machine-readable pass/fail/inconclusive result.

## Acceptance Criteria

- A documented command runs one Gemini-guided UI validation goal.
- The runner saves all screenshots and decisions needed for review.
- The runner can finish with `passed`, `failed`, or `inconclusive`.
- The action schema is validated before executing clicks/typing.
- The test can be used by agents for UI-change verification without hardcoding every click.

## Dependency

Depends on the shared UI automation harness issue.
