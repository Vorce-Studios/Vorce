//! Playback control action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_media::LoopMode;
use vorce_ui::UIAction;

/// Handles starting playback.
pub fn handle_play(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Play = action {
        app.state.effect_animator_mut().play();
    }
}

/// Handles pausing playback.
pub fn handle_pause(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Pause = action {
        app.state.effect_animator_mut().pause();
    }
}

/// Handles stopping playback and resetting.
pub fn handle_stop(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::Stop = action {
        app.state.effect_animator_mut().stop();
    }
}

/// Handles setting playback speed.
pub fn handle_set_speed(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetSpeed(speed) = action {
        app.state.effect_animator_mut().set_speed(speed);
    }
}

/// Handles setting loop mode.
pub fn handle_set_loop_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLoopMode(mode) = action {
        let looping = match mode {
            LoopMode::Loop => true,
            LoopMode::PlayOnce => false,
        };
        app.state.effect_animator_mut().set_looping(looping);
    }
}

/// Handles timeline-specific actions.
pub fn handle_timeline_action(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::TimelineAction(tl_action) = action {
        // Timeline action implementation
    }
}
