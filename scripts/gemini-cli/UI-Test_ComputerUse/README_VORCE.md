# Vorce UI Test Computer Use

This directory contains test runners for validating the Vorce UI.

## Runners

### Deterministic Test (`vorce_master_test.py`)

Runs a deterministic, fixed click path to smoke test the UI basic layout.

### Exploratory Test (`vorce_pilot.py`)

An exploratory UI validation runner powered by Gemini Computer Use. It uses screenshots to interpret the UI state and drives the mouse/keyboard via a strict JSON action schema to fulfill a user-defined goal.

#### Features

- **Goal-Oriented:** Accepts prompts like "Verify the settings dialog opens and contains audio/device controls."
- **Observation:** Relies purely on screenshots (`Pillow`, `pyautogui`).
- **Structured:** Requires strict JSON format for model actions (`click`, `type`, `done`, `fail`, `inconclusive`).
- **Guardrails:**
  - Max step limits.
  - Runtime limits.
  - Blocks potentially destructive typing actions unless explicitly allowed.
  - Fails safely on uncertainty.
- **Traceability:** Saves step screenshots, decisions, and summaries to `artifacts/visual-capture/ui-test-runs/`.

#### Usage

```bash
python vorce_pilot.py --goal "Validate the new media browser can be opened and visually shows an empty state." --max-steps 10
```
