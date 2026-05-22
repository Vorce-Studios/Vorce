import os
import sys
import json
import time
import argparse
import base64
from datetime import datetime
from pathlib import Path

MISSING_DEPS = []
try:
    import pyautogui
except ImportError:
    MISSING_DEPS.append("pyautogui")
try:
    from PIL import ImageGrab
except ImportError:
    MISSING_DEPS.append("Pillow")
try:
    from google import genai
    from google.genai import types
except ImportError:
    try:
        import google.generativeai as genai
    except ImportError:
        MISSING_DEPS.append("google-genai or google-generativeai")

ARTIFACT_DIR = Path("artifacts/visual-capture/ui-test-runs")

ACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "thought": {"type": "string"},
        "action": {
            "type": "string",
            "enum": ["click", "type", "done", "fail", "inconclusive"]
        },
        "x": {"type": "integer"},
        "y": {"type": "integer"},
        "text": {"type": "string"}
    },
    "required": ["thought", "action"]
}

def log_report(status, message, run_dir, extra_data=None):
    report = {
        "status": status,
        "message": message,
        "timestamp": datetime.now().isoformat(),
    }
    if extra_data:
        report.update(extra_data)

    report_file = run_dir / "run_report.json"
    with open(report_file, "w") as f:
        json.dump(report, f, indent=2)
    print(f"[{status}] {message}")
    print(f"Report saved to {report_file}")

def get_screenshot():
    """Captures the current screen."""
    try:
        return ImageGrab.grab()
    except Exception as e:
        print(f"Screenshot failed: {e}")
        return None

def take_screenshot(run_dir, name="screenshot"):
    if "Pillow" in MISSING_DEPS:
        return None, None
    try:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = run_dir / f"{name}_{timestamp}.png"
        img = get_screenshot()
        if img:
            img.save(filename)
            return str(filename), img
        return None, None
    except Exception as e:
        print(f"Failed to take screenshot: {e}")
        return None, None

def perform_action(action_data, allow_destructive):
    action = action_data.get("action")
    if action == "click":
        x, y = action_data.get("x"), action_data.get("y")
        if x is not None and y is not None:
             print(f"Executing: Click at ({x}, {y})")
             try:
                 pyautogui.click(x=x, y=y)
             except Exception as e:
                 print(f"Click failed: {e}")
        else:
             print("Missing x/y for click.")
    elif action == "type":
        text = action_data.get("text")
        if text:
             if not allow_destructive and any(keyword in text.lower() for keyword in ["delete", "remove", "rm", "format"]):
                 print("Blocked potentially destructive typing action.")
             else:
                 print(f"Executing: Type '{text}'")
                 try:
                     pyautogui.write(text)
                 except Exception as e:
                     print(f"Type failed: {e}")
        else:
             print("Missing text for type.")
    elif action in ["done", "fail", "inconclusive"]:
        print(f"Agent finished with status: {action}")
        return False, action
    else:
        print(f"Unknown action: {action}")
    return True, None

def run_vision_loop(goal, max_steps=5, run_dir=None):
    """Executes a Gemini Vision loop using screenshots and JSON actions."""
    if run_dir is None:
        run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        run_dir = ARTIFACT_DIR / run_id
        run_dir.mkdir(parents=True, exist_ok=True)

    print(f"Starting vision loop for goal: {goal}")

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("GEMINI_API_KEY not set. Cannot run vision loop.")
        return False

    if "google-genai or google-generativeai" in MISSING_DEPS:
        print("Neither google-genai nor google-generativeai package installed.")
        return False

    # Check which version of the API we are using
    use_new_genai = 'google.genai' in sys.modules

    if use_new_genai:
        client = genai.Client(api_key=api_key)
        model_id = "gemini-1.5-flash"
    else:
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel('gemini-1.5-flash')

    system_prompt = f"Goal: {goal}. Respond using this strict JSON schema ONLY: {json.dumps(ACTION_SCHEMA)}"
    history = []
    start_time = time.time()

    for step in range(max_steps):
        print(f"\n--- Step {step+1}/{max_steps} ---")

        path, img = take_screenshot(run_dir, f"step_{step}")
        if not path or not img:
            print("Could not capture screenshot.")
            return False

        print(f"Captured screen: {path}")

        prompt = "Current screen state. What is your next action based on the goal?"
        try:
            if use_new_genai:
                response = client.models.generate_content(
                    model=model_id,
                    contents=[system_prompt, prompt, img]
                )
                raw_text = response.text
            else:
                response = model.generate_content([system_prompt, prompt, img])
                raw_text = response.text
        except Exception as e:
            print(f"Gemini API error: {e}")
            return False

        try:
            # simple extract json from markdown if present
            if "```json" in raw_text:
                json_str = raw_text.split("```json")[1].split("```")[0].strip()
            elif "```" in raw_text:
                json_str = raw_text.split("```")[1].strip()
            else:
                json_str = raw_text.strip()

            action_data = json.loads(json_str)
        except json.JSONDecodeError:
            print(f"Invalid JSON returned from model: {raw_text}")
            return False

        print(f"Agent Thought: {action_data.get('thought')}")

        history.append({
            "step": step,
            "screenshot": path,
            "decision": action_data
        })

        continue_loop, status = perform_action(action_data, allow_destructive=False)

        if not continue_loop:
             log_report("PASS" if status == "done" else ("FAIL" if status == "fail" else "INCONCLUSIVE"),
                       f"Pilot finished: {status}", run_dir, {"history": history})
             return status == "done"

        time.sleep(2) # brief pause after action

    log_report("INCONCLUSIVE", "Max steps reached without completion.", run_dir, {"history": history})
    return False

def main():
    parser = argparse.ArgumentParser(description="Exploratory Gemini Computer Use Test Runner")
    parser.add_argument("--goal", type=str, required=True, help="Validation goal/prompt")
    parser.add_argument("--max-steps", type=int, default=15, help="Maximum number of UI interactions")
    parser.add_argument("--timeout", type=int, default=300, help="Hard timeout in seconds")
    parser.add_argument("--allow-destructive", action="store_true", help="Allow file/project operations")
    args = parser.parse_args()

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = ARTIFACT_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    if MISSING_DEPS:
        log_report("FAIL", f"Missing Python dependencies: {', '.join(MISSING_DEPS)}", run_dir)
        sys.exit(1)

    print(f"Goal: {args.goal}")
    print(f"Max Steps: {args.max_steps}")
    print(f"Artifacts: {run_dir}")

    success = run_vision_loop(args.goal, max_steps=args.max_steps, run_dir=run_dir)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
