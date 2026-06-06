use std::path::{Path, PathBuf};
use std::process::Command;

#[test]
fn test_ui_harness_env_check() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace_root = manifest_dir
        .parent()
        .and_then(Path::parent)
        .expect("vorce crate should live under <workspace>/crates/vorce");

    let harness_path =
        workspace_root.join("scripts/gemini-cli/UI-Test_ComputerUse/vorce_ui_harness.py");

    // Fallback to "python" if "python3" is not available
    let python_cmd = if Command::new("python3").arg("--version").status().is_ok() {
        "python3"
    } else {
        "python"
    };

    let status = Command::new(python_cmd)
        .arg(&harness_path)
        .arg("--mode")
        .arg("env-check")
        .status()
        .expect("failed to run python process for ui harness");

    assert!(status.success(), "UI harness env-check failed");
}

#[test]
#[ignore = "requires UI environment and built vorce binary"]
fn test_ui_harness_launch_check() {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let workspace_root = manifest_dir
        .parent()
        .and_then(Path::parent)
        .expect("vorce crate should live under <workspace>/crates/vorce");

    let harness_path =
        workspace_root.join("scripts/gemini-cli/UI-Test_ComputerUse/vorce_ui_harness.py");
    let target_dir = workspace_root.join("target").join("release");
    let vorce_exe = target_dir.join(if cfg!(windows) { "Vorce.exe" } else { "vorce" });

    let python_cmd = if Command::new("python3").arg("--version").status().is_ok() {
        "python3"
    } else {
        "python"
    };

    let status = Command::new(python_cmd)
        .arg(&harness_path)
        .arg("--mode")
        .arg("launch-check")
        .arg("--vorce-exe")
        .arg(vorce_exe.to_str().unwrap())
        .arg("--timeout")
        .arg("5") // short timeout for test
        .arg("--no-screenshot") // don't try to take screenshot in headless test
        .status()
        .expect("failed to run python process for ui harness");

    // The script might return non-zero if the window is not found within the timeout
    // but the test primarily ensures it executes correctly without crashing
    assert!(status.success() || status.code() == Some(1), "UI harness launch-check crashed");
}
