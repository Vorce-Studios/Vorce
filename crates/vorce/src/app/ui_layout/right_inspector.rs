use crate::app::App;

#[allow(deprecated)]
pub fn render(
    ctx: &egui::Context,
    app: &mut App,
    compact_height: bool,
    layout_locked: bool,
    inspector_default: f32,
    viewport_width: f32,
) {
    if app.ui_state.show_inspector {
        egui::Panel::right("right_panel")
            .resizable(!layout_locked)
            .default_size(inspector_default)
            .min_size(if compact_height { 220.0 } else { 260.0 })
            .max_size((viewport_width * 0.5).max(420.0))
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
                    egui::Panel::bottom("inspector_effect_chain_split")
                        .resizable(true)
                        .default_size(if compact_height { 180.0 } else { 240.0 })
                        .min_size(120.0)
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
