use crate::audio::analyzer_v2::AudioAnalysisV2;
use crate::audio_reactive::AudioTriggerData;
use crate::module::{MeshType, ModulePartId, OutputType};
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use super::result::{ModuleEvalResult, RenderOp};
use crate::module_eval::types::{ModuleGraphIndices, SourceProperties, TriggerState};

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
