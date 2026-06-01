use egui::{Context, RichText, Window};
use vorce_control::hue::controller::HueController;
use vorce_core::AppState;
use vorce_render::WgpuBackend;
use vorce_ui::AppUI;

#[cfg(feature = "midi")]
use vorce_control::midi::MidiInputHandler;

/// Audio configuration sub-dialog.
pub mod audio;
/// General configuration sub-dialog.
pub mod general;
/// Layout configuration sub-dialog.
pub mod layout;
/// Performance configuration sub-dialog.
pub mod performance;

/// Context required to render the settings window.
pub struct SettingsContext<'a> {
    /// UI State
    pub ui_state: &'a mut AppUI,
    /// App State
    pub state: &'a mut AppState,
    /// Wgpu Backend
    pub backend: &'a WgpuBackend,
    /// Hue Controller
    pub hue_controller: &'a mut HueController,
    /// MIDI Handler
    #[cfg(feature = "midi")]
    pub midi_handler: &'a mut Option<MidiInputHandler>,
    /// MIDI Ports
    #[cfg(feature = "midi")]
    pub midi_ports: &'a mut Vec<String>,
    /// Selected MIDI Port
    #[cfg(feature = "midi")]
    pub selected_midi_port: &'a mut Option<usize>,
    /// Restart Requested
    pub restart_requested: &'a mut bool,
    /// Exit Requested
    pub exit_requested: &'a mut bool,
    /// Tokio Runtime
    pub tokio_runtime: &'a tokio::runtime::Runtime,
}

/// Show settings dialog
pub fn show(ctx: &Context, mut context: SettingsContext) {
    let mut show_settings = context.ui_state.show_settings;

    Window::new(
        RichText::new(format!("⚙ {}", context.ui_state.i18n.t("settings").to_uppercase()))
            .strong()
            .color(
                #[allow(deprecated)]
                ctx.style().visuals.strong_text_color(),
            ),
    )
    .open(&mut show_settings)
    .resizable(true)
    .default_width(500.0)
    .show(ctx, |ui| {
        egui::ScrollArea::vertical().show(ui, |ui| {
            ui.style_mut().spacing.item_spacing = egui::vec2(10.0, 8.0);
            ui.style_mut().spacing.button_padding = egui::vec2(12.0, 7.0);
            ui.style_mut().spacing.interact_size = egui::vec2(30.0, 26.0);

            let tab_id = egui::Id::new("settings_active_tab");
            let mut active_tab = ctx.data_mut(|d| d.get_persisted::<usize>(tab_id).unwrap_or(0));
            ui.horizontal_wrapped(|ui| {
                ui.selectable_value(&mut active_tab, 0, "Allgemein & Theme");
                ui.selectable_value(&mut active_tab, 1, "Animation & Layout");
                ui.selectable_value(&mut active_tab, 2, "Performance");
                ui.selectable_value(&mut active_tab, 3, "Audio & System");
            });
            ctx.data_mut(|d| d.insert_persisted(tab_id, active_tab));
            ui.separator();
            ui.add_space(4.0);

            if active_tab == 0 {
                general::render_tab(ui, &mut context);
            }

            if active_tab == 1 {
                layout::render_tab(ui, &mut context);
            }

            if active_tab == 2 {
                performance::render_tab(ui, &mut context);
            }

            if active_tab == 3 {
                audio::render_tab(ui, &mut context);
            }
        });
    });
    context.ui_state.show_settings = show_settings;
}
