import os
import time
import json
import base64
import logging
from typing import Dict, Any, Optional

try:
    import mss
    import pyautogui
    import requests
except ImportError:
    logging.warning("mss, pyautogui, or requests not installed. Run: pip install mss pyautogui requests")

class VorcePilot:
    def __init__(self, api_key: str, out_dir: str = "pilot_output", max_steps: int = 10, max_runtime: int = 300, allow_destructive: bool = False):
        self.api_key = api_key
        self.out_dir = out_dir
        self.max_steps = max_steps
        self.max_runtime = max_runtime
        self.allow_destructive = allow_destructive
        self.logger = logging.getLogger("VorcePilot")
        self.logger.setLevel(logging.INFO)

        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

    def capture_screenshot(self, filepath: str) -> str:
        try:
            with mss.mss() as sct:
                sct.shot(output=filepath)
            with open(filepath, "rb") as image_file:
                return base64.b64encode(image_file.read()).decode('utf-8')
        except Exception as e:
            self.logger.error(f"Failed to capture screenshot: {e}")
            return ""

    def validate_action_schema(self, action_json: Dict[str, Any]) -> bool:
        required_keys = ["thought", "action", "status"]
        for key in required_keys:
            if key not in action_json:
                return False

        valid_actions = ["click", "type", "wait", "finish"]
        if action_json["action"] not in valid_actions:
            return False

        if action_json["action"] == "click" and "coordinates" not in action_json:
            return False

        if action_json["action"] == "type" and "text" not in action_json:
            return False

        if action_json["status"] not in ["continue", "passed", "failed", "inconclusive"]:
            return False

        return True

    def execute_action(self, action_json: Dict[str, Any]):
        action = action_json["action"]
        if action == "click":
            coords = action_json["coordinates"]
            if len(coords) == 2:
                try:
                    pyautogui.click(coords[0], coords[1])
                except NameError:
                    pass
        elif action == "type":
            try:
                pyautogui.write(action_json["text"])
            except NameError:
                pass
        elif action == "wait":
            time.sleep(2)

    def ask_gemini(self, goal: str, base64_image: str, history: list) -> Dict[str, Any]:
        prompt = f"""
You are a UI testing agent. Your goal is: {goal}
Analyze the screenshot and decide the next action to achieve the goal.
Respond ONLY with a valid JSON object matching this schema:
{{
  "thought": "Your reasoning about the current screen and what to do next",
  "action": "click|type|wait|finish",
  "coordinates": [x, y], // optional, required for click
  "text": "text to type", // optional, required for type
  "status": "continue|passed|failed|inconclusive" // use passed/failed/inconclusive only when action is finish
}}
"""
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent?key={self.api_key}"
        payload = {
            "contents": [{
                "parts": [
                    {"text": prompt},
                    {"inlineData": {"mimeType": "image/png", "data": base64_image}}
                ]
            }],
            "generationConfig": {"responseMimeType": "application/json"}
        }

        try:
            response = requests.post(url, json=payload)
            response.raise_for_status()
            data = response.json()
            text_response = data['candidates'][0]['content']['parts'][0]['text']
            return json.loads(text_response)
        except Exception as e:
            self.logger.error(f"Gemini API request failed: {e}")
            return {"thought": "API error", "action": "finish", "status": "inconclusive"}

    def run(self, goal: str) -> Dict[str, Any]:
        self.logger.info(f"Starting test for goal: {goal}")
        start_time = time.time()
        step = 0
        history = []
        result_status = "inconclusive"

        while step < self.max_steps:
            elapsed = time.time() - start_time
            if elapsed > self.max_runtime:
                self.logger.warning("Max runtime exceeded.")
                break

            step += 1
            self.logger.info(f"Step {step}...")

            screenshot_path = os.path.join(self.out_dir, f"step_{step}.png")
            base64_img = self.capture_screenshot(screenshot_path)
            if not base64_img:
                break

            decision = self.ask_gemini(goal, base64_img, history)
            self.logger.info(f"Model decision: {json.dumps(decision)}")

            with open(os.path.join(self.out_dir, f"step_{step}_decision.json"), "w") as f:
                json.dump(decision, f, indent=2)

            history.append(decision)

            if not self.validate_action_schema(decision):
                self.logger.error("Invalid action schema from model.")
                result_status = "inconclusive"
                break

            if decision["status"] in ["passed", "failed", "inconclusive"]:
                result_status = decision["status"]
                break

            self.execute_action(decision)
            time.sleep(1) # Wait for UI to update

        summary = {
            "goal": goal,
            "steps_taken": step,
            "duration_seconds": time.time() - start_time,
            "status": result_status,
            "history": history
        }

        with open(os.path.join(self.out_dir, "summary.json"), "w") as f:
            json.dump(summary, f, indent=2)

        return summary
