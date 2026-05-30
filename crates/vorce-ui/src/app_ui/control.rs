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
use crate::AppUI;
use vorce_control::ControlTarget;

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

    /// Take all pending actions and clear the list
    pub fn take_actions(&mut self) -> Vec<UIAction> {
        std::mem::take(&mut self.actions)
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
            let color = ui.visuals().warn_fg_color.linear_multiply(alpha as f32);
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
                            crate::core::theme::colors::MINT_ACCENT.linear_multiply(0.5),
                        );

                        // Log
                        tracing::info!("Global Learn Request: {} -> {}", element_id, target.name());
                    }
                }
            }
        }
    }
}
