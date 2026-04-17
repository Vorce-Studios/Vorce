use crate::midi::{MappingCurve, MidiMessageTemplate, ProfileMapping};
use crate::target::ControlTarget;

/// Helper: Create CC mapping
pub(crate) fn cc_mapping(
    channel: u8,
    controller: u8,
    label: &str,
    target: ControlTarget,
) -> ProfileMapping {
    ProfileMapping {
        message_template: MidiMessageTemplate::ControlChange { channel, controller },
        target,
        min_value: 0.0,
        max_value: 1.0,
        curve: MappingCurve::Linear,
        label: label.to_string(),
    }
}

/// Helper: Create Note mapping
pub(crate) fn note_mapping(
    channel: u8,
    note: u8,
    label: &str,
    target: ControlTarget,
) -> ProfileMapping {
    ProfileMapping {
        message_template: MidiMessageTemplate::Note { channel, note },
        target,
        min_value: 0.0,
        max_value: 1.0,
        curve: MappingCurve::Linear,
        label: label.to_string(),
    }
}
