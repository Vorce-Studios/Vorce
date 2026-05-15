use crate::app::App;

#[allow(deprecated, missing_docs)]
pub fn show(ctx: &egui::Context, app: &mut App) {
    if app.ui_state.show_cue_panel {
        app.ui_state.cue_panel.show(
            ctx,
            &app.control_manager,
            &app.ui_state.i18n,
            &mut app.ui_state.actions,
            app.ui_state.icon_manager.as_ref(),
        );
    }
}
