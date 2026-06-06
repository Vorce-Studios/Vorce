use vorce_control::cue::{Cue, LayerState, TimelineTrigger};

#[test]
fn test_cue_timeline_trigger_roundtrip() {
    let mut cue = Cue::new(1, "Timeline Trigger Test".to_string());
    cue.add_layer_state(0, LayerState::default_visible());

    // Add a timeline trigger
    let timeline_trigger = TimelineTrigger::new(42, 1000);
    cue.timeline_trigger = Some(timeline_trigger.clone());

    // Serialize
    let json = serde_json::to_string(&cue).expect("Failed to serialize Cue");

    // Deserialize
    let deserialized: Cue = serde_json::from_str(&json).expect("Failed to deserialize Cue");

    // Verify properties
    assert_eq!(deserialized.id, 1);
    assert_eq!(deserialized.name, "Timeline Trigger Test");

    // Verify timeline trigger roundtrip
    assert!(deserialized.timeline_trigger.is_some());
    let dt = deserialized.timeline_trigger.unwrap();
    assert_eq!(dt.module_id, 42);
    assert_eq!(dt.time_ms, 1000);

    // Verify logic
    assert!(dt.matches_time(42, 1000));
    assert!(!dt.matches_time(43, 1000));
    assert!(!dt.matches_time(42, 1001));
}
