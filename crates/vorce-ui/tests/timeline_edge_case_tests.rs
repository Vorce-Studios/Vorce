use vorce_ui::editors::timeline_v2::{ModuleArrangementItem, ShowMode, TimelineV2};

#[test]
fn test_timeline_empty_arrangement() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // Check at time 5.0 (should be None as timeline is empty)
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids);
    assert_eq!(mod_id, None);
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
                start_time: 5.0, // Overlaps with the first one
                duration: 10.0,
                enabled: true,
                start_trigger: None,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // Check at time 7.0
    // Active block function:
    // It loops through sorted_enabled_blocks().
    // They are sorted by start_time: block 1 (0.0), then block 2 (5.0).
    // The loop:
    // block 1: 7.0 >= 0.0 and 7.0 < 10.0. Returns Some(block 1).
    // So it will always return the *first* block that overlaps in start time order.
    // Let's test that it returns Some(101).
    let mod_id = timeline.runtime_show_module(7.0, true, &available_ids);
    assert_eq!(mod_id, Some(101));
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

    // Exactly at boundary 10.0
    let mod_id = timeline.runtime_show_module(10.0, true, &available_ids);
    assert_eq!(mod_id, Some(102));
}

#[test]
fn test_timeline_invalid_edits() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![
            ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: -5.0, // Invalid duration
                enabled: true,
                start_trigger: None,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101];

    // Check at time 2.0 (should handle invalid duration gracefully)
    // ModuleArrangementItem::end_time() is self.start_time + self.duration.max(0.1)
    // So end_time is 0.0 + (-5.0).max(0.1) = 0.1
    // At time 2.0: 2.0 >= 0.0 and 2.0 < 0.1 is false.
    // Loop finishes. It checks:
    // `if let Some(last_before) = blocks.iter().rev().find(|block| time >= block.start_time)`
    // 2.0 >= 0.0 is true. So it returns `Some(last_before)`!
    // So it returns Some(101)! This is because timeline retains the last active block if no current block matches but time is after a block.
    // Let's assert it returns Some(101).
    let mod_id = timeline.runtime_show_module(2.0, true, &available_ids);
    assert_eq!(mod_id, Some(101));
}
