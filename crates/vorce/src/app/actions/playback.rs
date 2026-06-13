#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

/// Initiates playback for timeline animations and all active media players.
pub fn handle_play(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Play = action {
        app.state.effect_animator_mut().play();
        for handle in app.media_players.values_mut() {
            let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Play);
        }
    }
}

/// Pauses playback of timeline animations and all active media players.
pub fn handle_pause(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Pause = action {
        app.state.effect_animator_mut().pause();
        for handle in app.media_players.values_mut() {
            let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Pause);
        }
    }
}

/// Stops playback of timeline animations and resets active media players to the beginning.
pub fn handle_stop(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Stop = action {
        app.state.effect_animator_mut().stop();
        for handle in app.media_players.values_mut() {
            let _ = handle.command_tx.send(vorce_media::PlaybackCommand::Stop);
        }
    }
}

/// Sets the playback speed factor for timeline animations and active media players.
pub fn handle_set_speed(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetSpeed(s) = action {
        app.state.effect_animator_mut().set_speed(s);
        for handle in app.media_players.values_mut() {
            let _ = handle.command_tx.send(vorce_media::PlaybackCommand::SetSpeed(s));
        }
    }
}

/// Configures the loop mode for active media players.
pub fn handle_set_loop_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLoopMode(m) = action {
        for handle in app.media_players.values_mut() {
            let _ = handle.command_tx.send(vorce_media::PlaybackCommand::SetLoopMode(m));
        }
    }
}

/// Handles timeline-specific actions (e.g. seek, markers, playback commands).
pub fn handle_timeline_action(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::TimelineAction(timeline_action) = action {
        use vorce_ui::TimelineAction;
        match timeline_action {
            TimelineAction::Play => app.state.effect_animator_mut().play(),
            TimelineAction::Pause => app.state.effect_animator_mut().pause(),
            TimelineAction::Stop => app.state.effect_animator_mut().stop(),
            TimelineAction::Seek(time) => app.state.effect_animator_mut().seek(time as f64),
            TimelineAction::SelectModule(module_id) => {
                app.ui_state.module_canvas.set_active_module(Some(module_id))
            }
            TimelineAction::AddMarker(t) => {
                let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                let name = format!("Marker {:.1}s", t);
                // Simple ID generation for markers
                let id = (t * 1000.0) as u64;
                animator.add_marker(vorce_core::animation::Marker::new(id, t as f64, name));
            }
            TimelineAction::RemoveMarker(t) => {
                let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                animator.remove_marker(t as f64);
            }
            TimelineAction::ToggleMarkerPause(t) => {
                let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                animator.toggle_marker_pause(t as f64);
            }
            TimelineAction::JumpNextMarker => {
                let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                animator.jump_next_marker();
            }
            TimelineAction::JumpPrevMarker => {
                let animator = std::sync::Arc::make_mut(&mut app.state.effect_animator);
                animator.jump_prev_marker();
            }
        }
    }
}
