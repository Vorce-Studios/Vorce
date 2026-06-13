#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use tracing::info;
use vorce_ui::UIAction;

/// Configures the selected audio device for input/analysis.
pub fn handle_select_audio_device(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SelectAudioDevice(device) = action {
        app.ui_state.selected_audio_device = Some(device.clone());
        app.ui_state.user_config.selected_audio_device = Some(device.clone());
        app.state.dirty = true;
        let _ = app.ui_state.user_config.save();
        info!("Selected audio device: {:?}", app.ui_state.selected_audio_device);
    }
}

/// Updates the audio config structure and notifies the audio analyzer.
pub fn handle_update_audio_config(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::UpdateAudioConfig(cfg) = action {
        app.state.audio_config = cfg.clone();
        app.audio_analyzer.update_config(cfg);
        app.state.dirty = true;
        // Persistence fix for MF-035
        let _ = app.ui_state.user_config.save();
    }
}

/// Sets the target frames per second (FPS) limit for rendering.
pub fn handle_set_target_fps(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetTargetFps(fps) = action {
        app.ui_state.user_config.target_fps = Some(fps);
        let _ = app.ui_state.user_config.save();
        app.ui_state.target_fps = fps; // Keep runtime variable updated if necessary
    }
}

/// Updates the vsync mode on physical rendering windows.
pub fn handle_set_vsync_mode(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetVsyncMode(mode) = action {
        app.ui_state.user_config.vsync_mode = mode;
        let _ = app.ui_state.user_config.save();
        // Apply vsync right away
        app.window_manager.update_vsync_mode(&app.backend, mode);
    }
}

/// Sets the preferred GPU index/identifier for rendering backend.
pub fn handle_set_preferred_gpu(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetPreferredGpu(gpu) = action {
        app.ui_state.user_config.preferred_gpu = gpu;
        let _ = app.ui_state.user_config.save();
    }
}

/// Sets the UI locale language by its language code.
pub fn handle_set_language(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetLanguage(lang_code) = action {
        app.state.settings_mut().language = lang_code.clone();
        app.state.dirty = true;
        app.ui_state.i18n.set_locale(&lang_code);
        info!("Language switched to: {}", lang_code);
    }
}

/// Sets the rendering layout style of audio volume meters.
pub fn handle_set_meter_style(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMeterStyle(style) = action {
        app.ui_state.user_config.meter_style = style;
        app.state.dirty = true;
        let _ = app.ui_state.user_config.save();
        info!("Audio meter style switched to: {:?}", style);
    }
}
