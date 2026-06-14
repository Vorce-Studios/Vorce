use super::super::state::ModuleCanvas;
use super::super::types::MediaPlaybackCommand;
use egui::Ui;
use vorce_core::module::{ModuleManager, TriggerType};

pub fn handle_playback_and_learn(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    manager: &mut ModuleManager,
) {
    if !canvas.selected_parts.is_empty()
        && !ui.memory(|m| m.focused().is_some())
        && ui.input_mut(|i| i.consume_key(egui::Modifiers::NONE, egui::Key::Space))
    {
        if let Some(module_id) = canvas.active_module_id {
            if let Some(module) = manager.get_module_mut(module_id) {
                for part_id in &canvas.selected_parts {
                    if let Some(part) = module.parts.iter().find(|p| p.id == *part_id) {
                        if let vorce_core::module::ModulePartType::Source(
                            vorce_core::module::SourceType::MediaFile { .. }
                            | vorce_core::module::SourceType::VideoUni { .. },
                        ) = &part.part_type
                        {
                            let is_playing = canvas
                                .player_info
                                .get(part_id)
                                .map(|info| info.is_playing)
                                .unwrap_or(false);

                            let command = if is_playing {
                                MediaPlaybackCommand::Pause
                            } else {
                                MediaPlaybackCommand::Play
                            };
                            canvas.pending_playback_commands.push((*part_id, command));
                        }
                    }
                }
            }
        }
    }

    if let Some((part_id, channel, cc_or_note, is_note)) = canvas.learned_midi.take() {
        let mut applied = false;
        if let Some(module_id) = canvas.active_module_id {
            if let Some(module) = manager.get_module_mut(module_id) {
                if let Some(part) = module.parts.iter_mut().find(|p| p.id == part_id) {
                    if let vorce_core::module::ModulePartType::Trigger(TriggerType::Midi {
                        channel: ref mut ch,
                        note: ref mut n,
                        ..
                    }) = part.part_type
                    {
                        *ch = channel;
                        *n = cc_or_note;
                        applied = true;
                        tracing::info!(
                            "Applied MIDI Learn: Channel={}, {}={}",
                            channel,
                            if is_note { "Note" } else { "CC" },
                            cc_or_note
                        );
                    }
                }
            }
        }
        if applied {
            manager.mark_dirty();
        }
    }
}
