#![allow(clippy::field_reassign_with_default)]
use vorce_core::effect_animation::EffectParameterAnimator;
use vorce_core::module::ModuleId;
use vorce_core::show_control::{ModuleArrangementItem, ShowControlModel, ShowMode};
use vorce_ui::editors::timeline_v2::TimelineV2;

#[test]
fn test_timeline_fully_automated_switch() {
    let mut timeline = TimelineV2 { ..TimelineV2::default() };
    let _animator = EffectParameterAnimator::new();
    let mut show_control = ShowControlModel::default();
    show_control.show_control_enabled = true;
    show_control.show_mode = ShowMode::FullyAutomated;
    show_control.module_arrangement = vec![
        ModuleArrangementItem {
            id: 1,
            module_id: ModuleId(101),
            start_time: 0.0,
            duration: 10.0,
            enabled: true,
            start_trigger: None,
        },
        ModuleArrangementItem {
            id: 2,
            module_id: ModuleId(102),
            start_time: 10.0,
            duration: 10.0,
            enabled: true,
            start_trigger: None,
        },
    ];

    let available_ids = vec![ModuleId(101), ModuleId(102)];

    // Check at time 5.0 (should be module 101)
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &mut show_control);
    assert_eq!(mod_id, Some(ModuleId(101)));

    // Check at time 15.0 (should be module 102)
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids, &mut show_control);
    assert_eq!(mod_id, Some(ModuleId(102)));
}

#[allow(clippy::field_reassign_with_default)]
#[test]
fn test_timeline_manual_mode_no_auto_switch() {
    let mut timeline = TimelineV2 { manual_current_block_id: Some(1), ..TimelineV2::default() };
    let _animator = EffectParameterAnimator::new();
    let mut show_control = ShowControlModel::default();
    show_control.show_control_enabled = true;
    show_control.show_mode = ShowMode::Manual;
    show_control.module_arrangement = vec![ModuleArrangementItem {
        id: 1,
        module_id: ModuleId(101),
        start_time: 0.0,
        duration: 10.0,
        enabled: true,
        start_trigger: None,
    }];

    let available_ids = vec![ModuleId(101)];

    // Even at time 15.0 (outside block), it should return the manual selection
    let mod_id = timeline.runtime_show_module(15.0, true, &available_ids, &mut show_control);
    assert_eq!(mod_id, Some(ModuleId(101)));
}

#[allow(clippy::field_reassign_with_default)]
#[test]
fn test_timeline_hybrid_mode() {
    let mut timeline = TimelineV2 { ..TimelineV2::default() };
    let _animator = EffectParameterAnimator::new();
    let mut show_control = ShowControlModel::default();
    show_control.show_control_enabled = true;
    show_control.show_mode = ShowMode::Hybrid;
    show_control.module_arrangement = vec![
        ModuleArrangementItem {
            id: 1,
            module_id: ModuleId(101),
            start_time: 0.0,
            duration: 10.0,
            enabled: true,
            start_trigger: None,
        },
        ModuleArrangementItem {
            id: 2,
            module_id: ModuleId(102),
            start_time: 0.0,
            duration: 10.0,
            enabled: true,
            start_trigger: Some("trigA".to_string()),
        },
    ];

    let available_ids = vec![ModuleId(101), ModuleId(102)];

    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &mut show_control);
    assert_eq!(mod_id, Some(ModuleId(101)));

    timeline.hybrid_active_triggers.insert("trigA".to_string());
    let mod_id = timeline.runtime_show_module(5.0, true, &available_ids, &mut show_control);
    assert_eq!(mod_id, Some(ModuleId(102)));
}
