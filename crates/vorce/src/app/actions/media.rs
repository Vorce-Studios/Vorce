//! Media loading and playback command action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Handles picking a media file from disk.
pub fn handle_pick_media_file(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::PickMediaFile(module_id, part_id, default_path) = action {
        if let Some(path) = rfd::FileDialog::new()
            .add_filter("Videos", &["mp4", "mov", "mkv", "avi", "webm"])
            .add_filter("Images", &["png", "jpg", "jpeg", "gif", "bmp"])
            .pick_file()
        {
            let path_str = path.to_string_lossy().to_string();
            // TODO: Logic to update module or paint based on module_id/part_id
            app.state.dirty = true;
        }
    }
}

/// Handles setting a media file path for a layer.
pub fn handle_set_media_file(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMediaFile(module_id, part_id, path) = action {
        // TODO: Logic to update module or paint based on module_id/part_id
        app.state.dirty = true;
    }
}

/// Handles sending a media command to a part.
pub fn handle_media_command(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::MediaCommand(part_id, cmd) = action {
        // Implementation for part-specific media commands
    }
}

/// Handles manual triggering of media.
pub fn handle_manual_trigger(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::ManualTrigger(module_id, part_id) = action {
        // Manual trigger implementation
    }
}
