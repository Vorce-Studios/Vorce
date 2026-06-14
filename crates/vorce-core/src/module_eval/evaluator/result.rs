use crate::module::{BlendModeType, MaskType, MeshType, ModulePartId, ModulizerType, OutputType};
use crate::module_eval::types::SourceProperties;
use std::collections::HashMap;

/// Render operation containing all info needed to render a layer to an output
#[derive(Debug, Clone)]
pub struct RenderOp {
    /// The output node ID (Part ID)
    pub output_part_id: ModulePartId,
    /// The specific output type configuration
    pub output_type: OutputType,

    /// The layer node ID calling for this render
    pub layer_part_id: ModulePartId,
    /// The mesh geometry to use
    pub mesh: MeshType,
    /// Layer opacity
    pub opacity: f32,
    /// Layer blend mode
    pub blend_mode: Option<BlendModeType>,
    /// Mapping mode active (render grid)
    pub mapping_mode: bool,

    /// Source part ID (if any)
    pub source_part_id: Option<ModulePartId>,
    /// Source-specific properties (color, transform, flip)
    pub source_props: SourceProperties,
    /// Applied effects in order (Source -> Effect1 -> Effect2 -> ...)
    pub effects: Vec<ModulizerType>,
    /// Applied masks
    pub masks: Vec<MaskType>,
}

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
        // Note: We don't remove keys from trigger_values map to reuse map capacity and vectors.
        // However, if the graph changes, we might accumulate stale keys.
        // For a fixed graph (most of the time), this is fine.
        // To be safe against memory leaks on graph changes, we could occasionally prune.
        // For now, simple reuse is a huge win.

        // Source commands are typically small (one per source), but we can clear the map
        self.source_commands.clear();

        // Recycle render ops instead of clearing (which drops/frees internal vectors)
        self.spare_render_ops.append(&mut self.render_ops);
    }
}

/// Command for a source node
#[derive(Debug, Clone)]
pub enum SourceCommand {
    /// Play media from a local path.
    PlayMedia {
        /// Path to the media file.
        path: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Play media from the shared library.
    PlaySharedMedia {
        /// Unique identifier for the shared media.
        id: String,
        /// Path to the media file.
        path: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Render a shader with the given parameters.
    PlayShader {
        /// Name of the shader.
        name: String,
        /// List of (parameter name, value) tuples.
        params: Vec<(String, f32)>,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Receive frames from an NDI source.
    NdiInput {
        /// Name of the NDI source.
        source_name: Option<String>,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Receive frames from a live video device.
    LiveInput {
        /// ID of the capture device.
        device_id: u32,
        /// Current trigger value.
        trigger_value: f32,
    },
    #[cfg(target_os = "windows")]
    /// Receive frames from a Spout sender (Windows only).
    SpoutInput {
        /// Name of the Spout sender.
        sender_name: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Input from the Bevy game engine.
    BevyInput {
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Render a 3D model via Bevy.
    Bevy3DModel {
        /// Path to the 3D model.
        path: String,
        /// Position in 3D space.
        position: [f32; 3],
        /// Rotation in degrees.
        rotation: [f32; 3],
        /// Scale factor.
        scale: [f32; 3],
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Control Philips Hue smart lights.
    HueOutput {
        /// Brightness level (0.0 - 1.0).
        brightness: f32,
        /// Hue value (0.0 - 1.0, optional).
        hue: Option<f32>,
        /// Saturation level (0.0 - 1.0, optional).
        saturation: Option<f32>,
        /// Strobe speed (0.0 - 1.0, optional).
        strobe: Option<f32>,
        /// List of light IDs to control.
        ids: Option<Vec<String>>,
    },
}
