//! Diagnostics - Module Integrity Checking
//!
//! This module provides tools to validate module connections, detect broken links,
//! and report issues (errors/warnings) to the user.
//!
//! # Features
//!
//! - **ModuleIssue**: Data structure for reporting problems.
//! - **check_module_integrity**: Scans a module for connectivity issues.
//! - **check_all_modules**: Scans all modules in a manager.

use crate::module::{MapFlowModule, ModuleConnection, ModuleManager, ModulePartType, OutputType};
use serde::{Deserialize, Serialize};

/// Severity levels for module issues.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueSeverity {
    /// Errors must be fixed for the module to function (e.g. broken source links).
    Error,
    /// Warnings indicate potential issues but don't prevent execution (e.g. unlinked nodes).
    Warning,
    /// Informational notes.
    Info,
}

/// A single issue found during module diagnostics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModuleIssue {
    /// Unique ID of the affected part (if any).
    pub part_id: Option<u64>,
    /// Human-readable description of the issue.
    pub message: String,
    /// Severity level.
    pub severity: IssueSeverity,
}

/// Checks a single module for structural and logical errors.
pub fn check_module_integrity(module: &MapFlowModule) -> Vec<ModuleIssue> {
    let mut issues = Vec::new();

    // 1. Check connections
    for conn in &module.connections {
        if !module.parts.iter().any(|p| p.id == conn.from_part) {
            issues.push(ModuleIssue {
                part_id: Some(conn.from_part),
                message: format!("Connection refers to invalid FROM Part ID: {}", conn.from_part),
                severity: IssueSeverity::Error,
            });
        }
        if !module.parts.iter().any(|p| p.id == conn.to_part) {
            issues.push(ModuleIssue {
                part_id: Some(conn.to_part),
                message: format!("Connection refers to invalid TO Part ID: {}", conn.to_part),
                severity: IssueSeverity::Error,
            });
        }
    }

    // 2. Part-specific checks
    for part in &module.parts {
        match &part.part_type {
            ModulePartType::Source(source) => {
                if source.file_path.is_none() {
                    issues.push(ModuleIssue {
                        part_id: Some(part.id),
                        message: format!("Source '{}' has no file selected.", part.id),
                        severity: IssueSeverity::Warning,
                    });
                }
            }
            ModulePartType::Output(OutputType::Projector { id, .. }) => {
                // Check if this output is actually driven by a layer
                let has_input = module
                    .connections
                    .iter()
                    .any(|c| c.to_part == part.id && c.to_socket == 0);
                if !has_input {
                    issues.push(ModuleIssue {
                        part_id: Some(part.id),
                        message: format!("Output window {} has no input connected.", id),
                        severity: IssueSeverity::Warning,
                    });
                }
            }
            _ => {}
        }
    }

    issues
}

/// Scans all modules in the manager.
pub fn check_all_modules(manager: &ModuleManager) -> Vec<(u64, Vec<ModuleIssue>)> {
    manager
        .modules()
        .iter()
        .map(|m| (m.id, check_module_integrity(m)))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::module::{ModulePartId, ModulePlaybackMode, PartType};

    #[test]
    fn test_integrity_invalid_connection() {
        let mut module = MapFlowModule {
            id: 1,
            name: "Test".to_string(),
            color: [1.0; 4],
            parts: vec![],
            connections: vec![],
            playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
            next_part_id: 1,
        };

<<<<<<< HEAD
        // Force a connection with an invalid from_part and to_part
        // `add_connection` performs validation and would silently ignore it,
        // so we manually push the invalid connection to test the diagnostic function.
=======
        // Add a connection with an invalid from_part and to_part
<<<<<<< HEAD
<<<<<<< HEAD
        // we bypass add_connection/connect_parts which would reject it
>>>>>>> fix-1245-trigger-nodes-migration-172233438171995501
=======
>>>>>>> origin/main
=======
        // `add_connection` performs validation and would silently ignore it,
        // so we manually push the invalid connection to test the diagnostic function.
=======
        // we bypass add_connection/connect_parts which would reject it
>>>>>>> ae090afc
>>>>>>> MF-SubI_Effect-Mask-Mesh-Nodes-Migration-390479776812751095
        module.connections.push(crate::module::ModuleConnection {
            from_part: 999,
            from_socket: 0,
            to_part: 1000,
            to_socket: 0,
        });

        let issues = check_module_integrity(&module);
        assert_eq!(issues.len(), 2); // missing from and to parts
        assert_eq!(issues[0].severity, IssueSeverity::Error);
        assert!(issues[0].message.contains("invalid FROM Part ID"));
    }

    #[test]
    fn test_integrity_missing_source_file() {
        let mut module = MapFlowModule {
            id: 1,
            name: "Test".to_string(),
            color: [1.0; 4],
            parts: vec![],
            connections: vec![],
            playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
            next_part_id: 1,
        };

        module.add_part(PartType::Source, (0.0, 0.0));

        let issues = check_module_integrity(&module);
        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].severity, IssueSeverity::Warning);
        assert!(issues[0].message.contains("no file selected"));
    }
}
