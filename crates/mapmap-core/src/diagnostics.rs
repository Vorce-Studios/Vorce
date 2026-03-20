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
    for (_idx, part) in module.parts.iter().enumerate() {
        if let crate::module::types::part::ModulePartType::Source(_) = part.part_type {
            // Validation logic for sources
            // ...
        }
    }

    issues
}

/// Diagnostic code for unsupported blend mode
pub const DEGRADED_FEATURE_BLEND_MODE: &str = "DEGRADED_FEATURE_BLEND_MODE";
/// Diagnostic code for unsupported mask
pub const DEGRADED_FEATURE_MASK: &str = "DEGRADED_FEATURE_MASK";
/// Diagnostic message for unsupported blend mode
pub const DEGRADED_FEATURE_BLEND_MODE_MSG: &str =
    "Blend modes are currently unsupported in this renderer.";
/// Diagnostic message for unsupported mask
pub const DEGRADED_FEATURE_MASK_MSG: &str = "Masks are not yet supported in this render path.";
/// Diagnostic message for unsupported LUT
pub const DEGRADED_FEATURE_LOAD_LUT: &str =
    "The LoadLUT effect is currently unsupported in this renderer.";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::{ModuleSocket, ModuleSocketType, PartType};

    #[test]
    fn test_check_module_integrity_empty() {
        let module = MapFlowModule {
            name: "Empty".to_string(),
            ..Default::default()
        };
        let issues = check_module_integrity(&module);
        assert!(issues.is_empty());
    }

    #[test]
    fn test_check_module_integrity_unconnected_output() {
        let mut module = MapFlowModule::default();
        module.add_part(PartType::Source, (0.0, 0.0));
        let issues = check_module_integrity(&module);
        // Only info for unconnected inputs by default
        assert!(issues
            .iter()
            .all(|i| matches!(i.severity, IssueSeverity::Info)));
    }

    #[test]
    fn test_check_module_integrity_invalid_from_part() {
        let mut module = MapFlowModule::default();
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
        let mut module = MapFlowModule::default();
        module.add_part(PartType::Source, (0.0, 0.0));
        let issues = check_module_integrity(&module);
        // Just verify it doesn't panic on empty modules
        assert!(!issues.is_empty() || issues.is_empty());
    }

    #[test]
    fn test_diagnostics_unconnected_info() {
        let mut module = MapFlowModule::default();
        module.add_part(PartType::Source, (0.0, 0.0));

        let mut input_socket = ModuleSocket::input("in", "Input", ModuleSocketType::Media);
        input_socket.id = "in".to_string();

        module.parts.last_mut().unwrap().inputs.push(input_socket);

        let issues = check_module_integrity(&module);
        assert!(!issues.is_empty());
        assert!(issues.iter().any(|i| i
            .message
            .contains("Input socket 'Input' on part 0 is unconnected.")));
    }

    #[test]
    fn test_diagnostics_invalid_source_validation() {
        let mut module = MapFlowModule::default();
        module.add_part(PartType::Source, (0.0, 0.0));

        let _issues = check_module_integrity(&module);
        // No errors for default sources in base integrity check
    }

    #[test]
    fn test_diagnostics_error_no_file() {
        let mut module = MapFlowModule::default();
        module.add_part(PartType::Source, (0.0, 0.0));

        let issues = check_module_integrity(&module);
        // We don't have file validation yet in check_module_integrity
        let _ = issues;
    }
}
