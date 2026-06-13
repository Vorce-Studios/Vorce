use crate::app::App;
use vorce_ui as ui;

#[allow(deprecated)]
pub fn render(ctx: &egui::Context, app: &mut App, compact_height: bool, layout_locked: bool) {
    if app.ui_state.show_toolbar {
        egui::Panel::top("toolbar_panel")
            .resizable(!layout_locked)
            .min_size(if compact_height { 36.0 } else { 44.0 })
            .frame(
                egui::Frame::default()
                    .fill(ctx.global_style().visuals.window_fill())
                    .inner_margin(egui::Margin::symmetric(16, 4))
                    .stroke(egui::Stroke::new(
                        1.0,
                        ctx.global_style().visuals.widgets.noninteractive.bg_stroke.color,
                    )),
            )
            .show(ctx, |ui_obj| {
                ui_obj.horizontal_wrapped(|ui_obj| {
                    if ui_obj
                        .small_button(if app.ui_state.show_left_sidebar {
                            "◀ Sidebar"
                        } else {
                            "▶ Sidebar"
                        })
                        .clicked()
                    {
                        app.ui_state.show_left_sidebar = !app.ui_state.show_left_sidebar;
                        app.ui_state.user_config.show_left_sidebar = app.ui_state.show_left_sidebar;
                        let _ = app.ui_state.user_config.save();
                    }
                    if ui_obj
                        .small_button(if app.ui_state.show_inspector {
                            "Inspector ▶"
                        } else {
                            "Inspector ◀"
                        })
                        .clicked()
                    {
                        app.ui_state.show_inspector = !app.ui_state.show_inspector;
                        app.ui_state.user_config.show_inspector = app.ui_state.show_inspector;
                        let _ = app.ui_state.user_config.save();
                    }
                    if ui_obj
                        .small_button(if app.ui_state.show_timeline {
                            "▼ Timeline"
                        } else {
                            "▲ Timeline"
                        })
                        .clicked()
                    {
                        app.ui_state.show_timeline = !app.ui_state.show_timeline;
                        app.ui_state.user_config.show_timeline = app.ui_state.show_timeline;
                        let _ = app.ui_state.user_config.save();
                    }
                    ui_obj.separator();
                    ui::view::menu_bar::toolbar::show(ui_obj, &mut app.ui_state);
                });
            });
    }
}
