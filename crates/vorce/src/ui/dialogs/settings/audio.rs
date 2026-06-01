use egui::{RichText, Ui};
use vorce_ui::UIAction;

use crate::ui::dialogs::settings::SettingsContext;

/// Rendert den Tab 'Audio'
pub fn render_tab(ui: &mut Ui, context: &mut SettingsContext) {
    ui.heading(
        RichText::new(context.ui_state.i18n.t("audio")).color(ui.visuals().strong_text_color()),
    );
    if cfg!(target_os = "macos") {
        ui.add_space(8.0);
        vorce_ui::widgets::custom::render_info_label(
            ui,
            "Audio input is currently feature-gated on macOS for stability.",
        );
    }
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label(format!("{}:", context.ui_state.i18n.t("label-device")));
        let current_device = context
            .ui_state
            .selected_audio_device
            .clone()
            .unwrap_or_else(|| context.ui_state.i18n.t("no-device"));
        egui::ComboBox::from_id_salt("audio_device_selector")
            .selected_text(&current_device)
            .show_ui(ui, |ui| {
                for device in &context.ui_state.audio_devices {
                    let is_selected =
                        Some(device) == context.ui_state.selected_audio_device.as_ref();
                    ui.add_enabled_ui(!cfg!(target_os = "macos"), |ui| {
                        if ui.selectable_label(is_selected, device).clicked() {
                            context
                                .ui_state
                                .actions
                                .push(UIAction::SelectAudioDevice(device.clone()));
                        }
                    });
                }
            });
    });
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label("Sample Rate:");
        let mut sample_rate = context.state.audio_config.sample_rate;
        egui::ComboBox::from_id_salt("audio_sample_rate_selector")
            .selected_text(format!("{} Hz", sample_rate))
            .show_ui(ui, |ui| {
                for rate in [22050_u32, 44100, 48000, 96000] {
                    ui.add_enabled_ui(!cfg!(target_os = "macos"), |ui| {
                        if ui
                            .selectable_label(sample_rate == rate, format!("{} Hz", rate))
                            .clicked()
                        {
                            sample_rate = rate;
                        }
                    });
                }
            });
        if sample_rate != context.state.audio_config.sample_rate {
            let mut cfg = context.state.audio_config.clone();
            cfg.sample_rate = sample_rate;
            context.ui_state.actions.push(UIAction::UpdateAudioConfig(cfg));
        }
    });
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label("Buffer Size:");
        let mut fft_size = context.state.audio_config.fft_size;
        egui::ComboBox::from_id_salt("audio_buffer_size_selector")
            .selected_text(format!("{}", fft_size))
            .show_ui(ui, |ui| {
                for size in [256_usize, 512, 1024, 2048, 4096] {
                    ui.add_enabled_ui(!cfg!(target_os = "macos"), |ui| {
                        if ui.selectable_label(fft_size == size, format!("{}", size)).clicked() {
                            fft_size = size;
                        }
                    });
                }
            });
        if fft_size != context.state.audio_config.fft_size {
            let mut cfg = context.state.audio_config.clone();
            cfg.fft_size = fft_size;
            context.ui_state.actions.push(UIAction::UpdateAudioConfig(cfg));
        }
    });
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label("Level Meter Style:");
        let meter = context.ui_state.user_config.meter_style;
        egui::ComboBox::from_id_salt("meter_select").selected_text(format!("{:?}", meter)).show_ui(
            ui,
            |ui| {
                use vorce_ui::core::config::AudioMeterStyle;
                for style in [AudioMeterStyle::Retro, AudioMeterStyle::Digital] {
                    ui.add_enabled_ui(!cfg!(target_os = "macos"), |ui| {
                        if ui.selectable_label(meter == style, format!("{:?}", style)).clicked() {
                            context.ui_state.actions.push(UIAction::SetMeterStyle(style));
                        }
                    });
                }
            },
        );
    });
    ui.add_space(20.0);
    ui.separator();
    ui.vertical_centered(|ui| {
        if ui
            .button(
                RichText::new(context.ui_state.i18n.t("restart-app"))
                    .color(ui.visuals().error_fg_color)
                    .strong(),
            )
            .clicked()
        {
            *context.restart_requested = true;
            *context.exit_requested = true;
        }
    });
}
