use vorce_core::module_eval::ModuleEvaluator;
use vorce_core::module::{VorceModule, PartType};

fn create_test_module() -> VorceModule {
    VorceModule {
        id: 1,
        name: "Test Module".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: vorce_core::module::ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    }
}

#[test]
fn test_render_ops_determinism() {
    let mut module = create_test_module();

    let mut outputs = Vec::new();
    for i in 0..10 {
        let l_id = module.add_part(PartType::Layer, (0.0, i as f32 * 50.0));
        let o_id = module.add_part(PartType::Output, (100.0, i as f32 * 50.0));
        module.add_connection(l_id, "layer_out".to_string(), o_id, "layer_in".to_string());
        outputs.push(o_id);
    }

    let mut evaluator = ModuleEvaluator::new();
    evaluator.evaluate(&module, &vorce_core::module::SharedMediaState::default(), 0);

    let op_ids: Vec<_> = evaluator.cached_result.render_ops.iter().map(|op| op.output_part_id).collect();

    let mut module_reversed = module.clone();
    module_reversed.parts.reverse();

    let mut evaluator_rev = ModuleEvaluator::new();
    evaluator_rev.evaluate(&module_reversed, &vorce_core::module::SharedMediaState::default(), 0);
    let op_ids_rev: Vec<_> = evaluator_rev.cached_result.render_ops.iter().map(|op| op.output_part_id).collect();

    assert_eq!(op_ids, op_ids_rev, "Render order should be deterministic and independent of parts order in Vec");
}
