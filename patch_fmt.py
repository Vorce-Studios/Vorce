import re

# helpers.rs
with open("crates/vorce-control/src/midi/ecler_nuo4/helpers.rs", "r") as f:
    text = f.read()

text = text.replace("""        message_template: MidiMessageTemplate::ControlChange {
            channel,
            controller,
        },""", """        message_template: MidiMessageTemplate::ControlChange { channel, controller },""")

with open("crates/vorce-control/src/midi/ecler_nuo4/helpers.rs", "w") as f:
    f.write(text)


# tests.rs
with open("crates/vorce-control/src/midi/ecler_nuo4/tests.rs", "r") as f:
    text = f.read()

text = text.replace("""    assert_eq!(
        profile.mappings.len(),
        89,
        "Expected 89 mappings, got {}",
        profile.mappings.len()
    );""", """    assert_eq!(profile.mappings.len(), 89, "Expected 89 mappings, got {}", profile.mappings.len());""")

text = text.replace("""        MidiMessageTemplate::ControlChange {
            channel,
            controller,
        } => {""", """        MidiMessageTemplate::ControlChange { channel, controller } => {""")

text = text.replace("""        _ => panic!(
            "CH2 Gain should be a CC message, got {:?}",
            ch2_gain.message_template
        ),""", """        _ => panic!("CH2 Gain should be a CC message, got {:?}", ch2_gain.message_template),""")

text = text.replace("""            assert_eq!(
                *channel, 15,
                "MIDI Control should be on MIDI channel 16 (15 indexed)"
            );""", """            assert_eq!(*channel, 15, "MIDI Control should be on MIDI channel 16 (15 indexed)");""")

text = text.replace("""        _ => panic!(
            "Encoder should be a CC message, got {:?}",
            enc3_a1.message_template
        ),""", """        _ => panic!("Encoder should be a CC message, got {:?}", enc3_a1.message_template),""")

with open("crates/vorce-control/src/midi/ecler_nuo4/tests.rs", "w") as f:
    f.write(text)

# mappings.rs
with open("crates/vorce-control/src/midi/ecler_nuo4/mappings.rs", "r") as f:
    text = f.read()

text = text.replace("""        note_mapping(
            15,
            44,
            "Switch 1 (B/L3)",
            ControlTarget::Custom("switch_1_b3".to_string()),
        ),""", """        note_mapping(15, 44, "Switch 1 (B/L3)", ControlTarget::Custom("switch_1_b3".to_string())),""")

text = text.replace("""        note_mapping(
            15,
            45,
            "Switch 2 (B/L3)",
            ControlTarget::Custom("switch_2_b3".to_string()),
        ),""", """        note_mapping(15, 45, "Switch 2 (B/L3)", ControlTarget::Custom("switch_2_b3".to_string())),""")

text = text.replace("""        note_mapping(
            15,
            46,
            "Switch 3 (B/L3)",
            ControlTarget::Custom("switch_3_b3".to_string()),
        ),""", """        note_mapping(15, 46, "Switch 3 (B/L3)", ControlTarget::Custom("switch_3_b3".to_string())),""")

text = text.replace("""        note_mapping(
            15,
            47,
            "Switch 4 (B/L3)",
            ControlTarget::Custom("switch_4_b3".to_string()),
        ),""", """        note_mapping(15, 47, "Switch 4 (B/L3)", ControlTarget::Custom("switch_4_b3".to_string())),""")

with open("crates/vorce-control/src/midi/ecler_nuo4/mappings.rs", "w") as f:
    f.write(text)
