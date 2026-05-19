use crate::app::App;

/// Renders the panel.
#[allow(deprecated)]
pub fn show(
    ctx: &egui::Context,
    app: &mut App,
    inspector_default: f32,
    compact_height: bool,
    viewport_width: f32,
    layout_locked: bool,
) {
    // 4. Right Panel: Inspector (Docked & Resizable)
    if app.ui_state.show_inspector {
        egui::SidePanel::right("right_panel")
            .resizable(!layout_locked)
            .default_width(inspector_default)
            .min_width(if compact_height { 220.0 } else { 260.0 })
            .max_width((viewport_width * 0.5).max(420.0))
            .show(ctx, |ui_obj| {
                ui_obj.horizontal(|ui| {
                    ui.heading(app.ui_state.i18n.t("inspector"));
                    if ui.small_button("✕").on_hover_text("Inspector ausblenden").clicked() {
                        app.ui_state.show_inspector = false;
                        app.ui_state.user_config.show_inspector = false;
                        let _ = app.ui_state.user_config.save();
                    }
                });

                ui_obj.separator();

                egui::ScrollArea::vertical().show(ui_obj, |ui_obj| {
                    // Render the unified Inspector
                    app.ui_state.render_inspector(
                        ui_obj,
                        std::sync::Arc::make_mut(&mut app.state.module_manager),
                        &app.state.layer_manager,
                        &app.state.output_manager,
                        &app.state.mapping_manager,
                    );

                    // Legacy panels (can be toggled separately or integrated)
                    if app.ui_state.show_transforms {
                        app.ui_state.transform_panel.render(ctx, &app.ui_state.i18n);
                    }

                    // Effect chain integrated into inspector side
                    egui::TopBottomPanel::bottom("inspector_effect_chain_split")
                        .resizable(true)
                        .default_height(if compact_height { 180.0 } else { 240.0 })
                        .min_height(120.0)
                        .show_inside(ui_obj, |_ui| {
                            app.ui_state.effect_chain_panel.ui(
                                ctx,
                                &app.ui_state.i18n,
                                app.ui_state.icon_manager.as_ref(),
                                Some(&mut app.recent_effect_configs),
                            );
                        });
                });
            });
    }
}
