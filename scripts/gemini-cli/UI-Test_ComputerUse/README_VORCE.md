# Vorce UI Automation Harness

This folder contains the Windows-local harness used by Codex, Jules, and Gemini workflows to verify Vorce UI readiness without depending on random desktop state.

## Quick Start

Run the no-op environment check from the repository root:

```powershell
python scripts\gemini-cli\UI-Test_ComputerUse\vorce_ui_harness.py --mode env-check
```

Run a launch/window/screenshot check after building Vorce:

```powershell
cargo build -p vorce --release
python scripts\gemini-cli\UI-Test_ComputerUse\vorce_ui_harness.py --mode launch-check --require-screenshot
```

Use a custom executable path:

```powershell
python scripts\gemini-cli\UI-Test_ComputerUse\vorce_ui_harness.py --mode launch-check --vorce-exe target\debug\vorce.exe
```

## Artifacts

Every run writes a timestamped folder under:

```text
artifacts/visual-capture/ui-test-runs/
```

The folder includes `run_report.json` and, for launch checks, `vorce_process.log`, `window_titles.json`, and `initial_window.png` when screenshot capture succeeds.

## Modes

- `env-check`: validates Python, repository root, Vorce executable path, optional Pillow screenshot support, optional `pyautogui`, and optional Gemini API key. It does not launch Vorce and does not modify app data.
- `launch-check`: starts Vorce, waits for a visible window from the launched process containing `Vorce`, captures process logs, samples visible window titles/PIDs, optionally captures a screenshot, and terminates the launched process.

## Prerequisites

- Python 3.10 or newer.
- `Pillow` for screenshot capture.
- `pyautogui` for future deterministic mouse/keyboard flows.
- `GEMINI_API_KEY` or `GOOGLE_API_KEY` only when a Gemini-guided runner explicitly requires it.

Missing prerequisites are reported in `run_report.json` with `pass`, `warn`, or `fail` checks. Use `--require-screenshot` or `--require-gemini-key` when a workflow must fail hard on those prerequisites.

By default the launch check only accepts a window owned by the launched `vorce.exe` process. Use `--allow-any-process-window` only for diagnostics, because it can match unrelated windows.

## Agent Contract

Codex/Jules/Gemini should treat `env-check` as the baseline no-op gate for issue #547. Deterministic smoke flows belong to #549 and exploratory Gemini Computer Use flows belong to #548; both should reuse this harness output folder and report schema.

## Gemini Runner Verification

To verify the Gemini Runner with a dummy scenario manifest:

```powershell
echo "{}" > dummy_manifest.json
python scripts\gemini-cli\UI-Test_ComputerUse\gemini_runner.py --scenario-manifest dummy_manifest.json --step-timeout 45 --retry-policy retry-once
```
