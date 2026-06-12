use crate::app::App;
use vorce_ui as ui;

mod central_canvas;
mod left_sidebar;
mod overlays;
mod right_inspector;
mod startup;
mod timeline;
mod toolbar;

/// Main UI orchestration function.
/// Renders the entire application UI layout using egui.
#[allow(deprecated)]
pub fn show(ctx: &egui::Context, app: &mut App) {
    app.ui_state.update_responsive_styles(ctx);

    let viewport_rect = ctx.content_rect();
    let viewport_width = viewport_rect.width();
    let viewport_height = viewport_rect.height();
    let compact_height = viewport_height < 760.0;

    let active_layout = app.ui_state.user_config.active_layout().cloned();
    let layout_sizes = active_layout.as_ref().map(|layout| layout.panel_sizes).unwrap_or_default();
    let layout_locked = active_layout.as_ref().map(|layout| layout.lock_layout).unwrap_or(false);

    let sidebar_default = if layout_sizes.left_sidebar_width > 0.0 {
        layout_sizes.left_sidebar_width
    } else {
        (viewport_width * 0.2).clamp(240.0, 420.0)
    }
    .clamp(220.0, (viewport_width * 0.45).max(340.0));

    let inspector_default = if layout_sizes.inspector_width > 0.0 {
        layout_sizes.inspector_width
    } else {
        (viewport_width * 0.24).clamp(260.0, 520.0)
    }
    .clamp(260.0, (viewport_width * 0.5).max(420.0));

    let timeline_default_height = if layout_sizes.timeline_height > 0.0 {
        layout_sizes.timeline_height
    } else if compact_height {
        (viewport_height * 0.22).clamp(90.0, 150.0)
    } else {
        (viewport_height * 0.26).clamp(140.0, 300.0)
    }
    .clamp(100.0, 500.0);

    // 1. Global Menu Bar (Top-most)
    let menu_actions = ui::view::menu_bar::show(ctx, &mut app.ui_state);
    for action in menu_actions {
        app.ui_state.actions.push(action);
    }

    // 2. Toolbar
    toolbar::render(ctx, app, compact_height, layout_locked);

    // 3. Left Panel: Sidebar
    left_sidebar::render(ctx, app, compact_height, layout_locked, sidebar_default, viewport_width);

    // 4. Right Panel: Inspector
    right_inspector::render(
        ctx,
        app,
        compact_height,
        layout_locked,
        inspector_default,
        viewport_width,
    );

    // 5. Bottom Panel: Timeline
    timeline::render(ctx, app, compact_height, layout_locked, timeline_default_height);

    // 6. Floating Windows / 8. Overlays
    overlays::render(ctx, app);

    // 7. Central Panel: Module Canvas
    central_canvas::render(ctx, app);
}
