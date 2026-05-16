use crate::{AppUI, UIAction};
use egui::{Context, Ui};

pub fn render_controls(app_ui: &mut AppUI, ctx: &Context) {
    if !app_ui.show_controls {
        return;
    }

    egui::Window::new(app_ui.i18n.t("panel-playback"))
        .default_size([320.0, 360.0])
        .frame(crate::widgets::panel::cyber_panel_frame(&ctx.global_style()))
        .show(ctx, |ui| {
            crate::widgets::panel::render_panel_header(
                ui,
                &app_ui.i18n.t("header-video-playback"),
                |_| {},
            );
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                if ui.button(app_ui.i18n.t("btn-play")).clicked() {
                    app_ui.actions.push(UIAction::Play);
                }
                if ui.button(app_ui.i18n.t("btn-pause")).clicked() {
                    app_ui.actions.push(UIAction::Pause);
                }
                if ui.button(app_ui.i18n.t("btn-stop")).clicked() {
                    app_ui.actions.push(UIAction::Stop);
                }
            });

            ui.separator();

            let old_speed = app_ui.playback_speed;
            ui.add(
                egui::Slider::new(&mut app_ui.playback_speed, 0.1..=2.0)
                    .text(app_ui.i18n.t("label-speed")),
            );
            if (app_ui.playback_speed - old_speed).abs() > 0.001 {
                app_ui.actions.push(UIAction::SetSpeed(app_ui.playback_speed));
            }

            ui.label(app_ui.i18n.t("label-mode"));
            egui::ComboBox::from_label(app_ui.i18n.t("label-mode"))
                .selected_text(match app_ui.loop_mode {
                    vorce_media::LoopMode::Loop => app_ui.i18n.t("mode-loop"),
                    vorce_media::LoopMode::PlayOnce => app_ui.i18n.t("mode-play-once"),
                })
                .show_ui(ui, |ui: &mut Ui| {
                    if ui
                        .selectable_value(
                            &mut app_ui.loop_mode,
                            vorce_media::LoopMode::Loop,
                            app_ui.i18n.t("mode-loop"),
                        )
                        .clicked()
                    {
                        app_ui.actions.push(UIAction::SetLoopMode(vorce_media::LoopMode::Loop));
                    }
                    if ui
                        .selectable_value(
                            &mut app_ui.loop_mode,
                            vorce_media::LoopMode::PlayOnce,
                            app_ui.i18n.t("mode-play-once"),
                        )
                        .clicked()
                    {
                        app_ui.actions
                            .push(UIAction::SetLoopMode(vorce_media::LoopMode::PlayOnce));
                    }
                });
        });
}
