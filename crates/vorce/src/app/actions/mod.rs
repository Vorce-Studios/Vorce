//! UI and Node action processing.

/// App actions for hue
pub mod hue;
/// App actions for layer
pub mod layer;
/// App actions for mapping
pub mod mapping;
/// App actions for master
pub mod master;
/// App actions for MCP
pub mod mcp;
/// App actions for media
pub mod media;
/// App actions for module
pub mod module;
/// App actions for node
pub mod node;
/// App actions for project
pub mod project;
/// App actions for settings
pub mod settings;

use crate::app::core::app_struct::App;
use anyhow::Result;

/// Handle global UI actions
pub fn handle_ui_actions(app: &mut App) -> Result<bool> {
    let actions = app.ui_state.take_actions();
    let mut needs_sync = false;
    let visibility_before = (
        app.ui_state.show_toolbar,
        app.ui_state.show_left_sidebar,
        app.ui_state.show_inspector,
        app.ui_state.show_timeline,
        app.ui_state.show_media_browser,
        app.ui_state.show_module_canvas,
    );

    for action in actions {
        if node::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if settings::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if project::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if media::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if mapping::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if module::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if hue::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if layer::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        if master::handle(app, action.clone(), &mut needs_sync) {
            continue;
        }
        // mcp doesn't use UIAction
        // Unhandled UIAction, or custom logic...
    }

    handle_mcp_actions(app);

    let visibility_after = (
        app.ui_state.show_toolbar,
        app.ui_state.show_left_sidebar,
        app.ui_state.show_inspector,
        app.ui_state.show_timeline,
        app.ui_state.show_media_browser,
        app.ui_state.show_module_canvas,
    );

    if visibility_before != visibility_after {
        needs_sync = true;
        app.ui_state.sync_runtime_to_active_layout();
        let _ = app.ui_state.user_config.save();
    }

    Ok(needs_sync)
}

pub use mcp::handle_mcp_actions;
