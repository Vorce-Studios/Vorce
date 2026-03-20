use crate::module::types::connection::ModuleConnection;
use crate::module::types::node_link::{LinkState, NodeLink, NodeLinkType};
use crate::module::types::part::{ModulePart, ModulePartType, PartType};
use crate::module::types::socket::ModuleSocketDirection;
use crate::module::types::source::{BevyShapeType, SourceType};
use crate::module::types::trigger::TriggerType;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use thiserror::Error;

pub type ModuleId = u64;
pub type ModulePartId = u64;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct MapFlowModule {
    pub id: ModuleId,
    pub name: String,
    pub color: [f32; 4],
    pub parts: Vec<ModulePart>,
    pub connections: Vec<ModuleConnection>,
    pub playback_mode: ModulePlaybackMode,
    #[serde(default = "crate::module::config::default_next_part_id")]
    pub next_part_id: ModulePartId,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ConnectionValidationError {
    #[error("source part {0} does not exist")]
    SourcePartNotFound(ModulePartId),
    #[error("target part {0} does not exist")]
    TargetPartNotFound(ModulePartId),
    #[error("source socket {0} does not exist on part {1}")]
    SourceSocketNotFound(usize, ModulePartId),
    #[error("target socket {0} does not exist on part {1}")]
    TargetSocketNotFound(usize, ModulePartId),
    #[error("cannot connect output to output")]
    OutputToOutput,
    #[error("cannot connect input to input")]
    InputToInput,
    #[error("incompatible socket types: {0:?} -> {1:?}")]
    IncompatibleSocketTypes(
        crate::module::types::socket::ModuleSocketType,
        crate::module::types::socket::ModuleSocketType,
    ),
    #[error("target socket already has a connection")]
    TargetSocketInUse,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ModulePlaybackMode {
    TimelineDuration { duration_ms: u64 },
    LoopUntilManualSwitch,
}

impl Default for ModulePlaybackMode {
    fn default() -> Self {
        Self::TimelineDuration { duration_ms: 1000 }
    }
}

// ... the rest of the file
