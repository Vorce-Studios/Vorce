use super::ecler_nuo4;
use crate::midi::profiles::ControllerProfile;
use crate::midi::MidiMessageTemplate;

#[test]
fn test_ecler_nuo4_profile() {
    let profile = ecler_nuo4();

    assert_eq!(profile.name, "Ecler NUO 4");
    assert_eq!(profile.manufacturer, "Ecler");

    // Should have exactly 89 mappings:
    // CH2: 6 CC + 2 Note = 8
    // CH3: 6 CC + 2 Note = 8
    // Crossfader: 1 CC = 1
    // Dedicated MIDI: 6 layouts × (4 CC + 4 Push Enc + 4 Switch) = 6 × 12 = 72
    // Total: 8 + 8 + 1 + 72 = 89
    assert_eq!(
        profile.mappings.len(),
        89,
        "Expected 89 mappings, got {}",
        profile.mappings.len()
    );
}

#[test]
fn test_ecler_nuo4_channel_mappings() {
    let profile = ecler_nuo4();

    // Check CH2 Gain mapping
    let ch2_gain = profile
        .mappings
        .iter()
        .find(|m| m.label == "CH2 Gain")
        .expect("CH2 Gain mapping not found");

    match &ch2_gain.message_template {
        MidiMessageTemplate::ControlChange {
            channel,
            controller,
        } => {
            assert_eq!(*channel, 0, "CH2 should be on MIDI channel 1 (0-indexed)");
            assert_eq!(*controller, 16, "CH2 Gain should be CC 16");
        }
        _ => panic!(
            "CH2 Gain should be a CC message, got {:?}",
            ch2_gain.message_template
        ),
    }
}

#[test]
fn test_ecler_nuo4_midi_control_section() {
    let profile = ecler_nuo4();

    // Check Encoder 3 (A/L1) - the one visible in screenshot
    let enc3_a1 = profile
        .mappings
        .iter()
        .find(|m| m.label == "Encoder 3 (A/L1)")
        .expect("Encoder 3 (A/L1) mapping not found");

    match &enc3_a1.message_template {
        MidiMessageTemplate::ControlChange {
            channel,
            controller,
        } => {
            assert_eq!(
                *channel, 15,
                "MIDI Control should be on MIDI channel 16 (15 indexed)"
            );
            assert_eq!(*controller, 22, "Encoder 3 (A/L1) should be CC 22");
        }
        _ => panic!(
            "Encoder should be a CC message, got {:?}",
            enc3_a1.message_template
        ),
    }
}

#[test]
fn test_ecler_nuo4_midi_mapping() {
    let profile = ecler_nuo4();
    let mapping = profile.to_midi_mapping();

    assert_eq!(mapping.map.len(), 89, "MidiMapping should have 89 entries");
}

#[test]
fn test_ecler_nuo4_serialization() {
    let profile = ecler_nuo4();
    let json = profile.to_json().unwrap();
    let loaded = ControllerProfile::from_json(&json).unwrap();

    assert_eq!(profile.name, loaded.name);
    assert_eq!(profile.mappings.len(), loaded.mappings.len());
}
