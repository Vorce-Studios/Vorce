//! Application settings action handlers.

#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use tracing::info;
use vorce_ui::UIAction;

/// Handles selecting the audio output device.
pub fn handle_select_audio_device(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SelectAudioDevice(device) = action {
        app.ui_state.user_config.selected_audio_device = Some(device);
        let _ = app.ui_state.user_config.save();
        app.state.dirty = true;
    }
}

/// Handles updating the audio configuration.
pub fn handle_update_audio_config(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::UpdateAudioConfig(config) = action {
        app.state.audio_config = config;
        app.state.dirty = true;
    }
}

/// Handles setting the target application FPS.
pub fn handle_set_target_fps(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetTargetFps(fps) = action {
        app.ui_state.user_config.target_fps = Some(fps);
        let _ = app.ui_state.user_config.save();
    }
}

/// Handles setting the vertical sync mode.
pub fn handle_set_vsync_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetVsyncMode(mode) = action {
        app.ui_state.user_config.vsync_mode = mode;
        let _ = app.ui_state.user_config.save();
    }
}

/// Handles setting the preferred GPU.
pub fn handle_set_preferred_gpu(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetPreferredGpu(adapter_name) = action {
        app.ui_state.user_config.preferred_gpu = adapter_name;
        let _ = app.ui_state.user_config.save();
    }
}

/// Handles setting the application language/locale.
pub fn handle_set_language(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLanguage(lang) = action {
        app.ui_state.i18n.set_locale(&lang);
        app.ui_state.user_config.language = lang;
        let _ = app.ui_state.user_config.save();
        info!("Language set to: {}", app.ui_state.user_config.language);
    }
}

/// Handles setting the audio meter visual style.
pub fn handle_set_meter_style(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMeterStyle(style) = action {
        app.ui_state.user_config.meter_style = style;
        let _ = app.ui_state.user_config.save();
    }
}
