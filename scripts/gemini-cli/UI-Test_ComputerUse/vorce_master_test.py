#!/usr/bin/env python3
import argparse
import sys
import os
import json
from vorce_pilot import VorcePilot

def main():
    parser = argparse.ArgumentParser(description="Vorce Gemini Computer Use UI Validation Runner")
    parser.add_argument("--goal", type=str, required=True, help="The validation goal/prompt for the agent")
    parser.add_argument("--out-dir", type=str, default="pilot_output", help="Directory to save screenshots and decisions")
    parser.add_argument("--max-steps", type=int, default=15, help="Maximum number of steps")
    parser.add_argument("--max-runtime", type=int, default=300, help="Maximum runtime in seconds")
    parser.add_argument("--allow-destructive", action="store_true", help="Allow destructive file operations (currently ignored for safety)")

    args = parser.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print(json.dumps({"error": "GEMINI_API_KEY environment variable not set", "status": "inconclusive"}))
        sys.exit(1)

    pilot = VorcePilot(
        api_key=api_key,
        out_dir=args.out_dir,
        max_steps=args.max_steps,
        max_runtime=args.max_runtime,
        allow_destructive=args.allow_destructive
    )

    result = pilot.run(args.goal)
    print(json.dumps(result, indent=2))

    if result.get("status") == "passed":
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
