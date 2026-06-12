use super::startup::render_startup_animation_overlay;
use crate::app::App;

pub fn render(ctx: &egui::Context, app: &mut App) {
    // 6. Floating Windows / Overlays
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

    // 8. Overlays (Shader Graph, Audio, MIDI, Startup)
    render_startup_animation_overlay(ctx, app);

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
