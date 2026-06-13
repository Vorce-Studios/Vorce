#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use std::path::PathBuf;
use vorce_mcp::McpAction;
use vorce_ui::UIAction;

/// Picks a media file either from a pre-specified path string or by opening a file dialog.
pub fn handle_pick_media_file(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::PickMediaFile(module_id, part_id, path_str) = action {
        app.ui_state.module_canvas.active_module_id = Some(module_id);
        app.ui_state.module_canvas.editing_part_id = Some(part_id);
        if !path_str.is_empty() {
            let _ = app.action_sender.send(McpAction::SetModuleSourcePath(
                module_id,
                part_id,
                std::path::PathBuf::from(path_str),
            ));
        } else {
            let sender = app.action_sender.clone();
            app.tokio_runtime.spawn(async move {
                if let Some(handle) = rfd::AsyncFileDialog::new()
                    .add_filter(
                        "Media",
                        &["mp4", "mov", "avi", "mkv", "webm", "gif", "png", "jpg", "jpeg"],
                    )
                    .pick_file()
                    .await
                {
                    let path = handle.path().to_path_buf();
                    let _ = sender.send(McpAction::SetModuleSourcePath(module_id, part_id, path));
                }
            });
        }
    }
}

/// Directly sets the media file path for a specific module part.
pub fn handle_set_media_file(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMediaFile(module_id, part_id, path) = action {
        let _ = app.action_sender.send(McpAction::SetModuleSourcePath(
            module_id,
            part_id,
            PathBuf::from(path),
        ));
    }
}

/// Routes a media playback command (e.g. play, pause, seek) to a specific module part.
pub fn handle_media_command(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::MediaCommand(part_id, command) = action {
        app.ui_state.module_canvas.pending_playback_commands.push((part_id, command));
    }
}

/// Manually triggers evaluation of a specific node by its ID.
pub fn handle_manual_trigger(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ManualTrigger(_module_id, part_id) = action {
        app.module_evaluator.trigger_node(part_id);
    }
}
