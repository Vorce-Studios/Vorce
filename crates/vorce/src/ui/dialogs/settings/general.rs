use egui::{RichText, Ui};
use vorce_ui::core::config::{AppLogLevel, ToolbarMetricMode};
use vorce_ui::UIAction;

use crate::ui::dialogs::settings::SettingsContext;

/// Rendert den Tab 'General'
pub fn render_tab(ui: &mut Ui, context: &mut SettingsContext) {
    ui.heading(RichText::new("General").color(ui.visuals().strong_text_color()));
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label(format!("{}:", context.ui_state.i18n.t("language")));
        let current_lang = context.ui_state.user_config.language.clone();
        let lang_name = if current_lang == "de" { "Deutsch" } else { "English" };
        egui::ComboBox::from_id_salt("lang_selector").selected_text(lang_name).show_ui(ui, |ui| {
            if ui.selectable_label(current_lang == "de", "Deutsch").clicked() {
                context.ui_state.actions.push(UIAction::SetLanguage("de".to_string()));
            }
            if ui.selectable_label(current_lang == "en", "English").clicked() {
                context.ui_state.actions.push(UIAction::SetLanguage("en".to_string()));
            }
        });
    });
    ui.add_space(10.0);
    ui.separator();
    ui.heading(
        RichText::new(context.ui_state.i18n.t("appearance"))
            .color(ui.visuals().strong_text_color()),
    );
    ui.add_space(4.0);
    ui.horizontal(|ui| {
        ui.label(format!("{}:", context.ui_state.i18n.t("theme")));
        let current_theme = context.ui_state.user_config.theme.theme;
        egui::ComboBox::from_id_salt("theme_selector")
            .selected_text(format!("{:?}", current_theme))
            .show_ui(ui, |ui| {
                use vorce_ui::core::theme::Theme;
                for theme in [
                    Theme::Dark,
                    Theme::Light,
                    Theme::Resolume,
                    Theme::Synthwave,
                    Theme::Cyber,
                    Theme::Midnight,
                    Theme::Purple,
                    Theme::Pink,
                    Theme::HighContrast,
                ] {
                    if ui.selectable_label(current_theme == theme, format!("{:?}", theme)).clicked()
                    {
                        context.ui_state.user_config.theme.theme = theme;
                        context.ui_state.user_config.theme.apply(ui.ctx());
                        let _ = context.ui_state.user_config.save();
                    }
                }
            });
    });

    ui.horizontal(|ui| {
        ui.label("Globaler UI-Scale:");
        let mut ui_scale = context.ui_state.user_config.ui_scale;
        if ui.add(egui::Slider::new(&mut ui_scale, 0.8..=1.4).suffix("x")).changed() {
            context.ui_state.user_config.ui_scale = ui_scale;
            let _ = context.ui_state.user_config.save();
        }
    });

    ui.horizontal(|ui| {
        ui.label("Basis-Schriftgröße:");
        let mut font_scale_percent =
            (context.ui_state.user_config.theme.font_size / 14.0 * 100.0).round() as i32;
        if ui
            .add(egui::Slider::new(&mut font_scale_percent, 80..=140).text("%").suffix("%"))
            .changed()
        {
            context.ui_state.user_config.theme.font_size =
                14.0 * (font_scale_percent as f32 / 100.0);
            context.ui_state.user_config.theme.apply(ui.ctx());
            let _ = context.ui_state.user_config.save();
        }
    });

    ui.add_space(10.0);
    ui.separator();
    ui.heading(RichText::new("Toolbar-Metriken").color(ui.visuals().strong_text_color()));
    ui.add_space(4.0);

    let mut save_needed = false;
    let metrics = &mut context.ui_state.user_config.toolbar_metrics;

    let mut metric_row = |ui: &mut egui::Ui,
                          label: &str,
                          config: &mut vorce_ui::core::config::ToolbarMetricConfig,
                          id: &str| {
        ui.horizontal(|ui| {
            save_needed |= ui.checkbox(&mut config.visible, label).changed();
            ui.add_enabled_ui(config.visible, |ui| {
                egui::ComboBox::from_id_salt(id)
                    .selected_text(match config.mode {
                        ToolbarMetricMode::Always => "Permanent",
                        ToolbarMetricMode::Hover => "Nur Hover/Popover",
                    })
                    .show_ui(ui, |ui| {
                        save_needed |= ui
                            .selectable_value(
                                &mut config.mode,
                                ToolbarMetricMode::Always,
                                "Permanent",
                            )
                            .changed();
                        save_needed |= ui
                            .selectable_value(
                                &mut config.mode,
                                ToolbarMetricMode::Hover,
                                "Nur Hover/Popover",
                            )
                            .changed();
                    });
            });
        });
    };

    metric_row(ui, "BPM (Tempo)", &mut metrics.bpm, "metric_bpm");
    metric_row(ui, "Audio Meter", &mut metrics.audio_meter, "metric_audio");
    metric_row(ui, "FPS (Frames/sec)", &mut metrics.fps, "metric_fps");
    metric_row(ui, "Frame Time", &mut metrics.frame_time, "metric_ft");
    metric_row(ui, "CPU Last", &mut metrics.cpu, "metric_cpu");
    metric_row(ui, "GPU Load", &mut metrics.gpu, "metric_gpu");
    metric_row(ui, "RAM Verbrauch", &mut metrics.ram, "metric_ram");
    metric_row(ui, "Status-Indikator", &mut metrics.status, "metric_status");

    if save_needed {
        let _ = context.ui_state.user_config.save();
    }

    ui.add_space(10.0);
    ui.separator();
    ui.heading(RichText::new("Logging").color(ui.visuals().strong_text_color()));
    ui.add_space(4.0);

    let previous_log_level = context.ui_state.user_config.log_level;
    ui.horizontal(|ui| {
        ui.label("Log-Level:");
        egui::ComboBox::from_id_salt("log_level_selector")
            .selected_text(context.ui_state.user_config.log_level.to_string())
            .show_ui(ui, |ui| {
                for level in [AppLogLevel::Info, AppLogLevel::Debug] {
                    if ui
                        .selectable_label(
                            context.ui_state.user_config.log_level == level,
                            level.to_string(),
                        )
                        .clicked()
                    {
                        context.ui_state.user_config.log_level = level;
                    }
                }
            });
    });
    if context.ui_state.user_config.log_level != previous_log_level {
        context.state.settings_mut().log_config.level =
            context.ui_state.user_config.log_level.as_str().to_string();
        context.state.dirty = true;
        let _ = context.ui_state.user_config.save();
    }
    ui.label(
        RichText::new("Hinweis: Die Log-Level-Aenderung wird nach einem App-Neustart wirksam.")
            .small()
            .weak(),
    );

    ui.add_space(10.0);
    ui.separator();
}
