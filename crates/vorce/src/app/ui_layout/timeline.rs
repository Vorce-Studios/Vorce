use crate::app::App;
use vorce_ui as ui;

pub fn render(
    ctx: &egui::Context,
    app: &mut App,
    compact_height: bool,
    layout_locked: bool,
    timeline_default_height: f32,
) {
    if app.ui_state.show_timeline {
        egui::Panel::bottom("bottom_panel")
            .resizable(!layout_locked)
            .default_size(timeline_default_height)
            .min_size(if compact_height { 80.0 } else { 100.0 })
            .show(ctx, |ui_obj| {
                ui_obj.horizontal(|ui| {
                    ui.heading(app.ui_state.i18n.t("timeline"));
                    if ui.small_button("✕").on_hover_text("Timeline ausblenden").clicked() {
                        app.ui_state.show_timeline = false;
                        app.ui_state.user_config.show_timeline = false;
                        let _ = app.ui_state.user_config.save();
                    }
                });

                let state = &mut app.state;
                let animator = std::sync::Arc::make_mut(&mut state.effect_animator);
                let mut modules: Vec<ui::TimelineModule> = state
                    .module_manager
                    .modules()
                    .iter()
                    .map(|m| ui::TimelineModule {
                        id: m.id,
                        // Optimization: Borrow name string to prevent allocation overhead in UI hot loop.
                        name: &m.name,
                    })
                    .collect();
                modules.sort_by_key(|m| m.id);

                if let Some(action) = app.ui_state.timeline_panel.ui(ui_obj, animator, &modules) {
                    app.ui_state.actions.push(ui::UIAction::TimelineAction(action));
                }
            });
    }
}
