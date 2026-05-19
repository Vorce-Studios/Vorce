/// Module for bottom_panel
pub mod bottom_panel;
/// Module for central_panel
pub mod central_panel;
/// Module for left_panel
pub mod left_panel;
/// Module for right_panel
pub mod right_panel;
/// Module for startup_animation
pub mod startup_animation;
/// Module for toolbar_panel
pub mod toolbar_panel;

use crate::app::App;
use vorce_ui as ui;

/// Main UI orchestration function.
/// Renders the entire application UI layout using egui.
#[allow(deprecated)]
/// Renders the panel.
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

    toolbar_panel::show(ctx, app, compact_height, layout_locked);
    left_panel::show(ctx, app, sidebar_default, compact_height, viewport_width, layout_locked);
    right_panel::show(ctx, app, inspector_default, compact_height, viewport_width, layout_locked);
    bottom_panel::show(ctx, app, timeline_default_height, compact_height, layout_locked);

    // Cue Panel
    if app.ui_state.show_cue_panel {
        app.ui_state.cue_panel.show(
            ctx,
            &app.control_manager,
            &app.ui_state.i18n,
            &mut app.ui_state.actions,
            app.ui_state.icon_manager.as_ref(),
        );
    }

    central_panel::show(ctx, app);

    startup_animation::render_startup_animation_overlay(ctx, app);

    crate::ui::panels::output::show(
        ctx,
        crate::ui::panels::output::OutputContext {
            ui_state: &mut app.ui_state,
            state: &mut app.state,
        },
    );

    crate::ui::panels::edge_blend::show(
        ctx,
        crate::ui::panels::edge_blend::EdgeBlendContext { ui_state: &mut app.ui_state },
    );

    crate::ui::panels::mapping::show(
        ctx,
        crate::ui::panels::mapping::MappingContext {
            ui_state: &mut app.ui_state,
            state: &mut app.state,
        },
    );

    crate::ui::panels::paint::show(
        ctx,
        crate::ui::panels::paint::PaintContext {
            ui_state: &mut app.ui_state,
            state: &mut app.state,
        },
    );

    app.ui_state.render_controls(ctx);

    vorce_ui::panels::osc_panel::show_osc_panel(ctx, &mut app.ui_state, &mut app.control_manager);

    app.ui_state.oscillator_panel.render(
        ctx,
        &app.ui_state.i18n,
        &mut app.state.oscillator_config,
        app.ui_state.icon_manager.as_ref(),
    );

    let mut actions = vec![];
    let mut selected_layer = app.ui_state.selected_layer_id;
    app.ui_state.layer_panel.show(
        ctx,
        std::sync::Arc::make_mut(&mut app.state.layer_manager),
        &mut selected_layer,
        &mut actions,
        &app.ui_state.i18n,
        app.ui_state.icon_manager.as_ref(),
    );
    app.ui_state.selected_layer_id = selected_layer;
    app.ui_state.actions.extend(actions);

    if app.ui_state.show_shader_graph {
        app.ui_state.render_node_editor(ctx);
    }

    app.ui_state.controller_overlay.show(
        ctx,
        app.ui_state.show_controller_overlay,
        false,
        &mut app.ui_state.user_config,
    );

    if app.ui_state.show_about {
        crate::ui::dialogs::about::show(ctx, &mut app.ui_state.show_about);
    }

    if app.ui_state.show_settings {
        let context = crate::ui::dialogs::settings::SettingsContext {
            ui_state: &mut app.ui_state,
            state: &mut app.state,
            backend: &app.backend,
            hue_controller: &mut app.hue_controller,
            #[cfg(feature = "midi")]
            midi_handler: &mut app.midi_handler,
            #[cfg(feature = "midi")]
            midi_ports: &mut app.midi_ports,
            #[cfg(feature = "midi")]
            selected_midi_port: &mut app.selected_midi_port,
            restart_requested: &mut app.restart_requested,
            exit_requested: &mut app.exit_requested,
            tokio_runtime: &app.tokio_runtime,
        };
        crate::ui::dialogs::settings::show(ctx, context);
    }

    app.ui_state.assignment_panel.show(ctx, &app.state.assignment_manager);
    app.ui_state.shortcut_editor.show(ctx, &app.ui_state.i18n);
}
