//! App actions for media.

use crate::app::core::app_struct::App;
#[cfg(feature = "ndi")]
use crossbeam_channel::Sender;
use std::path::PathBuf;
use vorce_mcp::McpAction;
use vorce_ui::UIAction;
/// Handle UI actions
pub fn handle(app: &mut App, action: UIAction, _needs_sync: &mut bool) -> bool {
    match action {
        UIAction::Play => {
            app.state.effect_animator_mut().play();
            for handle in app.media_players.values_mut() {
                let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Play);
            }
        }
        UIAction::Pause => {
            app.state.effect_animator_mut().pause();
            for handle in app.media_players.values_mut() {
                let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Pause);
            }
        }
        UIAction::Stop => {
            app.state.effect_animator_mut().stop();
            for handle in app.media_players.values_mut() {
                let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Stop);
            }
        }
        UIAction::SetSpeed(s) => {
            app.state.effect_animator_mut().set_speed(s);
            for handle in app.media_players.values_mut() {
                let _ = handle.command_tx.send(vorce_media::PlaybackCommand::SetSpeed(s));
            }
        }
        UIAction::SetLoopMode(m) => {
            for handle in app.media_players.values_mut() {
                let _ = handle.command_tx.send(vorce_media::PlaybackCommand::SetLoopMode(m));
            }
        }
        UIAction::PickMediaFile(module_id, part_id, path_str) => {
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
                        let _ =
                            sender.send(McpAction::SetModuleSourcePath(module_id, part_id, path));
                    }
                });
            }
        }
        UIAction::SetMediaFile(module_id, part_id, path) => {
            let _ = app.action_sender.send(McpAction::SetModuleSourcePath(
                module_id,
                part_id,
                PathBuf::from(path),
            ));
        }
        UIAction::MediaCommand(part_id, command) => {
            app.ui_state.module_canvas.pending_playback_commands.push((part_id, command));
        }
        UIAction::ManualTrigger(_module_id, part_id) => {
            app.module_evaluator.trigger_node(part_id);
        }
        _ => return false,
    }
    true
}
