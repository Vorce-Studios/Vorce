use crate::app::App;
use vorce_ui as ui;

#[allow(deprecated)]
pub fn render(
    ctx: &egui::Context,
    app: &mut App,
    compact_height: bool,
    layout_locked: bool,
    sidebar_default: f32,
    viewport_width: f32,
) {
    if app.ui_state.show_left_sidebar {
        egui::Panel::left("left_sidebar_panel")
            .resizable(!layout_locked)
            .default_size(sidebar_default)
            .min_size(if compact_height { 180.0 } else { 220.0 })
            .max_size((viewport_width * 0.45).max(340.0))
            .show(ctx, |ui_obj| {
                egui::Panel::bottom("left_sidebar_preview")
                    .resizable(true)
                    .default_size(if compact_height { 120.0 } else { 180.0 })
                    .min_size(110.0)
                    .show_inside(ui_obj, |ui_obj| {
                        ui_obj.horizontal(|ui| {
                            ui.heading(app.ui_state.i18n.t("preview"));
                        });
                        use vorce_core::module::{ModulePartType, OutputType};
                        let preview_outputs = app
                            .state
                            .module_manager
                            .modules()
                            .iter()
                            .flat_map(|m| m.parts.iter())
                            .filter_map(|part| {
                                if let ModulePartType::Output(OutputType::Projector {
                                    id,
                                    name,
                                    show_in_preview_panel,
                                    ..
                                }) = &part.part_type
                                {
                                    Some(ui::OutputPreviewInfo {
                                        id: *id,
                                        name: name.clone(),
                                        show_in_panel: *show_in_preview_panel,
                                        texture_name: None,
                                        texture_id: app
                                            .output_preview_cache
                                            .get(id)
                                            .map(|(texture_id, _)| *texture_id),
                                    })
                                } else {
                                    None
                                }
                            })
                            .collect::<Vec<_>>();

                        app.ui_state.module_canvas.output_previews = preview_outputs
                            .iter()
                            .filter_map(|output| {
                                output.texture_id.map(|texture_id| (output.id, texture_id))
                            })
                            .collect();
                        if app.ui_state.show_preview_panel {
                            app.ui_state.preview_panel.update_outputs(preview_outputs);
                            app.ui_state.preview_panel.show(ui_obj);
                        }
                    });

                egui::Panel::bottom("left_sidebar_media")
                    .resizable(true)
                    .default_size(if compact_height { 160.0 } else { 240.0 })
                    .min_size(120.0)
                    .show_inside(ui_obj, |ui_obj| {
                        egui::CollapsingHeader::new(app.ui_state.i18n.t("media"))
                            .default_open(true)
                            .show(ui_obj, |ui| {
                                if app.ui_state.show_media_browser {
                                    let _ = app.ui_state.media_browser.ui(
                                        ui,
                                        &app.ui_state.i18n,
                                        app.ui_state.icon_manager.as_ref(),
                                    );
                                } else {
                                    ui.label(app.ui_state.i18n.t("media-sidebar-placeholder"));
                                }
                            });
                    });

                egui::ScrollArea::vertical().show(ui_obj, |ui_obj| {
                    egui::CollapsingHeader::new(app.ui_state.i18n.t("dashboard"))
                        .default_open(true)
                        .show(ui_obj, |ui| {
                            if let Some(dash_action) = app.ui_state.dashboard.render_contents(
                                ui,
                                &app.ui_state.i18n,
                                app.ui_state.icon_manager.as_ref(),
                            ) {
                                match dash_action {
                                    ui::view::dashboard::DashboardAction::SendCommand(cmd) => {
                                        if let Some(_module_id) = app.ui_state.module_canvas.active_module_id {
                                            if let Some(part_id) = app.ui_state.module_canvas.get_selected_part_id() {
                                                app.ui_state.actions.push(ui::UIAction::MediaCommand(part_id, cmd));
                                            }
                                        }
                                    }
                                    ui::view::dashboard::DashboardAction::ToggleAudioPanel => {
                                        app.ui_state.show_audio = !app.ui_state.show_audio;
                                    }
                                    _ => {}
                                }
                            }
                        });
                    ui_obj.separator();

                    if app.ui_state.show_master_controls {
                        egui::CollapsingHeader::new(app.ui_state.i18n.t("panel-master"))
                            .default_open(true)
                            .show(ui_obj, |ui| {
                                let mut layer_manager = std::sync::Arc::make_mut(&mut app.state.layer_manager).clone();
                                app.ui_state.render_master_controls_embedded(ui, &mut layer_manager);
                                if layer_manager != *app.state.layer_manager {
                                    *std::sync::Arc::make_mut(&mut app.state.layer_manager) = layer_manager;
                                    app.state.dirty = true;
                                }
                            });
                        ui_obj.separator();
                    }

                    egui::CollapsingHeader::new(app.ui_state.i18n.t("audio"))
                        .default_open(app.ui_state.show_audio)
                        .show(ui_obj, |ui| {
                            let analysis = app.audio_analyzer.get_latest_analysis();
                            if let Some(audio_action) = app.ui_state.audio_panel.ui(
                                ui,
                                &app.ui_state.i18n,
                                Some(&analysis),
                                &app.state.audio_config,
                                app.ui_state.user_config.meter_style,
                                &mut app.ui_state.show_audio_panel_meters,
                                &mut app.ui_state.audio_fft_mode,
                            ) {
                                match audio_action {
                                    ui::panels::audio_panel::AudioPanelAction::ConfigChanged(cfg) => {
                                        app.ui_state.actions.push(ui::UIAction::UpdateAudioConfig(cfg));
                                    }
                                    ui::panels::audio_panel::AudioPanelAction::MeterStyleChanged(style) => {
                                        app.ui_state.actions.push(ui::UIAction::SetMeterStyle(style));
                                    }
                                }
                            }
                        });
                });
            });
    }
}
