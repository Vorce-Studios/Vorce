use vorce_core::module::part::ModulePart;
use vorce_core::module::SharedMediaState;
use vorce_core::module::{
    LayerType, ModuleConnection, ModulePartType, ModulePlaybackMode, OutputType, VorceModule,
};
use vorce_core::module_eval::ModuleEvaluator;

#[test]
fn test_render_ops_deterministic_order() {
    let mut evaluator = ModuleEvaluator::new();
    let shared_state = SharedMediaState::default();

    let mut module = VorceModule {
        id: 1,
        name: "Test Module".to_string(),
        color: [1.0, 1.0, 1.0, 1.0],
        parts: Vec::new(),
        connections: Vec::new(),
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 100,
    };

    // Add layers out of order
    for i in (0..10).rev() {
        module.parts.push(ModulePart {
            id: i as u64,
            part_type: ModulePartType::Layer(LayerType::Single {
                id: i as u64,
                name: format!("Layer {}", i),
                mesh: Default::default(),
                opacity: 1.0,
                blend_mode: Default::default(),
                mapping_mode: Default::default(),
            }),
            position: Default::default(),
            size: Default::default(),
            inputs: vec![],
            outputs: vec![],
            trigger_targets: Default::default(),
            link_data: Default::default(),
        });

        module.parts.push(ModulePart {
            id: 10 + i as u64,
            part_type: ModulePartType::Output(OutputType::Projector {
                id: 0,
                name: "Proj".to_string(),
                hide_cursor: false,
                target_screen: 0,
                show_in_preview_panel: false,
                extra_preview_window: false,
                output_width: 1920,
                output_height: 1080,
                ndi_enabled: false,
                ndi_stream_name: "".to_string(),
                output_fps: 60.0,
            }),
            position: Default::default(),
            size: Default::default(),
            inputs: vec![],
            outputs: vec![],
            trigger_targets: Default::default(),
            link_data: Default::default(),
        });

        module.connections.push(ModuleConnection {
            from_part: i as u64,
            from_socket: "layer_out".to_string(),
            to_part: 10 + i as u64,
            to_socket: "layer_in".to_string(),
        });
    }

    evaluator.evaluate(&module, &shared_state, 1);

    // Evaluate multiple times to make sure it's deterministic
    for _ in 0..5 {
        evaluator.evaluate(&module, &shared_state, 1);
        let ops = &evaluator.cached_result.render_ops;

        let mut prev_id = 0;
        let mut first = true;
        for op in ops {
            if first {
                first = false;
                prev_id = op.layer_part_id;
            } else {
                assert!(
                    prev_id < op.layer_part_id,
                    "Render ops are not in deterministic order! {} vs {}",
                    prev_id,
                    op.layer_part_id
                );
                prev_id = op.layer_part_id;
            }
        }
    }
}
