//! Phase 6: Enhanced Timeline Editor with Keyframe Animation UI Logic
//!
//! Multi-track timeline with keyframe animation, using vorce_core::animation types.

pub mod arrangement;
pub mod helpers;
pub mod render;
pub mod show_control;

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use vorce_core::module::ModuleId;

use super::models::{ModuleArrangementItem, ShowMode};

/// Timeline editor view state (data is in AnimationClip)
#[derive(Serialize, Deserialize)]
#[serde(default)]
pub struct TimelineV2 {
    /// Playhead position (in seconds) - purely for visualization if not synced
    pub playhead: f32,
    /// Zoom level (pixels per second)
    pub zoom: f32,
    /// Pan offset
    pub pan_offset: f32,
    /// Snap settings
    pub snap_enabled: bool,
    pub snap_interval: f32,
    /// Selected keyframes (track_name, key_time_us)
    pub selected_keyframes: Vec<(String, u64)>,
    /// Show curve editor
    pub show_curve_editor: bool,
    /// Expanded automation tracks/groups
    pub expanded_tracks: HashSet<String>,
    /// Enable module arrangement show-control.
    pub show_control_enabled: bool,
    /// Selected show mode.
    pub show_mode: ShowMode,
    /// Scheduled module blocks.
    pub module_arrangement: Vec<ModuleArrangementItem>,
    /// UI add-block module selection.
    pub selected_module_id: Option<ModuleId>,
    /// ID counter for arrangement blocks.
    pub next_arrangement_id: u64,
    /// Manual mode current block.
    pub manual_current_block_id: Option<u64>,
    /// Semi-auto current block.
    pub semi_auto_current_block_id: Option<u64>,
    /// Semi-auto pending block (needs GO).
    pub semi_auto_pending_block_id: Option<u64>,
    /// Full-auto last block.
    pub full_auto_current_block_id: Option<u64>,
    /// Hybrid mode current block.
    pub hybrid_current_block_id: Option<u64>,
    /// Hybrid mode active triggers (aggregated from MIDI, OSC, and keyboard).
    pub hybrid_active_triggers: HashSet<String>,
    /// Selected marker ID.
    pub selected_marker_id: Option<u64>,
}

impl Default for TimelineV2 {
    fn default() -> Self {
        Self {
            playhead: 0.0,
            zoom: 100.0,
            pan_offset: 0.0,
            snap_enabled: true,
            snap_interval: 0.1, // 100ms default snap
            selected_keyframes: Vec::new(),
            show_curve_editor: false,
            expanded_tracks: HashSet::new(),
            show_control_enabled: true,
            show_mode: ShowMode::FullyAutomated,
            module_arrangement: Vec::new(),
            selected_module_id: None,
            next_arrangement_id: 1,
            manual_current_block_id: None,
            semi_auto_current_block_id: None,
            semi_auto_pending_block_id: None,
            full_auto_current_block_id: None,
            hybrid_current_block_id: None,
            hybrid_active_triggers: HashSet::new(),
            selected_marker_id: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_timeline_empty_arrangement() {
        let mut timeline = TimelineV2 {
            show_mode: ShowMode::FullyAutomated,
            module_arrangement: vec![],
            ..TimelineV2::default()
        };

        let available_ids = vec![101, 102];

        let mod_id = timeline.runtime_show_module(5.0, true, &available_ids);
        assert_eq!(mod_id, None);
    }

    #[test]
    fn test_timeline_overlapping_cues() {
        let mut timeline = TimelineV2 {
            show_mode: ShowMode::FullyAutomated,
            module_arrangement: vec![
                ModuleArrangementItem {
                    id: 1,
                    module_id: 101,
                    start_time: 0.0,
                    duration: 10.0,
                    enabled: true,
                    start_trigger: None,
                },
                ModuleArrangementItem {
                    id: 2,
                    module_id: 102,
                    start_time: 5.0,
                    duration: 10.0,
                    enabled: true,
                    start_trigger: None,
                },
            ],
            ..TimelineV2::default()
        };

        let available_ids = vec![101, 102];

        let mod_id = timeline.runtime_show_module(7.0, true, &available_ids);
        assert_eq!(mod_id, Some(101));
    }

    #[test]
    fn test_timeline_boundary_timestamps() {
        let mut timeline = TimelineV2 {
            show_mode: ShowMode::FullyAutomated,
            module_arrangement: vec![
                ModuleArrangementItem {
                    id: 1,
                    module_id: 101,
                    start_time: 0.0,
                    duration: 10.0,
                    enabled: true,
                    start_trigger: None,
                },
                ModuleArrangementItem {
                    id: 2,
                    module_id: 102,
                    start_time: 10.0,
                    duration: 10.0,
                    enabled: true,
                    start_trigger: None,
                },
            ],
            ..TimelineV2::default()
        };

        let available_ids = vec![101, 102];

        let mod_id = timeline.runtime_show_module(10.0, true, &available_ids);
        assert_eq!(mod_id, Some(102));
    }

    #[test]
    fn test_timeline_invalid_edits() {
        let mut timeline = TimelineV2 {
            show_mode: ShowMode::FullyAutomated,
            module_arrangement: vec![ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: -5.0,
                enabled: true,
                start_trigger: None,
            }],
            ..TimelineV2::default()
        };

        let available_ids = vec![101];

        let mod_id = timeline.runtime_show_module(2.0, true, &available_ids);
        assert_eq!(mod_id, Some(101));
    }
}
