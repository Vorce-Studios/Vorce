use crate::app::App;
use vorce_ui as ui;

#[allow(deprecated)]
pub fn render(ctx: &egui::Context, app: &mut App) {
    // 7. Central Panel: Module Canvas
    egui::CentralPanel::default()
        .frame(egui::Frame::default().fill(ctx.global_style().visuals.panel_fill))
        .show(ctx, |ui_obj| {
            if app.ui_state.show_module_canvas {
                app.ui_state.module_canvas.ensure_icons_loaded(ctx);

                if app.ui_state.module_canvas.active_module_id.is_none() {
                    if let Some(first_mod) = app.state.module_manager.modules().first() {
                        app.ui_state.module_canvas.active_module_id = Some(first_mod.id);
                    }
                }

                // --- Module Selector Toolbar ---
                egui::MenuBar::new().ui(ui_obj, |ui_obj| {
                    let modules: Vec<(u64, String, [f32; 4])> = app
                        .state
                        .module_manager
                        .modules()
                        .iter()
                        .map(|m| (m.id, m.name.clone(), m.color))
                        .collect();

                    if !modules.is_empty() {
                        let active_name = app
                            .ui_state
                            .module_canvas
                            .active_module_id
                            .and_then(|id| modules.iter().find(|(mid, _, _)| *mid == id))
                            .map(|(_, name, _)| name.clone())
                            .unwrap_or_else(|| "Module wählen...".to_string());

                        egui::ComboBox::from_id_salt("module_selector")
                            .selected_text(format!("📦 {}", active_name))
                            .show_ui(ui_obj, |ui_obj| {
                                for (id, name, color) in &modules {
                                    let color32 = egui::Color32::from_rgba_premultiplied(
                                        (color[0] * 255.0) as u8,
                                        (color[1] * 255.0) as u8,
                                        (color[2] * 255.0) as u8,
                                        255,
                                    );
                                    let is_selected =
                                        app.ui_state.module_canvas.active_module_id == Some(*id);
                                    let label =
                                        egui::RichText::new(format!("● {}", name)).color(color32);
                                    if ui_obj.selectable_label(is_selected, label).clicked() {
                                        app.ui_state.module_canvas.set_active_module(Some(*id));
                                    }
                                }
                            });
                        ui_obj.separator();
                    }

                    if let Some(module_id) = app.ui_state.module_canvas.active_module_id {
                        ui_obj.menu_button(
                            egui::RichText::new("➕ Hinzufügen").strong(),
                            |ui_obj| {
                                ui::editors::module_canvas::draw::render_add_node_menu_content(
                                    ui_obj,
                                    std::sync::Arc::make_mut(&mut app.state.module_manager),
                                    None,
                                    Some(module_id),
                                );
                            },
                        );
                        ui_obj.separator();
                    }

                    if ui_obj.button("💾 Speichern").clicked() {
                        app.ui_state.module_canvas.show_presets = true;
                    }
                    if ui_obj.button("🔍 Suchen").clicked() {
                        app.ui_state.module_canvas.show_search =
                            !app.ui_state.module_canvas.show_search;
                    }

                    if ui_obj.button(egui::RichText::new("➕ Neues Modul").strong()).clicked() {
                        let new_id = std::sync::Arc::make_mut(&mut app.state.module_manager)
                            .create_module("New Module".to_string());
                        app.ui_state.module_canvas.set_active_module(Some(new_id));
                    }

                    ui_obj.with_layout(
                        egui::Layout::right_to_left(egui::Align::Center),
                        |ui_obj| {
                            if ui_obj.button("Zentrieren").clicked() {
                                app.ui_state.module_canvas.pan_offset = egui::Vec2::ZERO;
                                app.ui_state.module_canvas.zoom = 1.0;
                            }
                            ui_obj.label(format!("Zoom: {:.1}x", app.ui_state.module_canvas.zoom));
                        },
                    );
                });

                app.ui_state.module_canvas.show(
                    ui_obj,
                    std::sync::Arc::make_mut(&mut app.state.module_manager),
                    &app.ui_state.i18n,
                    &mut app.ui_state.actions,
                    ui::ModuleCanvasRenderOptions::from(&app.ui_state.user_config),
                );
            } else {
                ui_obj.centered_and_justified(|ui_obj| {
                    ui_obj.label("Canvas - Module Canvas deaktiviert (View → Module Canvas)");
                });
            }
        });
}
