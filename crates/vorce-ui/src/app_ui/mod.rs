use crate::action::UIAction;
use crate::config;
use crate::core::i18n::LocaleManager;
use crate::editors::{
    module_canvas::ModuleCanvas, node_editor::NodeEditor, shortcut_editor::ShortcutEditor,
    timeline_v2::TimelineV2,
};
use crate::panels::{
    assignment_panel::AssignmentPanel, audio_panel::AudioPanel,
    controller_overlay_panel::ControllerOverlayPanel, cue_panel::CuePanel,
    edge_blend_panel::EdgeBlendPanel, effect_chain::EffectChainPanel, inspector::InspectorPanel,
    layer_panel::LayerPanel, mapping_panel::MappingPanel, oscillator_panel::OscillatorPanel,
    output_panel::OutputPanel, paint_panel::PaintPanel, preview_panel::PreviewPanel,
    transform_panel::TransformPanel,
};
use crate::view::{
    dashboard::Dashboard, media_browser::MediaBrowser, menu_bar, module_sidebar::ModuleSidebar,
};
use crate::widgets::icon_demo_panel;

use vorce_control::ControlTarget;

/// UI state for the application
pub struct AppUI {
    /// Main menu bar
    pub menu_bar: menu_bar::MenuBar,
    /// Dashboard panel
    pub dashboard: Dashboard,
    /// Paint manager panel
    pub paint_panel: PaintPanel,
    /// Show OSC configuration panel
    pub show_osc_panel: bool,
    /// Selected target for control assignment
    pub selected_control_target: ControlTarget,
    /// OSC input port
    pub osc_port_input: String,
    /// OSC client address
    pub osc_client_input: String,
    /// Show playback controls window
    pub show_controls: bool,
    /// Show performance statistics overlay
    pub show_stats: bool,
    /// Show main toolbar
    pub show_toolbar: bool,
    /// Show layers panel (legacy)
    pub show_layers: bool,

    /// Show timeline panel
    pub show_timeline: bool,
    /// Show shader graph editor
    pub show_shader_graph: bool,
    /// Layer panel state
    pub layer_panel: LayerPanel,
    /// Show mapping configuration
    pub show_mappings: bool,
    /// Mapping panel state
    pub mapping_panel: MappingPanel,
    /// Show transform controls (legacy)
    pub show_transforms: bool, // Phase 1
    /// Show master composition controls
    pub show_master_controls: bool, // Phase 1
    /// Show output configuration
    pub show_outputs: bool, // Phase 2
    /// Output panel state
    pub output_panel: OutputPanel,
    /// Edge blend configuration panel
    pub edge_blend_panel: EdgeBlendPanel,
    /// Oscillator control panel
    pub oscillator_panel: OscillatorPanel,
    /// Show audio panel
    pub show_audio: bool,
    /// Audio panel state
    pub audio_panel: AudioPanel,
    /// Show level meters inside audio panel
    pub show_audio_panel_meters: bool,
    /// FFT visualization mode for audio panel
    pub audio_fft_mode: crate::panels::audio_panel::FftVisualizationMode,       
    /// Show cue list panel
    pub show_cue_panel: bool,
    /// Assignment panel state
    pub assignment_panel: AssignmentPanel,
    /// Show assignment panel
    pub show_assignment_panel: bool,
    /// Global playback speed
    pub playback_speed: f32,
    /// Global loop mode
    pub loop_mode: vorce_media::LoopMode,
    // Phase 1: Transform editing state
    /// Currently selected layer ID
    pub selected_layer_id: Option<u64>,
    // Phase 2: Output configuration state
    /// Currently selected output ID
    pub selected_output_id: Option<u64>,
    /// List of available audio devices
    pub audio_devices: Vec<String>,
    /// Currently selected audio device
    pub selected_audio_device: Option<String>,
    /// Recent project files
    pub recent_files: Vec<String>,
    /// Pending UI actions to be processed
    pub actions: Vec<UIAction>,
    /// Localization manager
    pub i18n: LocaleManager,
    /// Effect chain editor panel
    pub effect_chain_panel: EffectChainPanel,
    /// Cue list panel
    pub cue_panel: CuePanel,
    /// Timeline V2 panel
    pub timeline_panel: TimelineV2,
    /// Node editor panel state
    pub node_editor_panel: NodeEditor,
    /// Transform control panel
    pub transform_panel: TransformPanel,
    /// Shortcut editor panel
    pub shortcut_editor: ShortcutEditor,
    /// Icon manager
    pub icon_manager: Option<crate::widgets::icons::IconManager>,
    /// Icon demo panel
    pub icon_demo_panel: icon_demo_panel::IconDemoPanel,
    /// User configuration
    pub user_config: config::UserConfig,
    /// Show settings window
    pub show_settings: bool,
    /// Show about window
    pub show_about: bool,
    /// Show media browser
    pub show_media_browser: bool,
    /// Media browser panel
    pub media_browser: MediaBrowser,
    /// Inspector panel for context-sensitive properties
    pub inspector_panel: InspectorPanel,
    /// Show inspector panel
    pub show_inspector: bool,
    /// Module sidebar panel
    pub module_sidebar: ModuleSidebar,
    /// Show module sidebar
    pub show_module_sidebar: bool,
    /// Module canvas (node editor)
    pub module_canvas: ModuleCanvas,
    /// Show module canvas
    pub show_module_canvas: bool,
    /// Left sidebar visibility (collapsible)
    pub show_left_sidebar: bool,
    /// Current audio level (0.0-1.0) for toolbar display
    pub current_audio_level: f32,
    /// Current FPS for toolbar display
    pub current_fps: f32,
    /// Current frame time in ms for toolbar display
    pub current_frame_time_ms: f32,
    /// Target FPS from settings
    pub target_fps: f32,
    /// CPU usage percentage (0.0-100.0)
    pub cpu_usage: f32,
    /// GPU usage percentage (0.0-100.0)
    pub gpu_usage: f32,
    /// RAM usage in MB
    pub ram_usage_mb: f32,
    /// Controller overlay panel
    pub controller_overlay: ControllerOverlayPanel,
    /// Show controller overlay
    pub show_controller_overlay: bool,
    /// Global flag for "Hover" MIDI Learn Mode (Way 1)
    pub is_midi_learn_mode: bool,
    /// Current detected BPM (None if not detected yet)
    pub current_bpm: Option<f32>,
    /// Preview panel for output thumbnails
    pub preview_panel: PreviewPanel,
    /// Show preview panel
    pub show_preview_panel: bool,
    /// Control panel height in unified sidebar (pixels)
    pub control_panel_height: f32,
    /// Show control panel in unified sidebar
    pub show_control_panel: bool,
    /// Discovered Hue Bridges
    pub discovered_hue_bridges: Vec<vorce_control::hue::api::discovery::DiscoveredBridge>,
    /// Available Hue Entertainment Groups (ID, Name)
    pub available_hue_groups: Vec<(String, String)>,
    /// System Info
    pub sys_info: sysinfo::System,
    /// Active keyboard keys (for Shortcut triggers)
    pub active_keys: std::collections::HashSet<String>,

    /// Active tab in compact sidebar (0 = Controls, 1 = Preview)
    pub active_sidebar_tab: usize,

    /// Last time responsive styles were updated
    last_style_update: std::time::Instant,
}

impl Default for AppUI {
    fn default() -> Self {
        Self::from_user_config(config::UserConfig::load())
    }
}

pub mod control;
pub mod icons;
pub mod layout;
pub mod render;
