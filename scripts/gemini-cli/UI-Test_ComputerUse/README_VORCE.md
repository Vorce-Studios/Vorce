# Vorce Exploratory UI Validation Runner

This tool uses Gemini's vision capabilities and "Computer Use" style actions to explore and validate the Vorce UI interactively based on natural language goals.

## Prerequisites

- Python 3.8+
- Requirements: pip install mss pyautogui requests
- Environment Variable: GEMINI_API_KEY must be set with your Gemini API key.

## Usage

Run the master test script with a specific validation goal:

```bash
export GEMINI_API_KEY="your_api_key_here"
python scripts/gemini-cli/UI-Test_ComputerUse/vorce_master_test.py \
  --goal "Verify the settings dialog opens and contains audio/device controls." \
  --out-dir "test_results" \
  --max-steps 10
```

## How It Works

1. **Observation**: Takes a screenshot of the desktop.
2. **Analysis**: Sends the screenshot and the goal to the Gemini model, requesting a strict JSON response.
3. **Action**: The model decides on an action (`click`, `type`, `wait`, `finish`) and a status (`continue`, `passed`, `failed`, `inconclusive`).
4. **Execution**: The runner validates the JSON schema and executes the interaction (using PyAutoGUI).
5. **Reporting**: Screenshots, decisions, and a final summary are saved to the output directory. A machine-readable JSON result is printed to stdout.

## Guardrails

- **Max Steps/Runtime**: Prevents infinite loops.
- **Strict Schema**: Model responses are validated against a required action schema before any input is simulated.
- **Safety**: Destructive operations are disabled by default. If the model is uncertain, it should return an `inconclusive` status rather than guessing.
