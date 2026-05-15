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
use crate::widgets::icons;
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
    pub icon_manager: Option<icons::IconManager>,
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

impl AppUI {
    /// Create UI state from a preloaded user configuration.
    pub fn from_user_config(mut user_config: config::UserConfig) -> Self {
        user_config.ensure_layout_profiles();

        let active_layout = user_config
            .active_layout()
            .cloned()
            .unwrap_or_else(config::LayoutProfile::default_profile);

        let saved_audio_device = user_config.selected_audio_device.clone();
        let saved_recent_files = user_config.recent_files.clone();
        let saved_language = user_config.language.clone();
        let saved_target_fps = user_config.target_fps.unwrap_or(60.0);
        let saved_show_controller_overlay = user_config.show_controller_overlay;

        let mut app_ui = Self {
            menu_bar: menu_bar::MenuBar::default(),
            dashboard: Dashboard::default(),
            paint_panel: PaintPanel::default(),
            show_osc_panel: false, // Hide by default - advanced feature
            selected_control_target: ControlTarget::Custom("".to_string()),
            osc_port_input: "8000".to_string(),
            osc_client_input: "127.0.0.1:9000".to_string(),
            show_controls: false, // Hide by default - use Dashboard instead
            show_stats: true,     // Keep performance overlay
            show_layers: true,
            layer_panel: LayerPanel { visible: true },
            show_mappings: false, // Hide by default - use Inspector when ready
            mapping_panel: MappingPanel { visible: false },
            show_transforms: false,     // Hide - will move to Inspector
            show_master_controls: true, // Keep visible
            show_outputs: false,        // Hide by default
            output_panel: {
                let mut panel = OutputPanel::default();
                panel.visible = false;
                panel
            },
            edge_blend_panel: EdgeBlendPanel::default(),
            oscillator_panel: OscillatorPanel::default(), // Hide by default
            show_audio: false,                            // Hide by default - use Dashboard toggle
            audio_panel: AudioPanel::default(),
            show_audio_panel_meters: true,
            audio_fft_mode: crate::panels::audio_panel::FftVisualizationMode::FullFft,
            show_cue_panel: false, // Hide by default
            assignment_panel: AssignmentPanel::default(),
            show_assignment_panel: false, // Hide by default
            playback_speed: 1.0,
            loop_mode: vorce_media::LoopMode::Loop,
            selected_layer_id: None,
            selected_output_id: None,
            audio_devices: vec!["None".to_string()],
            // Load selected audio device from user config
            selected_audio_device: saved_audio_device,
            recent_files: saved_recent_files,
            actions: Vec::new(),
            i18n: LocaleManager::new(&saved_language),
            effect_chain_panel: EffectChainPanel::default(),
            cue_panel: CuePanel::default(),
            timeline_panel: TimelineV2::default(),
            show_timeline: active_layout.visibility.show_timeline,
            show_shader_graph: false, // Advanced - hide by default
            node_editor_panel: NodeEditor::default(),
            transform_panel: TransformPanel::default(),
            shortcut_editor: ShortcutEditor::new(),
            show_toolbar: active_layout.visibility.show_toolbar,
            icon_manager: None, // Will be initialized with egui context
            icon_demo_panel: icon_demo_panel::IconDemoPanel::default(),
            user_config,
            show_settings: false,
            show_about: false,
            show_media_browser: active_layout.visibility.show_media_browser,
            media_browser: MediaBrowser::new(std::env::current_dir().unwrap_or_default()),
            inspector_panel: InspectorPanel::default(),
            show_inspector: active_layout.visibility.show_inspector,
            module_sidebar: ModuleSidebar::default(),
            show_module_sidebar: true, // Show when Module Canvas is active
            module_canvas: ModuleCanvas::default(),
            show_module_canvas: active_layout.visibility.show_module_canvas,
            show_left_sidebar: active_layout.visibility.show_left_sidebar,
            current_audio_level: 0.0,
            current_fps: 60.0,
            current_frame_time_ms: 16.67,
            target_fps: saved_target_fps,
            cpu_usage: 0.0,
            gpu_usage: 0.0,
            ram_usage_mb: 0.0,
            controller_overlay: ControllerOverlayPanel::new(),
            show_controller_overlay: saved_show_controller_overlay, // Load from config
            is_midi_learn_mode: false,
            current_bpm: None,
            preview_panel: PreviewPanel::default(),
            show_preview_panel: true,    // Show by default
            control_panel_height: 250.0, // Default height in pixels
            show_control_panel: true,    // Show by default
            discovered_hue_bridges: Vec::new(),
            available_hue_groups: Vec::new(),
            sys_info: sysinfo::System::new_all(),
            active_keys: std::collections::HashSet::new(),
            active_sidebar_tab: 0,
            last_style_update: std::time::Instant::now(),
        };

        app_ui.ensure_startup_viability();
        app_ui
    }

    fn has_primary_workspace(&self) -> bool {
        self.show_module_canvas
            || self.show_left_sidebar
            || self.show_inspector
            || self.show_timeline
            || self.show_media_browser
    }

    fn ensure_startup_viability(&mut self) {
        if self.has_primary_workspace() {
            return;
        }

        tracing::error!(
            "Recovered unusable UI startup state: no primary work area was visible. Re-enabling sidebar and module canvas."
        );

        self.show_left_sidebar = true;
        self.show_module_canvas = true;
        self.user_config.show_left_sidebar = true;
        self.user_config.show_module_canvas = true;

        if let Some(layout) = self.user_config.active_layout_mut() {
            layout.visibility.show_left_sidebar = true;
            layout.visibility.show_module_canvas = true;
        }

        if let Err(err) = self.user_config.save() {
            tracing::error!("Failed to persist repaired UI startup state: {}", err);
        }
    }

    /// Wendet das aktive Layoutprofil auf die Runtime-Sichtbarkeitsflags an.
    pub fn apply_active_layout(&mut self) {
        if let Some(layout) = self.user_config.active_layout() {
            self.show_toolbar = layout.visibility.show_toolbar;
            self.show_left_sidebar = layout.visibility.show_left_sidebar;
            self.show_inspector = layout.visibility.show_inspector;
            self.show_timeline = layout.visibility.show_timeline;
            self.show_media_browser = layout.visibility.show_media_browser;
            self.show_module_canvas = layout.visibility.show_module_canvas;
        }
    }

    /// Synchronisiert die Runtime-Sichtbarkeiten zurück in das aktive Layoutprofil.
    pub fn sync_runtime_to_active_layout(&mut self) {
        if let Some(layout) = self.user_config.active_layout_mut() {
            layout.visibility.show_toolbar = self.show_toolbar;
            layout.visibility.show_left_sidebar = self.show_left_sidebar;
            layout.visibility.show_inspector = self.show_inspector;
            layout.visibility.show_timeline = self.show_timeline;
            layout.visibility.show_media_browser = self.show_media_browser;
            layout.visibility.show_module_canvas = self.show_module_canvas;
        }
    }

    /// Update responsive styles based on viewport size
    ///
    /// Only updates every 500ms to preserve performance
    pub fn update_responsive_styles(&mut self, ctx: &egui::Context) {
        // Keep style updates frequent enough for live settings changes while avoiding per-frame churn.
        if self.last_style_update.elapsed().as_millis() < 120 {
            return;
        }
        self.last_style_update = std::time::Instant::now();

        let layout = crate::core::responsive::ResponsiveLayout::new(ctx);

        let mut style = (*ctx.global_style()).clone();
        let base_font_size = self.user_config.theme.font_size.max(10.0);
        let user_scale = self.user_config.ui_scale.clamp(0.8, 1.4);

        // Scale font sizes
        let scaled_size = layout.scale_font(base_font_size) * user_scale;

        style.text_styles.insert(egui::TextStyle::Body, egui::FontId::proportional(scaled_size));
        style.text_styles.insert(egui::TextStyle::Button, egui::FontId::proportional(scaled_size));
        style
            .text_styles
            .insert(egui::TextStyle::Heading, egui::FontId::proportional(scaled_size * 1.4));
        style
            .text_styles
            .insert(egui::TextStyle::Small, egui::FontId::proportional(scaled_size * 0.85));

        // Scale spacing
        let spacing_scale = (layout.scale_font(1.0) / 14.0) * user_scale; // Normalize scale factor
        style.spacing.item_spacing = egui::vec2(8.0, 6.0) * spacing_scale;
        style.spacing.button_padding = egui::vec2(8.0, 4.0) * spacing_scale;

        ctx.set_global_style(style);
    }

    /// Take all pending actions and clear the list
    pub fn take_actions(&mut self) -> Vec<UIAction> {
        std::mem::take(&mut self.actions)
    }

    /// Initialize the icon manager with the egui context
    pub fn initialize_icons(&mut self, ctx: &egui::Context, assets_dir: &std::path::Path) {
        if self.icon_manager.is_none() {
            self.icon_manager = Some(icons::IconManager::new(ctx, assets_dir, 64));
        }
    }

    /// Render the icon demo panel
    pub fn render_icon_demo(&mut self, ctx: &egui::Context) {
        self.icon_demo_panel.ui(ctx, self.icon_manager.as_ref(), &self.i18n);
    }

    /// Toggle icon demo panel visibility
    pub fn toggle_icon_demo(&mut self) {
        self.icon_demo_panel.visible = !self.icon_demo_panel.visible;
    }

    /// Render the media browser as left side panel
    #[allow(deprecated)]
    pub fn render_media_browser(&mut self, ctx: &egui::Context) {
        if !self.show_media_browser {
            return;
        }

        egui::Panel::left("media_browser_panel")
            .resizable(true)
            .default_size(280.0)
            .min_size(200.0)
            .max_size(400.0)
            .frame(crate::widgets::panel::cyber_panel_frame(&ctx.global_style()))
            .show(ctx, |ui: &mut egui::Ui| {
                crate::widgets::panel::render_panel_header(
                    ui,
                    &self.i18n.t("panel-media-browser"),
                    |ui| {
                        if ui.button("✕").on_hover_text("Close Media Browser").clicked() {
                            self.show_media_browser = false;
                        }
                    },
                );

                egui::Frame::default().inner_margin(egui::Margin::symmetric(8, 8)).show(ui, |ui| {
                    let _ = self.media_browser.ui(ui, &self.i18n, self.icon_manager.as_ref());
                });
            });
    }

    /// Render the right-side inspector panel (docked)
    pub fn render_inspector(
        &mut self,
        ui: &mut egui::Ui,
        module_manager: &mut vorce_core::module::ModuleManager,
        layer_manager: &vorce_core::LayerManager,
        output_manager: &vorce_core::OutputManager,
        mapping_manager: &vorce_core::MappingManager,
    ) {
        if !self.show_inspector {
            return;
        }

        // Determine context priority: Module > Layer > Output
        let mut context = crate::panels::inspector::InspectorContext::None;
        let mut module_part_snapshot = None;

        // 1. Module Selection
        if self.show_module_canvas {
            if let Some(module_id) = self.module_canvas.active_module_id {
                // Collect shared media IDs before borrowing module mutably from manager
                let shared_media_ids: Vec<String> =
                    module_manager.shared_media.items.keys().cloned().collect();

                if let Some(part_id) = self.module_canvas.get_selected_part_id() {
                    module_part_snapshot =
                        module_manager.get_module(module_id).and_then(|module| {
                            module
                                .parts
                                .iter()
                                .find(|part| part.id == part_id)
                                .cloned()
                                .map(|part| (module_id, part_id, part))
                        });

                    if let Some(module) = module_manager.get_module_mut(module_id) {
                        context = crate::panels::inspector::InspectorContext::Module {
                            canvas: &mut self.module_canvas,
                            module,
                            part_id,
                            shared_media_ids,
                        };
                    }
                }
            }
        }

        // 2. Layer Selection (if not in module mode)
        if matches!(context, crate::panels::inspector::InspectorContext::None) {
            if let Some(id) = self.selected_layer_id {
                if let Some(layer) = layer_manager.get_layer(id) {
                    let index = layer_manager.layers().iter().position(|l| l.id == id).unwrap_or(0);

                    let first_mapping = layer
                        .mapping_ids
                        .first()
                        .and_then(|&mapping_id| mapping_manager.get_mapping(mapping_id));

                    context = crate::panels::inspector::InspectorContext::Layer {
                        layer,
                        transform: &layer.transform,
                        index,
                        first_mapping,
                    };
                }
            }
        }

        // 3. Output Selection
        if matches!(context, crate::panels::inspector::InspectorContext::None) {
            if let Some(id) = self.selected_output_id {
                if let Some(output) = output_manager.get_output(id) {
                    context = crate::panels::inspector::InspectorContext::Output(output);
                }
            }
        }

        let action = self.inspector_panel.show(ui, context, &self.i18n, &mut self.actions);

        if let Some((module_id, part_id, before_part)) = module_part_snapshot {
            let mut inspector_changed = false;
            if let Some(module) = module_manager.get_module_mut(module_id) {
                if let Some(after_part) =
                    module.parts.iter().find(|part| part.id == part_id).cloned()
                {
                    if after_part != before_part {
                        module.update_part_sockets(part_id);
                        inspector_changed = true;
                    }
                }
            }
            if inspector_changed {
                module_manager.mark_dirty();
            }
        }

        if let Some(action) = action {
            match action {
                crate::panels::inspector::InspectorAction::UpdateOpacity(id, val) => {
                    self.actions.push(crate::UIAction::SetLayerOpacity(id, val));
                }
                crate::panels::inspector::InspectorAction::UpdateTransform(id, transform) => {
                    self.actions.push(crate::UIAction::SetLayerTransform(id, transform));
                }
                crate::panels::inspector::InspectorAction::UpdateMappingMesh(id, mesh) => {
                    self.actions.push(crate::UIAction::UpdateMappingMesh(id, mesh));
                }
                crate::panels::inspector::InspectorAction::RequestClose => {
                    self.show_inspector = false;
                    self.user_config.show_inspector = false;
                    let _ = self.user_config.save();
                }
            }
        }
    }

    /// Helper for Global MIDI Learn (Way 1)
    /// Call this after adding a widget to enable hover-based learning
    pub fn midi_learn_helper(
        ui: &mut egui::Ui,
        response: &egui::Response,
        target: ControlTarget,
        is_learning: bool,
        last_active_element: Option<&String>,
        last_active_time: Option<std::time::Instant>,
        actions: &mut Vec<UIAction>,
    ) {
        if !is_learning {
            return;
        }

        if response.hovered() {
            ui.ctx().set_cursor_icon(egui::CursorIcon::Crosshair);
            let rect = response.rect;

            // Visual indicator (Pulse yellow)
            let time = ui.input(|i| i.time);
            let alpha = (time * 5.0).sin().abs() * 0.5 + 0.5;
            let color = egui::Color32::YELLOW.linear_multiply(alpha as f32);
            ui.painter().rect_stroke(
                rect.expand(2.0),
                4.0,
                egui::Stroke::new(2.0, color),
                egui::StrokeKind::Middle,
            );

            // Check for recent MIDI activity (last 0.5s)
            if let Some(last_time) = last_active_time {
                if last_time.elapsed().as_secs_f32() < 0.2 {
                    // Short window to avoid accidental assignment
                    if let Some(element_id) = last_active_element {
                        // Action!
                        actions.push(UIAction::SetMidiAssignment(
                            element_id.clone(),
                            target.to_id_string(),
                        ));

                        // Feedback: Flash Green
                        ui.painter().rect_filled(
                            rect.expand(2.0),
                            4.0,
                            egui::Color32::GREEN.linear_multiply(0.5),
                        );

                        // Log
                        tracing::info!("Global Learn Request: {} -> {}", element_id, target.name());
                    }
                }
            }
        }
    }

    /// Render Node Editor Window
    pub fn render_node_editor(&mut self, ctx: &egui::Context) {
        if !self.show_shader_graph {
            return;
        }

        let mut open = self.show_shader_graph;
        egui::Window::new(self.i18n.t("panel-node-editor"))
            .default_size([800.0, 600.0])
            .resizable(true)
            .vscroll(false) // Canvas handles panning
            .open(&mut open)
            .show(ctx, |ui: &mut egui::Ui| {
                if let Some(action) = self.node_editor_panel.ui(ui, &self.i18n) {
                    self.actions.push(UIAction::NodeAction(action));
                }
            });
        self.show_shader_graph = open;
    }
}
