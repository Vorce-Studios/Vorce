import argparse
import sys
from pathlib import Path

# Add current dir to sys.path for importing harness
sys.path.insert(0, str(Path(__file__).resolve().parent))
from vorce_ui_harness import make_run_dir, RunReport, default_exe_path

def parse_args():
    parser = argparse.ArgumentParser(description="Vorce Gemini Computer Use Runner")
    parser.add_argument("--scenario-manifest", type=str, required=True, help="Path to scenario manifest JSON file")
    parser.add_argument("--step-timeout", type=int, default=30, help="Per-step timeout in seconds")
    parser.add_argument("--retry-policy", type=str, choices=["none", "retry-once", "retry-until-timeout"], default="none", help="Explicit retry policy for scenario steps")
    parser.add_argument("--vorce-exe", default=str(default_exe_path()), help="Path to vorce.exe.")

    return parser.parse_args()

def main():
    args = parse_args()

    run_dir = make_run_dir("gemini-run")
    report = RunReport("gemini-run", run_dir, args)

    manifest_path = Path(args.scenario_manifest)
    if not manifest_path.exists():
        report.check("manifest", "fail", f"Scenario manifest not found: {args.scenario_manifest}")
        return report.finish("failed", "Runner initialization failed due to missing manifest")

    report.check("manifest", "pass", f"Accepted scenario manifest: {args.scenario_manifest}")
    report.check("timeout", "pass", f"Per-step timeout configured to: {args.step_timeout}s")
    report.check("retry", "pass", f"Retry policy configured to: {args.retry_policy}")

    return report.finish("passed", "Gemini runner scaffold completed successfully")

if __name__ == "__main__":
    sys.exit(main())
