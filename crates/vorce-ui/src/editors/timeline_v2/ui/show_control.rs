use super::super::models::{ModuleArrangementItem, ShowMode};
use super::TimelineV2;
use vorce_core::module::ModuleId;

impl TimelineV2 {
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
                    active_blocks.sort_by_key(|a| a.start_trigger.is_some());

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
            let idx = block_ids.iter().position(|id| *id == current_id).unwrap_or(0);
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
            let idx = block_ids.iter().position(|id| *id == current_id).unwrap_or(0);
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
            let idx = block_ids.iter().position(|id| *id == current_id).unwrap_or(0);
            (idx + 1).min(block_ids.len().saturating_sub(1))
        } else {
            0
        };

        self.semi_auto_current_block_id = Some(block_ids[next_index]);
        self.module_for_block_id(self.semi_auto_current_block_id)
    }
}
