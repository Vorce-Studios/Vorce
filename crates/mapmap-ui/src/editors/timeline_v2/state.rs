use super::types::*;
use mapmap_core::module::ModuleId;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

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
    /// Hybrid mode active triggers.
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

impl TimelineV2 {
    /// Snap time to grid
    pub(crate) fn snap_time(&self, time: f32) -> f32 {
        if self.snap_enabled && self.snap_interval > 0.0 {
            (time / self.snap_interval).round() * self.snap_interval
        } else {
            time
        }
    }

    pub(crate) fn sorted_enabled_blocks(&self) -> Vec<&ModuleArrangementItem> {
        let mut blocks: Vec<&ModuleArrangementItem> = self
            .module_arrangement
            .iter()
            .filter(|item| item.enabled)
            .collect();
        blocks.sort_by(|a, b| a.start_time.total_cmp(&b.start_time).then(a.id.cmp(&b.id)));
        blocks
    }

    pub(crate) fn sorted_enabled_block_ids(&self) -> Vec<u64> {
        let mut pairs: Vec<(u64, f32)> = self
            .module_arrangement
            .iter()
            .filter(|item| item.enabled)
            .map(|item| (item.id, item.start_time))
            .collect();
        pairs.sort_by(|a, b| a.1.total_cmp(&b.1).then(a.0.cmp(&b.0)));
        pairs.into_iter().map(|(id, _)| id).collect()
    }

    pub(crate) fn find_block(&self, block_id: u64) -> Option<&ModuleArrangementItem> {
        self.module_arrangement
            .iter()
            .find(|item| item.id == block_id)
    }

    pub(crate) fn first_enabled_block_id(&self) -> Option<u64> {
        self.sorted_enabled_blocks().first().map(|item| item.id)
    }

    pub(crate) fn active_block_for_time(&self, time: f32) -> Option<&ModuleArrangementItem> {
        let blocks = self.sorted_enabled_blocks();
        if blocks.is_empty() {
            return None;
        }

        for block in &blocks {
            if time >= block.start_time && time < block.end_time() {
                return Some(block);
            }
        }

        if let Some(last_before) = blocks.iter().rev().find(|block| time >= block.start_time) {
            return Some(last_before);
        }

        blocks.first().copied()
    }

    pub(crate) fn module_name_map<'a>(
        modules: &[TimelineModule<'a>],
    ) -> HashMap<ModuleId, &'a str> {
        modules.iter().map(|m| (m.id, m.name)).collect()
    }

    pub(crate) fn module_name(
        module_names: &HashMap<ModuleId, &str>,
        module_id: ModuleId,
    ) -> String {
        module_names
            .get(&module_id)
            .map(|s| s.to_string())
            .unwrap_or_else(|| format!("Module {}", module_id))
    }

    pub(crate) fn reset_runtime_selection(&mut self) {
        self.manual_current_block_id = None;
        self.semi_auto_current_block_id = None;
        self.semi_auto_pending_block_id = None;
        self.full_auto_current_block_id = None;
        self.hybrid_current_block_id = None;
    }

    pub(crate) fn cleanup_missing_modules(&mut self, available_module_ids: &[ModuleId]) {
        let valid: HashSet<ModuleId> = available_module_ids.iter().copied().collect();
        self.module_arrangement
            .retain(|item| valid.contains(&item.module_id));

        let has_block = |id: Option<u64>, blocks: &[ModuleArrangementItem]| {
            id.is_some_and(|block_id| blocks.iter().any(|item| item.id == block_id))
        };

        if !has_block(self.manual_current_block_id, &self.module_arrangement) {
            self.manual_current_block_id = None;
        }
        if !has_block(self.semi_auto_current_block_id, &self.module_arrangement) {
            self.semi_auto_current_block_id = None;
        }
        if !has_block(self.semi_auto_pending_block_id, &self.module_arrangement) {
            self.semi_auto_pending_block_id = None;
        }
        if !has_block(self.full_auto_current_block_id, &self.module_arrangement) {
            self.full_auto_current_block_id = None;
        }
        if !has_block(self.hybrid_current_block_id, &self.module_arrangement) {
            self.hybrid_current_block_id = None;
        }
    }

    pub(crate) fn add_module_block(&mut self, module_id: ModuleId) {
        let default_start = self
            .module_arrangement
            .iter()
            .map(ModuleArrangementItem::end_time)
            .fold(0.0, f32::max);
        let id = self.next_arrangement_id;
        self.next_arrangement_id = self.next_arrangement_id.saturating_add(1);

        self.module_arrangement.push(ModuleArrangementItem {
            id,
            module_id,
            start_time: default_start,
            duration: 8.0,
            enabled: true,
            start_trigger: None,
        });
    }

    pub(crate) fn set_manual_current(&mut self, block_id: Option<u64>) {
        self.manual_current_block_id = block_id;
    }

    pub(crate) fn module_for_block_id(&self, block_id: Option<u64>) -> Option<ModuleId> {
        block_id
            .and_then(|id| self.find_block(id))
            .map(|block| block.module_id)
    }

    /// Returns the module that should be active for show playback.
    /// `None` means "do not filter modules".
    pub fn runtime_show_module(
        &mut self,
        current_time: f32,
        is_playing: bool,
        available_module_ids: &[ModuleId],
    ) -> Option<ModuleId> {
        self.cleanup_missing_modules(available_module_ids);

        if !self.show_control_enabled {
            return None;
        }
        if self.sorted_enabled_blocks().is_empty() {
            return None;
        }

        match self.show_mode {
            ShowMode::FullyAutomated | ShowMode::Trackline => {
                let active_id = self.active_block_for_time(current_time).map(|b| b.id);
                self.full_auto_current_block_id = active_id;
                self.manual_current_block_id = active_id;
                self.module_for_block_id(active_id)
            }
            ShowMode::SemiAutomated => {
                if self.semi_auto_current_block_id.is_none() {
                    self.semi_auto_current_block_id = self.first_enabled_block_id();
                }

                if is_playing {
                    if let Some(time_block_id) =
                        self.active_block_for_time(current_time).map(|b| b.id)
                    {
                        if self.semi_auto_current_block_id != Some(time_block_id) {
                            self.semi_auto_pending_block_id = Some(time_block_id);
                        }
                    }
                }

                if self.semi_auto_current_block_id.is_none() {
                    self.semi_auto_current_block_id = self.first_enabled_block_id();
                }

                self.module_for_block_id(self.semi_auto_current_block_id)
            }
            ShowMode::Manual => {
                if self.manual_current_block_id.is_none() {
                    self.manual_current_block_id = self.first_enabled_block_id();
                }
                self.module_for_block_id(self.manual_current_block_id)
            }
            ShowMode::Hybrid => {
                if self.hybrid_current_block_id.is_none() {
                    self.hybrid_current_block_id = self.first_enabled_block_id();
                }

                if is_playing {
                    let blocks = self.sorted_enabled_blocks();

                    // Find all blocks that overlap with the current time
                    let mut active_blocks: Vec<&ModuleArrangementItem> = blocks
                        .iter()
                        .copied()
                        .filter(|b| current_time >= b.start_time && current_time < b.end_time())
                        .collect();

                    // Sort by whether they require triggers (those without triggers are defaults)
                    active_blocks
                        .sort_by(|a, b| a.start_trigger.is_some().cmp(&b.start_trigger.is_some()));

                    let mut next_block_id = self.hybrid_current_block_id;

                    // Evaluate blocks matching current time
                    for block in active_blocks {
                        if let Some(trigger) = &block.start_trigger {
                            if self.hybrid_active_triggers.contains(trigger) {
                                next_block_id = Some(block.id);
                                break; // Trigger matched, take this block
                            }
                        } else {
                            // Block has no trigger, it's the default for this time
                            let current_is_active =
                                if let Some(current_id) = self.hybrid_current_block_id {
                                    blocks.iter().find(|b| b.id == current_id).is_some_and(|b| {
                                        current_time >= b.start_time && current_time < b.end_time()
                                    })
                                } else {
                                    false
                                };

                            if !current_is_active {
                                next_block_id = Some(block.id);
                            }
                        }
                    }

                    if next_block_id != self.hybrid_current_block_id {
                        self.hybrid_current_block_id = next_block_id;
                    }
                }

                self.module_for_block_id(self.hybrid_current_block_id)
            }
        }
    }

    /// In manual mode, advance to next arranged module.
    pub fn step_manual_next(&mut self) -> Option<ModuleId> {
        let block_ids = self.sorted_enabled_block_ids();
        if block_ids.is_empty() {
            self.manual_current_block_id = None;
            return None;
        }

        let next_index = if let Some(current_id) = self.manual_current_block_id {
            let idx = block_ids
                .iter()
                .position(|id| *id == current_id)
                .unwrap_or(0);
            (idx + 1) % block_ids.len()
        } else {
            0
        };

        self.manual_current_block_id = Some(block_ids[next_index]);
        self.module_for_block_id(self.manual_current_block_id)
    }

    /// In manual mode, go to previous arranged module.
    pub fn step_manual_prev(&mut self) -> Option<ModuleId> {
        let block_ids = self.sorted_enabled_block_ids();
        if block_ids.is_empty() {
            self.manual_current_block_id = None;
            return None;
        }

        let prev_index = if let Some(current_id) = self.manual_current_block_id {
            let idx = block_ids
                .iter()
                .position(|id| *id == current_id)
                .unwrap_or(0);
            if idx == 0 {
                block_ids.len() - 1
            } else {
                idx - 1
            }
        } else {
            0
        };

        self.manual_current_block_id = Some(block_ids[prev_index]);
        self.module_for_block_id(self.manual_current_block_id)
    }

    /// In semi-auto mode, confirm or advance to next module.
    pub fn step_semi_auto_next(&mut self) -> Option<ModuleId> {
        if let Some(pending) = self.semi_auto_pending_block_id.take() {
            self.semi_auto_current_block_id = Some(pending);
            return self.module_for_block_id(self.semi_auto_current_block_id);
        }

        let block_ids = self.sorted_enabled_block_ids();
        if block_ids.is_empty() {
            self.semi_auto_current_block_id = None;
            return None;
        }

        let next_index = if let Some(current_id) = self.semi_auto_current_block_id {
            let idx = block_ids
                .iter()
                .position(|id| *id == current_id)
                .unwrap_or(0);
            (idx + 1).min(block_ids.len().saturating_sub(1))
        } else {
            0
        };

        self.semi_auto_current_block_id = Some(block_ids[next_index]);
        self.module_for_block_id(self.semi_auto_current_block_id)
    }
}
