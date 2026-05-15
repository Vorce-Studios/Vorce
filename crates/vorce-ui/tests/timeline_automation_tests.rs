use vorce_core::effect_animation::{EffectParameterAnimator, ModuleArrangementItem, ShowMode};
use vorce_ui::editors::timeline_v2::TimelineV2;

#[test]
fn test_timeline_fully_automated_switch() {
    let mut timeline = TimelineV2 { ..TimelineV2::default() };
    let mut animator = EffectParameterAnimator::new();
    animator.show_mode = ShowMode::FullyAutomated;
    animator.module_arrangement = vec![
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
    ];

    let available_ids = vec![101, 102];

    // Check at time 5.0 (should be module 101)
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &animator);
    assert_eq!(mod_id, Some(101));

    // Check at time 15.0 (should be module 102)
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids, &animator);
    assert_eq!(mod_id, Some(102));
}

#[test]
fn test_timeline_manual_mode_no_auto_switch() {
    let mut timeline = TimelineV2 { manual_current_block_id: Some(1), ..TimelineV2::default() };
    let mut animator = EffectParameterAnimator::new();
    animator.show_mode = ShowMode::Manual;
    animator.module_arrangement = vec![ModuleArrangementItem {
        id: 1,
        module_id: 101,
        start_time: 0.0,
        duration: 10.0,
        enabled: true,
        start_trigger: None,
    }];

    let available_ids = vec![101];

    // Even at time 15.0 (outside block), it should return the manual selection
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids, &animator);
    assert_eq!(mod_id, Some(101));
}

#[test]
fn test_timeline_hybrid_mode() {
    let mut timeline = TimelineV2 { ..TimelineV2::default() };
    let mut animator = EffectParameterAnimator::new();
    animator.show_mode = ShowMode::Hybrid;
    animator.module_arrangement = vec![
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
            start_time: 0.0,
            duration: 10.0,
            enabled: true,
            start_trigger: Some("trigA".to_string()),
        },
    ];

    let available_ids = vec![101, 102];

    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &animator);
    assert_eq!(mod_id, Some(101));

    timeline.hybrid_active_triggers.insert("trigA".to_string());
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &animator);
    assert_eq!(mod_id, Some(102));
}
