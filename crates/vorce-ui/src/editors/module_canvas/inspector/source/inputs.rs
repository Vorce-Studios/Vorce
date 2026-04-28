// Extracted inputs module
use super::super::super::state::ModuleCanvas;
use super::super::capabilities;
use crate::action::UIAction;
use egui::Ui;
use vorce_core::module::SourceType;
use vorce_core::module::{ModuleId, ModulePartId};
pub fn render_inputs_source(
    _canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    _part_id: ModulePartId,
    _module_id: ModuleId,
    _shared_media_ids: &[String],
    _actions: &mut Vec<UIAction>,
) {
    match source {
        SourceType::LiveInput { device_id } => {
            ui.label("\u{1F4F9} Live Input");
            let supported = capabilities::is_source_type_enum_supported(false, true, false, false);
            if !supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "Live Input is currently not fully wired up to the runtime.",
                );
            }
            ui.add_enabled_ui(supported, |ui| {
                egui::Grid::new("live_input_grid").num_columns(2).spacing([10.0, 8.0]).show(
                    ui,
                    |ui| {
                        ui.label("Device ID:");
                        ui.add(egui::Slider::new(device_id, 0..=10));
                        ui.end_row();
                    },
                );
            });
        }
        #[cfg(feature = "ndi")]
        SourceType::NdiInput { source_name } => {
            ui.label("\u{1F4E1} NDI Input");
            let supported = capabilities::is_source_type_enum_supported(false, false, true, false);
            if !supported {
                capabilities::render_unsupported_warning(
                            ui,
                            "[Experimental] NDI Input has no active polling/upload path in the current runtime.",
                        );
            } else {
                capabilities::render_runtime_active_info(ui);
            }

            ui.add_enabled_ui(supported, |ui| {
                // Smart Empty State
                if source_name.is_none()
                    && canvas.ndi_sources.is_empty()
                    && canvas.ndi_discovery_rx.is_none()
                {
                    ui.vertical_centered(|ui| {
                        ui.add_space(10.0);
                        if ui
                            .add(
                                egui::Button::new("🔍 Discover Sources")
                                    .min_size(egui::vec2(150.0, 30.0)),
                            )
                            .clicked()
                        {
                            // Start async discovery
                            let (tx, rx) = std::sync::mpsc::channel();
                            canvas.ndi_discovery_rx = Some(rx);
                            vorce_io::ndi::NdiReceiver::discover_sources_async(tx);
                            canvas.ndi_sources.clear();
                            ui.ctx().request_repaint();
                        }
                        render_info_label(ui, "No NDI source selected");
                        ui.add_space(10.0);
                    });
                } else {
                    // Display current source
                    let display_name =
                        source_name.clone().unwrap_or_else(|| "Not Connected".to_string());
                    ui.label(format!("Current: {}", display_name));

                    // Discover button
                    ui.horizontal(|ui| {
                        if ui.button("🔍 Discover Sources").clicked() {
                            // Start async discovery
                            let (tx, rx) = std::sync::mpsc::channel();
                            canvas.ndi_discovery_rx = Some(rx);
                            vorce_io::ndi::NdiReceiver::discover_sources_async(tx);
                            canvas.ndi_sources.clear();
                            ui.ctx().request_repaint();
                        }

                        // Check for discovery results
                        if let Some(rx) = &canvas.ndi_discovery_rx {
                            if let Ok(sources) = rx.try_recv() {
                                canvas.ndi_sources = sources;
                                canvas.ndi_discovery_rx = None;
                            }
                        }

                        // Show spinner if discovering
                        if canvas.ndi_discovery_rx.is_some() {
                            ui.spinner();
                            ui.label("Searching...");
                        }
                    });

                    // Source selection dropdown
                    if !canvas.ndi_sources.is_empty() {
                        ui.separator();
                        ui.label("Available Sources:");

                        egui::ComboBox::from_id_salt("ndi_source_select")
                            .selected_text(display_name.clone())
                            .show_ui(ui, |ui| {
                                // Option to disconnect
                                if ui
                                    .selectable_label(source_name.is_none(), "❌ None (Disconnect)")
                                    .clicked()
                                {
                                    *source_name = None;
                                    actions.push(UIAction::DisconnectNdiSource { part_id });
                                }

                                // Available sources
                                for ndi_source in &canvas.ndi_sources {
                                    let selected = source_name.as_ref() == Some(&ndi_source.name);
                                    if ui.selectable_label(selected, &ndi_source.name).clicked() {
                                        *source_name = Some(ndi_source.name.clone());

                                        // Trigger connection action
                                        actions.push(UIAction::ConnectNdiSource {
                                            part_id,
                                            source: ndi_source.clone(),
                                        });
                                    }
                                }
                            });

                        if let Some(status) = canvas.ndi_input_status.get(&part_id) {
                            if status.connected {
                                ui.horizontal(|ui| {
                                    ui.label(egui::RichText::new("●").color(colors::MINT_ACCENT));
                                    ui.label(format!(
                                        "Connected: {}",
                                        status.source_name.as_deref().unwrap_or("Unknown")
                                    ));
                                });
                            } else {
                                ui.horizontal(|ui| {
                                    ui.label(egui::RichText::new("○").color(colors::WARN_COLOR));
                                    ui.label("Disconnected");
                                });
                            }
                        }

                        ui.label(format!("Found {} source(s)", canvas.ndi_sources.len()));
                    } else if canvas.ndi_discovery_rx.is_none() {
                        ui.label("Click 'Discover' to find NDI sources");
                    }
                }
            });
        }
        #[cfg(feature = "ndi")]
        SourceType::NdiInput { .. } => {
            ui.label("\u{1F4E1} NDI Input (Feature Disabled)");
            capabilities::render_unsupported_warning(
                ui,
                "[Experimental] NDI feature is disabled in this build.",
            );
        }
        #[cfg(target_os = "windows")]
        SourceType::SpoutInput { sender_name } => {
            ui.label("\u{1F6B0} Spout Input");
            let supported = capabilities::is_source_type_enum_supported(false, false, false, true);
            if !supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "Spout Input is currently not fully wired up to the runtime.",
                );
            }
            ui.add_enabled_ui(supported, |ui| {
                ui.horizontal(|ui| {
                    ui.label("Sender:");
                    ui.text_edit_singleline(sender_name);
                });
            });
        }
        _ => {}
    }
}
