use super::super::mesh;
use super::super::state::ModuleCanvas;
use super::capabilities;
use egui::Ui;
use vorce_core::module::{HueMappingMode, ModulePartId, OutputType};

/// Renders the hue entertainment area selection UI.
pub fn render_hue_area_selection(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    bridge_ip: &str,
    username: &str,
    entertainment_area: &mut String,
    lamp_positions: &mut std::collections::HashMap<String, (f32, f32)>,
) {
    if !username.is_empty() {
        ui.separator();
        if let Some(rx) = &canvas.hue_groups_rx {
            if let Ok(result) = rx.try_recv() {
                canvas.hue_groups_rx = None;
                match result {
                    Ok(groups) => canvas.hue_groups = Some(groups),
                    Err(e) => {
                        canvas.hue_status_message = Some(format!("Failed to fetch areas: {}", e))
                    }
                }
            } else {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Fetching areas...");
                });
            }
        }

        if ui.button("🔄 Fetch Areas").clicked() {
            let (tx, rx) = std::sync::mpsc::channel();
            canvas.hue_groups_rx = Some(rx);
            let bridge_ip = bridge_ip.to_owned();
            let username = username.to_owned();

            #[cfg(feature = "tokio")]
            {
                tokio::spawn(async move {
                    let config = vorce_control::hue::models::HueConfig {
                        bridge_ip,
                        username,
                        client_key: String::new(),
                        application_id: String::new(),
                        entertainment_group_id: String::new(),
                    };
                    let result = vorce_control::hue::api::groups::get_entertainment_groups(&config)
                        .await
                        .map_err(|e| e.to_string());
                    let _ = tx.send(result);
                });
            }
            #[cfg(not(feature = "tokio"))]
            {
                let _ = tx;
                let _ = bridge_ip;
                let _ = username;
            }
        }

        if let Some(groups) = &canvas.hue_groups {
            if groups.is_empty() {
                ui.label("No entertainment areas found.");
            } else {
                // Find the name of the currently selected area, if any
                let mut selected_name = "Select Area...".to_string();
                for group in groups {
                    if group.id == *entertainment_area {
                        selected_name = group.name.clone();
                        break;
                    }
                }

                egui::ComboBox::from_id_salt("hue_area_select")
                    .selected_text(selected_name)
                    .show_ui(ui, |ui| {
                        for group in groups {
                            if ui
                                .selectable_value(entertainment_area, group.id.clone(), &group.name)
                                .clicked()
                            {
                                *lamp_positions = group
                                    .lights
                                    .iter()
                                    .map(|l| (l.id.clone(), (l.x as f32, l.y as f32)))
                                    .collect();
                            }
                        }
                    });
            }
        }
    }
}

pub fn render_hue_bridge_discovery(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    current_ip: &mut String,
) {
    if ui.button("🔍 Discover Bridges").clicked() {
        let (tx, rx) = std::sync::mpsc::channel();
        canvas.hue_discovery_rx = Some(rx);
        // Spawn async task
        #[cfg(feature = "tokio")]
        {
            canvas.hue_status_message = Some("Searching...".to_string());
            let task = async move {
                let result = vorce_control::hue::api::discovery::discover_bridges()
                    .await
                    .map_err(|e| e.to_string());
                let _ = tx.send(result);
            };
            tokio::spawn(task);
        }
        #[cfg(not(feature = "tokio"))]
        {
            let _ = tx;
            canvas.hue_status_message = Some("Async runtime not available".to_string());
        }
    }

    if !canvas.hue_bridges.is_empty() {
        ui.separator();
        ui.label("Select Bridge:");
        for bridge in &canvas.hue_bridges {
            if ui.button(format!("{} ({})", bridge.id, bridge.ip)).clicked() {
                *current_ip = bridge.ip.clone();
            }
        }
    }
}

/// Renders the configuration UI for a `ModulePartType::Output`.
pub fn render_output_ui(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    output: &mut OutputType,
    _part_id: ModulePartId,
    _actions: &mut Vec<crate::action::UIAction>,
) {
    ui.label("Output:");
    match output {
        OutputType::Projector {
            id,
            name,
            hide_cursor,
            target_screen,
            show_in_preview_panel,
            extra_preview_window,
            output_width,
            output_height,
            output_fps,
            ndi_enabled: _ndi_enabled,
            ndi_stream_name: _ndi_stream_name,
            ..
        } => {
            ui.label("📽️ Projector Output");

            // Output ID selection
            ui.horizontal(|ui| {
                ui.label("Output #:");
                ui.add(egui::DragValue::new(id).range(1..=8));
            });

            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(name);
            });

            ui.separator();
            ui.label("🖥️ Window Settings:");

            // Target screen selection
            ui.horizontal(|ui| {
                ui.label("Target Screen:");
                egui::ComboBox::from_id_salt("target_screen_select")
                    .selected_text(format!("Monitor {}", target_screen))
                    .show_ui(ui, |ui| {
                        for i in 0..=3u8 {
                            let label = if i == 0 {
                                "Primary".to_string()
                            } else {
                                format!("Monitor {}", i)
                            };
                            if ui.selectable_label(*target_screen == i, &label).clicked() {
                                *target_screen = i;
                            }
                        }
                    });
            });

            ui.checkbox(hide_cursor, "🖱️ Hide Mouse Cursor");

            ui.separator();
            ui.label("⚙️ Advanced Setup:");
            ui.horizontal(|ui| {
                ui.label("Resolution:");
                ui.add(egui::DragValue::new(output_width).suffix(" px").range(1..=8192));
                ui.label("x");
                ui.add(egui::DragValue::new(output_height).suffix(" px").range(1..=8192));
            });
            ui.horizontal(|ui| {
                ui.label("Target FPS:");
                ui.add(egui::DragValue::new(output_fps).range(1.0..=240.0));
            });

            ui.separator();
            ui.label("👁️ Preview:");
            ui.checkbox(show_in_preview_panel, "Show in Preview Panel");
            ui.add_enabled_ui(false, |ui| {
                ui.checkbox(extra_preview_window, "Extra Preview Window");
            });
            capabilities::render_unsupported_warning(
                ui,
                "Dedicated preview windows are not implemented yet. Use the Preview Panel instead.",
            );

            ui.separator();
            ui.label("\u{1F4E1} NDI Broadcast");
            #[cfg(feature = "ndi")]
            {
                let supported = capabilities::is_output_type_enum_supported(true, false, false);
                if !supported {
                    #[cfg(target_os = "macos")]
                    capabilities::render_unsupported_warning(
                        ui,
                        "NDI Output is experimental/unavailable on macOS currently.",
                    );
                    #[cfg(not(target_os = "macos"))]
                    capabilities::render_unsupported_warning(
                        ui,
                        "[Experimental] NDI Output has no active runtime path currently.",
                    );
                }
                ui.add_enabled_ui(supported, |ui| {
                    ui.checkbox(_ndi_enabled, "Enable NDI Output");
                    if *_ndi_enabled {
                        ui.horizontal(|ui| {
                            ui.label("Stream Name:");
                            ui.text_edit_singleline(_ndi_stream_name);
                        });
                        if _ndi_stream_name.is_empty() {
                            ui.small(format!("Default: {}", name));
                        }
                    }
                });
            }
            #[cfg(not(feature = "ndi"))]
            {
                ui.label("NDI feature disabled in build");
            }
        }
        #[cfg(feature = "ndi")]
        OutputType::NdiOutput { name } => {
            ui.label("\u{1F4E1} NDI Output Configuration");
            ui.separator();
            ui.horizontal(|ui| {
                ui.label("Stream Name:");
                ui.text_edit_singleline(name);
            });
            ui.separator();
            ui.label("⚙️ Runtime Status");

            // Process incoming status results
            if let Some(rx) = canvas.ndi_status_rx.get(&_part_id) {
                if let Ok(status) = rx.try_recv() {
                    canvas.ndi_sender_status.insert(_part_id, status);
                    canvas.ndi_status_rx.remove(&_part_id);
                }
            }

            if let Some(status) = canvas.ndi_sender_status.get(&_part_id) {
                match status {
                    Some(frames) => {
                        ui.label(
                            egui::RichText::new(format!("🟢 Running (Sent frames: {})", frames))
                                .color(crate::theme::colors::SUCCESS_COLOR),
                        );
                    }
                    None => {
                        ui.label(
                            egui::RichText::new("🟡 Waiting for runtime...")
                                .color(crate::theme::colors::WARN_COLOR),
                        );
                    }
                }
            } else {
                ui.label("Status: Unknown");
            }

            if ui.button("🔄 Refresh Status").clicked() {
                let (tx, rx) = crossbeam_channel::unbounded();
                canvas.ndi_status_rx.insert(_part_id, rx);
                _actions.push(crate::action::UIAction::GetNdiSenderStatus(_part_id, tx));
            }
        }
        #[cfg(not(feature = "ndi"))]
        OutputType::NdiOutput { .. } => {
            ui.label("\u{1F4E1} NDI Output (Feature Disabled)");
            crate::editors::module_canvas::inspector::capabilities::render_unsupported_warning(
                ui,
                "NDI feature is disabled in this build.",
            );
        }
        #[cfg(target_os = "windows")]
        OutputType::Spout { name } => {
            ui.label("\u{1F6B0} Spout Output");
            ui.horizontal(|ui| {
                ui.label("Stream Name:");
                ui.text_edit_singleline(name);
            });
        }
        OutputType::Hue {
            bridge_ip,
            username,
            client_key: _client_key,
            entertainment_area,
            lamp_positions,
            mapping_mode,
        } => {
            ui.label("\u{1F4A1} Philips Hue Entertainment");
            ui.separator();

            // --- Tabs for Hue configuration ---
            ui.collapsing("⚙️ Setup (Bridge & Pairing)", |ui| {
                // Discovery status
                if let Some(msg) = &canvas.hue_status_message {
                    ui.label(format!("Status: {}", msg));
                }

                // Handle discovery results
                if let Some(rx) = &canvas.hue_discovery_rx {
                    if let Ok(result) = rx.try_recv() {
                        canvas.hue_discovery_rx = None;
                        // Explicit type annotation for the result to help inference
                        let result: Result<
                            Vec<vorce_control::hue::api::discovery::DiscoveredBridge>,
                            _,
                        > = result;
                        match result {
                            Ok(bridges) => {
                                canvas.hue_bridges = bridges;
                                canvas.hue_status_message =
                                    Some(format!("Found {} bridges", canvas.hue_bridges.len()));
                            }
                            Err(e) => {
                                canvas.hue_status_message =
                                    Some(format!("Discovery failed: {}", e));
                            }
                        }
                    } else {
                        ui.horizontal(|ui| {
                            ui.spinner();
                            ui.label("Searching for bridges...");
                        });
                    }
                }

                // Using a block to allow attributes on expression
                // Hue Discovery Logic extracted to method to satisfy rustfmt
                render_hue_bridge_discovery(canvas, ui, bridge_ip);

                ui.separator();
                ui.label("Manual IP:");
                ui.text_edit_singleline(bridge_ip);

                // Pairing (Requires bridge button press)
                if ui
                    .button("\u{1F517} Pair with Bridge")
                    .on_hover_text("Press button on Bridge then click this")
                    .clicked()
                {
                    let (tx, rx) = std::sync::mpsc::channel();
                    canvas.hue_pairing_rx = Some(rx);
                    let ip = bridge_ip.clone();

                    #[cfg(feature = "tokio")]
                    {
                        canvas.hue_status_message =
                            Some("Pairing... (Press Bridge Button)".to_string());
                        let task = async move {
                            let result = vorce_control::hue::api::client::HueClient::register_user(
                                &ip, "Vorce",
                            )
                            .await
                            .map_err(|e| e.to_string());
                            let _ = tx.send(result);
                        };
                        tokio::spawn(task);
                    }
                    #[cfg(not(feature = "tokio"))]
                    {
                        let _ = tx;
                        let _ = ip;
                        canvas.hue_status_message = Some("Async runtime not available".to_string());
                    }
                }

                // Handle pairing results
                if let Some(rx) = &canvas.hue_pairing_rx {
                    if let Ok(result) = rx.try_recv() {
                        canvas.hue_pairing_rx = None;
                        match result {
                            Ok(config) => {
                                *username = config.username;
                                *_client_key = config.client_key;
                                canvas.hue_status_message = Some("Pairing Successful!".to_string());
                            }
                            Err(e) => {
                                canvas.hue_status_message = Some(format!("Pairing failed: {}", e));
                            }
                        }
                    }
                }

                if !username.is_empty() {
                    ui.label("\u{2705} Paired");
                    // ui.label(format!("User: {}", username)); // Keep secret?
                } else {
                    ui.label("❌ Not Paired");
                }
            });

            ui.collapsing("\u{1F3AD} Area & Mode", |ui| {
                ui.label("Entertainment Area:");
                ui.text_edit_singleline(entertainment_area);

                render_hue_area_selection(
                    canvas,
                    ui,
                    bridge_ip,
                    username,
                    entertainment_area,
                    lamp_positions,
                );

                ui.separator();
                ui.label("Mapping Mode:");
                ui.radio_value(mapping_mode, HueMappingMode::Ambient, "Ambient (Average Color)");
                ui.radio_value(mapping_mode, HueMappingMode::Spatial, "Spatial (2D Map)");
                ui.radio_value(mapping_mode, HueMappingMode::Trigger, "Trigger (Strobe/Pulse)");
            });

            if *mapping_mode == HueMappingMode::Spatial {
                ui.collapsing("🗺️ Spatial Editor", |ui| {
                    ui.label("Position lamps in the virtual room:");
                    // Render 2D room editor
                    mesh::render_hue_spatial_editor(ui, lamp_positions);
                });
            }
        }
    }
}
