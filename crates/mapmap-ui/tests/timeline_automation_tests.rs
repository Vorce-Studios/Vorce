use mapmap_ui::editors::timeline_v2::{ModuleArrangementItem, ShowMode, TimelineV2};

#[test]
fn test_timeline_fully_automated_switch() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::FullyAutomated,
        module_arrangement: vec![
            ModuleArrangementItem {
                id: 1,
                module_id: 101,
                start_time: 0.0,
                duration: 10.0,
                enabled: true,
            },
            ModuleArrangementItem {
                id: 2,
                module_id: 102,
                start_time: 10.0,
                duration: 10.0,
                enabled: true,
            },
        ],
        ..TimelineV2::default()
    };

    let available_ids = vec![101, 102];

    // Check at time 5.0 (should be module 101)
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids);
    assert_eq!(mod_id, Some(101));

    // Check at time 15.0 (should be module 102)
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids);
    assert_eq!(mod_id, Some(102));
}

#[test]
fn test_timeline_manual_mode_no_auto_switch() {
    let mut timeline = TimelineV2 {
        show_mode: ShowMode::Manual,
        manual_current_block_id: Some(1),
        module_arrangement: vec![ModuleArrangementItem {
            id: 1,
            module_id: 101,
            start_time: 0.0,
            duration: 10.0,
            enabled: true,
        }],
        ..TimelineV2::default()
    };

    let available_ids = vec![101];

    // Even at time 15.0 (outside block), it should return the manual selection
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids);
    assert_eq!(mod_id, Some(101));
}

#[test]
fn test_timeline_keyframe_selection() {
    let mut timeline = TimelineV2::default();
    let track_name = "test_track".to_string();
    let time = 1.5_f32;
    let time_bits = (time as f64).to_bits();

    assert!(timeline.selected_keyframes.is_empty());

    // Simulate selection
    timeline
        .selected_keyframes
        .push((track_name.clone(), time_bits));

    assert_eq!(timeline.selected_keyframes.len(), 1);
    assert_eq!(timeline.selected_keyframes[0].0, track_name);
    assert_eq!(timeline.selected_keyframes[0].1, time_bits);

    // Simulate clearing selection
    timeline.selected_keyframes.clear();
    assert!(timeline.selected_keyframes.is_empty());
}
