use crate::audio::analyzer_v2::AudioAnalysisV2;
use crate::audio_reactive::AudioTriggerData;
use crate::module::{BlendModeType, MaskType, MeshType, ModulePartId, ModulizerType, OutputType};
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use crate::module_eval::types::*;

/// The evaluator traverses the module graph and computes output values.
pub struct ModuleEvaluator {
    /// Current trigger data from audio analysis
    pub(crate) audio_trigger_data: AudioTriggerData,
    /// Creation time for timing calculations
    pub(crate) start_time: Instant,
    /// Per-node state for stateful triggers (e.g., Random)
    #[allow(dead_code)]
    pub(crate) trigger_states: HashMap<ModulePartId, TriggerState>,
    /// Reusable result buffer to avoid allocations
    pub cached_result: ModuleEvalResult,

    /// Cached indices per module ID to support multi-module switching
    pub(crate) indices_cache: HashMap<crate::module::ModuleId, Arc<ModuleGraphIndices>>,

    /// Currently active keyboard keys (for Shortcut triggers)
    pub(crate) active_keys: std::collections::HashSet<String>,

    /// State for smoothed trigger inputs: (PartId, SocketIdx) -> (Current Value, Last Updated Frame)
    pub(crate) trigger_smoothing_state: RefCell<HashMap<(ModulePartId, usize), (f32, u64)>>,

    /// Manually fired triggers for the current frame
    pub(crate) manual_triggers: std::collections::HashSet<ModulePartId>,

    /// MIDI notes/CCs received this frame: (channel, note/cc)
    pub(crate) midi_triggers: std::collections::HashSet<(u8, u8)>,

    /// OSC addresses received this frame
    pub(crate) osc_triggers: std::collections::HashSet<String>,

    /// Current evaluation frame count (used to prevent smoothing multiple times per frame)
    pub(crate) current_frame: u64,

    /// Time of the last evaluation (used for delta time calculation)
    pub(crate) last_eval_time: Instant,

    /// The delta time calculated at the start of the current evaluation frame
    pub(crate) current_dt: f32,
}

impl Default for ModuleEvaluator {
    fn default() -> Self {
        Self::new()
    }
}

impl ModuleEvaluator {
    /// Create a new module evaluator
    pub fn new() -> Self {
        Self {
            audio_trigger_data: AudioTriggerData::default(),
            start_time: Instant::now(),
            trigger_states: HashMap::new(),
            cached_result: ModuleEvalResult::default(),
            indices_cache: HashMap::new(),
            active_keys: std::collections::HashSet::new(),
            trigger_smoothing_state: RefCell::new(HashMap::new()),
            manual_triggers: std::collections::HashSet::new(),
            midi_triggers: std::collections::HashSet::new(),
            osc_triggers: std::collections::HashSet::new(),
            current_frame: 0,
            last_eval_time: Instant::now(),
            current_dt: 0.0,
        }
    }

    /// Inject the frame delta reported by the outer app loop.
    pub fn set_delta_time(&mut self, dt: f32) {
        let clamped = dt.clamp(0.0, 0.5);
        self.current_dt = clamped;
        self.last_eval_time = Instant::now() - std::time::Duration::from_secs_f32(clamped);
    }

    /// Manually fire a trigger node for the next evaluation frame
    pub fn trigger_node(&mut self, part_id: ModulePartId) {
        self.manual_triggers.insert(part_id);
    }

    /// Record an OSC message for the next evaluation frame
    pub fn record_osc(&mut self, address: &str) {
        self.osc_triggers.insert(address.to_string());
    }

    /// Update audio trigger data from analysis
    pub fn update_audio(&mut self, analysis: &AudioAnalysisV2) {
        self.audio_trigger_data.band_energies = analysis.band_energies;
        self.audio_trigger_data.rms_volume = analysis.rms_volume;
        self.audio_trigger_data.peak_volume = analysis.peak_volume;
        self.audio_trigger_data.beat_detected = analysis.beat_detected;
        self.audio_trigger_data.beat_strength = analysis.beat_strength;
        self.audio_trigger_data.bpm = analysis.tempo_bpm;
    }

    /// Update active keyboard keys for evaluation.
    pub fn update_keys(&mut self, keys: &std::collections::HashSet<String>) {
        self.active_keys = keys.clone();
    }

    /// Get a spare RenderOp from the cache or create a new one (Object Pooling)
    pub(crate) fn get_spare_render_op(&mut self) -> RenderOp {
        self.cached_result.spare_render_ops.pop().unwrap_or_else(|| RenderOp {
            output_part_id: 0,
            output_type: OutputType::Projector {
                id: 0,
                name: String::new(),
                hide_cursor: false,
                target_screen: 0,
                show_in_preview_panel: true,
                extra_preview_window: false,
                output_width: 1920,
                output_height: 1080,
                output_fps: 60.0,
                ndi_enabled: false,
                ndi_stream_name: String::new(),
            },
            layer_part_id: 0,
            mesh: MeshType::default(),
            opacity: 1.0,
            blend_mode: None,
            mapping_mode: false,
            source_part_id: None,
            source_props: SourceProperties::default_identity(),
            effects: Vec::new(),
            masks: Vec::new(),
        })
    }
}

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
