use super::super::models::ModuleArrangementItem;
use super::super::types::TimelineModule;
use super::TimelineV2;
use std::collections::{HashMap, HashSet};
use vorce_core::module::ModuleId;

impl TimelineV2 {
    /// Snap time to grid
    pub fn snap_time(&self, time: f32) -> f32 {
        if self.snap_enabled && self.snap_interval > 0.0 {
            (time / self.snap_interval).round() * self.snap_interval
        } else {
            time
        }
    }

    pub(crate) fn sorted_enabled_blocks(&self) -> Vec<&ModuleArrangementItem> {
        let mut blocks: Vec<&ModuleArrangementItem> =
            self.module_arrangement.iter().filter(|item| item.enabled).collect();
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
        self.module_arrangement.iter().find(|item| item.id == block_id)
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
        self.module_arrangement.retain(|item| valid.contains(&item.module_id));

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
}
