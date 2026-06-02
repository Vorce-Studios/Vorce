use crate::module::ModuleId;
use serde::{Deserialize, Serialize};

/// Show orchestration mode for module arrangement.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum ShowMode {
    /// Fully automatic module switching by timeline time.
    #[default]
    FullyAutomated,
    /// Timeline advances automatically, module switch is confirmed manually.
    SemiAutomated,
    /// Module switching is manual only (timeline acts as arrangement board).
    Manual,
    /// Hybrid logic combining time and triggers.
    Hybrid,
    /// Playback stops at markers, waiting for explicit trigger to continue.
    Trackline,
}

impl ShowMode {
    /// Get a human readable label
    pub fn label(self) -> &'static str {
        match self {
            Self::FullyAutomated => "Fully Auto",
            Self::SemiAutomated => "Semi Auto",
            Self::Manual => "Manual",
            Self::Hybrid => "Hybrid",
            Self::Trackline => "Trackline",
        }
    }
}

/// A scheduled module block on the show timeline.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct ModuleArrangementItem {
    /// Unique ID for stable runtime selection.
    pub id: u64,
    /// Target module.
    pub module_id: ModuleId,
    /// Block start time in seconds.
    pub start_time: f32,
    /// Block duration in seconds.
    pub duration: f32,
    /// Whether this block is active in runtime.
    pub enabled: bool,
    /// Trigger that must be active to start this block (Hybrid Mode).
    pub start_trigger: Option<String>,
}

impl Default for ModuleArrangementItem {
    fn default() -> Self {
        Self {
            id: 0,
            module_id: 0,
            start_time: 0.0,
            duration: 8.0,
            enabled: true,
            start_trigger: None,
        }
    }
}

impl ModuleArrangementItem {
    /// Get the end time of the block
    pub fn end_time(&self) -> f32 {
        self.start_time + self.duration.max(0.1)
    }
}

/// Persistent model for show control orchestration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct ShowControlModel {
    /// Enable module arrangement show-control.
    pub show_control_enabled: bool,
    /// ID counter for arrangement blocks.
    pub next_arrangement_id: u64,
    /// Selected show mode
    pub show_mode: ShowMode,
    /// Scheduled module blocks
    pub module_arrangement: Vec<ModuleArrangementItem>,
}

impl Default for ShowControlModel {
    fn default() -> Self {
        Self {
            show_control_enabled: false,
            next_arrangement_id: 1,
            show_mode: ShowMode::default(),
            module_arrangement: Vec::new(),
        }
    }
}
