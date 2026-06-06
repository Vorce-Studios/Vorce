use vorce_ui::editors::timeline_v2::{ModuleArrangementItem, ShowMode, TimelineV2};

#[test]
fn test_timeline_empty_timeline() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // empty timeline returns None
    assert_eq!(timeline.runtime_show_module(0.0, true, &available_ids), None);
    assert_eq!(timeline.runtime_show_module(5.0, true, &available_ids), None);
}

#[test]
fn test_timeline_overlapping_cues() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![
            ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: 10.0,
                enabled: true,
                start_trigger: None,
            },
            ModuleArrangementItem {
                id: 2,
                module_id: 102,
                start_time: 5.0,
                duration: 10.0,
                enabled: true,
                start_trigger: None,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // At 0.0 -> 101
    assert_eq!(timeline.runtime_show_module(0.0, true, &available_ids), Some(101));

    // At 6.0 -> Both are active, the sorting logic dictates it should pick the first one by start time -> 101
    assert_eq!(timeline.runtime_show_module(6.0, true, &available_ids), Some(101));

    // At 12.0 -> Only 102 is active -> 102
    assert_eq!(timeline.runtime_show_module(12.0, true, &available_ids), Some(102));
}

#[test]
fn test_timeline_boundary_timestamps() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![
            ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: 10.0,
                enabled: true,
                start_trigger: None,
            },
            ModuleArrangementItem {
                id: 2,
                module_id: 102,
                start_time: 10.0,
                duration: 10.0,
                enabled: true,
                start_trigger: None,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // At exactly 10.0 -> The first block ends and second begins.
    // `current_time < block.end_time()` makes 101 end exactly at 10.0 (not inclusive).
    // `current_time >= block.start_time` makes 102 start exactly at 10.0 (inclusive).
    assert_eq!(timeline.runtime_show_module(10.0, true, &available_ids), Some(102));
}

#[test]
fn test_timeline_invalid_edits_zero_or_negative_duration() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![
            ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: -5.0, // Invalid edit
                enabled: true,
                start_trigger: None,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101];

    // end_time() uses `duration.max(0.1)` so negative durations become 0.1s
    assert_eq!(timeline.module_arrangement[0].end_time(), 0.1);

    assert_eq!(timeline.runtime_show_module(0.05, true, &available_ids), Some(101));
    assert_eq!(timeline.runtime_show_module(0.2, true, &available_ids), Some(101)); // Falls back to nearest/last block
}
