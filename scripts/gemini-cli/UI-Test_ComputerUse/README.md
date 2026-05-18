# Vorce UI Automation Harness for Computer Use Tests

This directory contains the standard harness for deterministic UI checks and exploratory Gemini Computer Use tests for Vorce.

## Usage

### Prerequisites

- Windows environment
- The `GEMINI_API_KEY` environment variable must be set.
- Python dependencies installed:

  ```bash
  pip install -r requirements.txt
  ```

### Running

To verify your environment without altering app data:

```bash
python scripts/gemini-cli/UI-Test_ComputerUse/harness.py --env-check
```

To run the harness:

```bash
python scripts/gemini-cli/UI-Test_ComputerUse/harness.py
```

You can configure the timeout or executable path:

```bash
python scripts/gemini-cli/UI-Test_ComputerUse/harness.py --timeout 120 --vorce-exe target/debug/vorce.exe
```

### Artifacts

All run artifacts (logs, JSON reports, screenshots) are stored in the ignored folder `artifacts/visual-capture/ui-test-runs/`. Check the `run_report.json` inside the respective run timestamp folder for the pass/fail status.
