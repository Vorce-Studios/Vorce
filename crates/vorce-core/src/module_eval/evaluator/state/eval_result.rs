//! Evaluation Result.
use std::collections::HashMap;
use crate::module::ModulePartId;
use super::{SourceCommand, RenderOp};

/// Evaluation result for a single frame
#[derive(Debug, Clone, Default)]
pub struct ModuleEvalResult {
    /// Trigger values: part_id -> (output_index -> value)
    pub trigger_values: HashMap<ModulePartId, Vec<f32>>,
    /// Source commands: part_id -> SourceCommand
    pub source_commands: HashMap<ModulePartId, SourceCommand>,
    /// Render operations to specific outputs
    pub render_ops: Vec<RenderOp>,
    /// Spare render operations for reuse (object pooling)
    pub spare_render_ops: Vec<RenderOp>,
}

impl ModuleEvalResult {
    /// Clears the result for reuse, preserving capacity where possible
    pub fn clear(&mut self) {
        // Clear trigger values but keep the vectors to reuse their capacity
        for values in self.trigger_values.values_mut() {
            values.clear();
        }

        // Source commands are typically small (one per source), but we can clear the map
        self.source_commands.clear();

        // Recycle render ops instead of clearing (which drops/frees internal vectors)
        self.spare_render_ops.append(&mut self.render_ops);
    }
}
