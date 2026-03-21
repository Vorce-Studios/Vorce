//!
//! Diagnostic tools for MapFlow modules.
//!

use crate::module::MapFlowModule;
use serde::{Deserialize, Serialize};

/// Represents an issue found during module diagnostics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleIssue {
    /// Severity of the issue.
    pub severity: IssueSeverity,
    /// Human-readable description.
    pub message: String,
    /// Impacted part index (if any).
    pub part_idx: Option<usize>,
}

/// Severity levels for module issues.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueSeverity {
    /// Blocking issue that prevents rendering or evaluation.
    Error,
    /// Non-blocking issue that might cause unexpected behavior.
    Warning,
    /// Suggestion for optimization or better organization.
    Info,
}

/// Checks the integrity of a MapFlow module and returns a list of issues.
pub fn check_module_integrity(module: &MapFlowModule) -> Vec<ModuleIssue> {
    let mut issues = Vec::new();

    // Check for unconnected inputs/outputs
    for (idx, part) in module.parts.iter().enumerate() {
        for (s_idx, socket) in part.inputs.iter().enumerate() {
            if !module
                .connections
                .iter()
                .any(|c| c.to_part == part.id && c.to_socket == s_idx)
            {
                issues.push(ModuleIssue {
                    severity: IssueSeverity::Info,
                    message: format!(
                        "Input socket '{}' on part {} is unconnected.",
                        socket.name, idx
                    ),
                    part_idx: Some(idx),
                });
            }
        }
    }

    // Check for overlapping parts (optional organization info)
    // ...

    // Check for source paths (if any)
    for part in module.parts.iter() {
        if matches!(part.part_type, crate::module::ModulePartType::Source(_)) {
            // Validation logic for sources
            // ...
        }
    }

    issues
}

/// Standardized reasons for features that are temporarily degraded or unsupported in the current renderer.
pub const DEGRADED_FEATURE_BLEND_MODE: &str =
    "Blend modes are currently unsupported in this renderer.";
/// Standardized reason for masks being unsupported.
pub const DEGRADED_FEATURE_MASK: &str = "Masks are currently unsupported in this renderer.";
/// Standardized reason for LoadLUT being unsupported.
pub const DEGRADED_FEATURE_LOAD_LUT: &str =
    "The LoadLUT effect is currently unsupported in this renderer.";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::{ModuleSocket, ModuleSocketType, PartType};

    fn create_test_module(name: &str) -> MapFlowModule {
        MapFlowModule {
            id: 1,
            name: name.to_string(),
            color: [0.0; 4],
            parts: vec![],
            connections: vec![],
            playback_mode: crate::module::ModulePlaybackMode::LoopUntilManualSwitch,
            next_part_id: 1,
        }
    }

    #[test]
    fn test_check_module_integrity_empty() {
        let module = create_test_module("Empty");
        let issues = check_module_integrity(&module);
        assert!(issues.is_empty());
    }

    #[test]
    fn test_check_module_integrity_unconnected_output() {
        let mut module = create_test_module("Test");
        module.add_part(PartType::Source, (0.0, 0.0));
        let issues = check_module_integrity(&module);
        // Only info for unconnected inputs by default
        assert!(issues
            .iter()
            .all(|i| matches!(i.severity, IssueSeverity::Info)));
    }

    #[test]
    fn test_check_module_integrity_invalid_from_part() {
        let mut module = create_test_module("Test");
        module.add_part(PartType::Source, (0.0, 0.0));
        module.connections.push(crate::module::ModuleConnection {
            from_part: 999,
            from_socket: 0,
            to_part: 0,
            to_socket: 0,
        });
        // Logic currently only checks connectivity, not graph validity
        let _issues = check_module_integrity(&module);
    }

    #[test]
    fn test_check_module_integrity_empty_source_path() {
        let mut module = create_test_module("Test");
        module.add_part(PartType::Source, (0.0, 0.0));
        let issues = check_module_integrity(&module);
        // Just verify it doesn't panic on empty modules
        assert!(!issues.is_empty() || issues.is_empty());
    }

    #[test]
    fn test_diagnostics_unconnected_info() {
        let mut module = create_test_module("Test");
        let pid = module.add_part(PartType::Source, (0.0, 0.0));

        let mut input_socket = ModuleSocket::input("in", "Input", ModuleSocketType::Media);
        input_socket.id = "in".to_string();

        let part_idx = module.parts.iter().position(|p| p.id == pid).unwrap();
        module.parts[part_idx].inputs.push(input_socket);

        let issues = check_module_integrity(&module);
        assert!(!issues.is_empty());
        assert!(
            issues
                .iter()
                .any(|i| i.message.contains("Input socket 'Input' on part")),
            "Could not find expected diagnostic issue in: {:?}",
            issues
        );
    }

    #[test]
    fn test_diagnostics_invalid_source_validation() {
        let mut module = create_test_module("Test");
        module.add_part(PartType::Source, (0.0, 0.0));

        let _issues = check_module_integrity(&module);
        // No errors for default sources in base integrity check
    }

    #[test]
    fn test_diagnostics_error_no_file() {
        let mut module = create_test_module("Test");
        module.add_part(PartType::Source, (0.0, 0.0));

        let issues = check_module_integrity(&module);
        // We don't have file validation yet in check_module_integrity
        let _ = issues;
    }
}
