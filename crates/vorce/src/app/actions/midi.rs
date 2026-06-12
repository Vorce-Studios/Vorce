#![allow(unused_variables)]
use crate::app::core::app_struct::App;
use vorce_ui::UIAction;

pub fn handle_set_midi_assignment(app: &mut App, action: UIAction, _needs_sync: &mut bool) {
    if let UIAction::SetMidiAssignment(element_id, target_id) = action {
        #[cfg(feature = "midi")]
        {
            use vorce_ui::config::MidiAssignmentTarget;
            app.ui_state
                .user_config
                .set_midi_assignment(&element_id, MidiAssignmentTarget::Vorce(target_id.clone()));
            let _ = app.ui_state.user_config.save();
            tracing::info!("MIDI Assignment set via Global Learn: {} -> {}", element_id, target_id);
        }
        #[cfg(not(feature = "midi"))]
        {
            let _ = element_id;
            let _ = target_id;
        }
    }
}
