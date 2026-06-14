use super::super::models::ModuleArrangementItem;
use super::TimelineV2;
use vorce_core::module::ModuleId;

impl TimelineV2 {
    pub(crate) fn add_module_block(&mut self, module_id: ModuleId) {
        let default_start =
            self.module_arrangement.iter().map(ModuleArrangementItem::end_time).fold(0.0, f32::max);
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
        block_id.and_then(|id| self.find_block(id)).map(|block| block.module_id)
    }
}
