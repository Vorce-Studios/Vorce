use vorce_ui::editors::timeline_v2::TimelineV2;

// The purpose of this test suite is to assert the behavior of TimelineV2 drag calculations and selection properties.

#[test]
fn test_timeline_drag_snapping() {
    let mut timeline = TimelineV2 { snap_enabled: true, snap_interval: 0.1, ..Default::default() };

    // Test basic drag snapping intervals
    assert!((timeline.snap_time(1.11) - 1.1).abs() < 1e-5);
    assert!((timeline.snap_time(1.16) - 1.2).abs() < 1e-5);

    // Test wider interval dragging
    timeline.snap_interval = 0.5;
    assert!((timeline.snap_time(1.2) - 1.0).abs() < 1e-5);
    assert!((timeline.snap_time(1.3) - 1.5).abs() < 1e-5);

    // Test when dragging with snapping disabled
    timeline.snap_enabled = false;
    assert!((timeline.snap_time(1.24) - 1.24).abs() < 1e-5);
}

// Instead of pushing to a Vec we will test the methods that actually modify the arrangement selection
#[test]
fn test_timeline_step_manual() {
    use vorce_ui::editors::timeline_v2::models::ShowMode;

    let mut timeline = TimelineV2 { show_mode: ShowMode::Manual, ..Default::default() };

    // Simulate adding modules and selecting them
    // Let's add some blocks directly to module_arrangement, normally done via `add_module_block` but for setup we'll just mock the items.
    timeline.module_arrangement.push(
        vorce_ui::editors::timeline_v2::models::ModuleArrangementItem {
            id: 1,
            module_id: 101,
            start_time: 0.0,
            duration: 1.0,
            enabled: true,
            start_trigger: None,
        },
    );
    timeline.module_arrangement.push(
        vorce_ui::editors::timeline_v2::models::ModuleArrangementItem {
            id: 2,
            module_id: 102,
            start_time: 1.0,
            duration: 1.0,
            enabled: true,
            start_trigger: None,
        },
    );

    timeline.manual_current_block_id = Some(1);

    // Test selection behavior via next/prev interactions
    let next_mod = timeline.step_manual_next();
    assert_eq!(next_mod, Some(102));
    assert_eq!(timeline.manual_current_block_id, Some(2));

    let prev_mod = timeline.step_manual_prev();
    assert_eq!(prev_mod, Some(101));
    assert_eq!(timeline.manual_current_block_id, Some(1));
}

#[test]
fn test_timeline_step_semi_auto() {
    use vorce_ui::editors::timeline_v2::models::ShowMode;

    let mut timeline = TimelineV2 { show_mode: ShowMode::SemiAutomated, ..Default::default() };

    timeline.module_arrangement.push(
        vorce_ui::editors::timeline_v2::models::ModuleArrangementItem {
            id: 1,
            module_id: 101,
            start_time: 0.0,
            duration: 1.0,
            enabled: true,
            start_trigger: None,
        },
    );
    timeline.module_arrangement.push(
        vorce_ui::editors::timeline_v2::models::ModuleArrangementItem {
            id: 2,
            module_id: 102,
            start_time: 1.0,
            duration: 1.0,
            enabled: true,
            start_trigger: None,
        },
    );

    timeline.semi_auto_current_block_id = Some(1);
    timeline.semi_auto_pending_block_id = Some(2);

    // Test selection interaction: step_semi_auto_next confirms pending
    let selected_mod = timeline.step_semi_auto_next();
    assert_eq!(selected_mod, Some(102));
    assert_eq!(timeline.semi_auto_current_block_id, Some(2));
    assert_eq!(timeline.semi_auto_pending_block_id, None);
}
