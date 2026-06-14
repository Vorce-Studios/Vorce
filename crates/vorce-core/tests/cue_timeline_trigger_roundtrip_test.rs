use vorce_control::cue::{Cue, triggers::{TimelineTrigger, TimelineTriggerAction}};

#[test]
fn test_cue_timeline_trigger_roundtrip() {
    let mut original_cue = Cue::new(1, "Test Cue".to_string());
    original_cue.timeline_trigger = Some(TimelineTrigger::seek(1.5).with_module(42));

    // Serialize
    let serialized = serde_json::to_string(&original_cue).expect("Failed to serialize");

    // Deserialize
    let deserialized: Cue = serde_json::from_str(&serialized).expect("Failed to deserialize");

    // Validate deterministic roundtrip execution of the trigger
    assert_eq!(deserialized.id, 1);
    assert_eq!(deserialized.name, "Test Cue");

    let trigger = deserialized.timeline_trigger.expect("Timeline trigger missing after roundtrip");
    assert_eq!(trigger.module_id, Some(42));
    assert_eq!(trigger.action, TimelineTriggerAction::Seek(1.5));
}
