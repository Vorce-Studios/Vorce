#[cfg(test)]
mod evaluator_tests {

    use crate::audio::analyzer_v2::AudioAnalysisV2;
    use crate::module::{
        AudioTriggerOutputConfig, HueNodeType, LinkMode, ModulePartType, SourceType, TriggerType,
        VorceModule,
    };
    use crate::module_eval::evaluator::SourceCommand;
    use crate::module_eval::ModuleEvaluator;
    use std::time::Duration;

    fn create_test_module() -> VorceModule {
        VorceModule {
            id: 1,
            name: "Test Module".to_string(),
            color: [1.0; 4],
            parts: vec![],
            connections: vec![],
            playback_mode: crate::module::ModulePlaybackMode::LoopUntilManualSwitch,
            next_part_id: 1,
        }
    }

    #[test]
    fn test_evaluator_initialization() {
        let evaluator = ModuleEvaluator::new();
        assert_eq!(evaluator.audio_trigger_data.rms_volume, 0.0);
    }

    #[test]
    fn test_trigger_fixed_interval() {
        let mut evaluator = ModuleEvaluator::new();
        let shared = crate::module::SharedMediaState::default();

        let mut module = create_test_module();
        let trigger_part =
            ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 100, offset_ms: 0 });
        let part_id = module.add_part_with_type(trigger_part, (0.0, 0.0));

        // Initial eval - t=0, phase=0, duration=10, 0 < 10 -> 1.0
        let result = evaluator.evaluate(&module, &shared, 0);
        let values = &result.trigger_values[&part_id];
        assert_eq!(values[0], 1.0);

        // We can't easily mock time passage without refactoring ModuleEvaluator to accept a clock,
        // or sleeping. Sleeping in unit tests is generally bad, but for 15ms it's acceptable-ish
        // for this specific scenario if we want to test the time logic.
        // Ideally we'd refactor to inject time.
        std::thread::sleep(Duration::from_millis(20));

        let result = evaluator.evaluate(&module, &shared, 0);
        let values = &result.trigger_values[&part_id];
        // 20ms > 10ms pulse duration -> 0.0
        assert_eq!(values[0], 0.0);
    }

    #[test]
    fn test_trigger_audio_fft() {
        let mut evaluator = ModuleEvaluator::new();

        // Setup Audio Analysis with a "Beat"
        let analysis =
            AudioAnalysisV2 { beat_detected: true, rms_volume: 0.8, ..Default::default() };

        evaluator.update_audio(&analysis);

        let mut module = create_test_module();

        // Setup AudioFFT Trigger expecting Beat Output and Volume
        let config = AudioTriggerOutputConfig {
            beat_output: true,
            volume_outputs: true,
            ..Default::default()
        };
        let trigger_part = ModulePartType::Trigger(TriggerType::AudioFFT {
            band: crate::module::AudioBand::Bass, // irrelevant here
            threshold: 0.5,
            output_config: config,
        });

        let part_id = module.add_part_with_type(trigger_part, (0.0, 0.0));

        let result = evaluator.evaluate(&module, &crate::module::SharedMediaState::default(), 0);
        let values = &result.trigger_values[&part_id];

        // Order in generate_outputs:
        // if volume_outputs: RMS, Peak
        // if beat_output: Beat Out
        // So indices: 0: RMS, 1: Peak, 2: Beat Out

        assert_eq!(values.len(), 3);
        assert_eq!(values[0], 0.8); // RMS
        assert_eq!(values[2], 1.0); // Beat detected
    }

    #[test]
    fn test_evaluator_propagation() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        // 1. Trigger (Fixed -> always 1.0 at start)
        let t_type = ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 0, offset_ms: 0 }); // 0 interval = always on
        let t_id = module.add_part_with_type(t_type, (0.0, 0.0));

        // 2. Source (Target)
        let s_id = module.add_part(crate::module::PartType::Source, (200.0, 0.0));
        module.add_connection(t_id, "trigger_out".to_string(), s_id, "trigger_in".to_string()); // Trigger Out -> Source Trigger In

        let shared = crate::module::SharedMediaState::default();
        let _result = evaluator.evaluate(&module, &shared, 0);

        // Should produce a SourceCommand because trigger > 0.1
        // (Source defaults to "MediaFile" with empty path, create_source_command checks empty path)
        // Wait, SourceType::new_media_file("") -> default empty path.
        // create_source_command returns None if path is empty.
        // Let's set a path.
        if let Some(part) = module.parts.iter_mut().find(|p| p.id == s_id) {
            if let ModulePartType::Source(SourceType::MediaFile { path, .. }) = &mut part.part_type
            {
                *path = "test.mp4".to_string();
            }
        }

        let result = evaluator.evaluate(&module, &shared, 0);
        assert!(result.source_commands.contains_key(&s_id));

        // Now remove connection
        module.remove_connection(t_id, "trigger_out".to_string(), s_id, "trigger_in".to_string());

        let result = evaluator.evaluate(&module, &shared, 1);

        // A disconnected source defaults to trigger = 1.0, so it SHOULD generate a SourceCommand
        assert!(result.source_commands.contains_key(&s_id));
    }

    #[test]
    fn test_full_evaluation_pipeline() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        // Graph: FixedTrigger(Always) -> Source -> Layer -> Output

        // 1. Trigger
        let t_type = ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 0, offset_ms: 0 });
        let t_id = module.add_part_with_type(t_type, (0.0, 0.0));

        // 2. Source
        let s_id = module.add_part(crate::module::PartType::Source, (100.0, 0.0));
        if let Some(part) = module.parts.iter_mut().find(|p| p.id == s_id) {
            if let ModulePartType::Source(SourceType::MediaFile { path, .. }) = &mut part.part_type
            {
                *path = "test.mp4".to_string();
            }
        }

        // 3. Layer
        let l_id = module.add_part(crate::module::PartType::Layer, (200.0, 0.0));

        // 4. Output
        let o_id = module.add_part(crate::module::PartType::Output, (300.0, 0.0));

        // Connections
        module.add_connection(t_id, "trigger_out".to_string(), s_id, "trigger_in".to_string());
        module.add_connection(s_id, "media_out".to_string(), l_id, "media_in".to_string());
        module.add_connection(l_id, "layer_out".to_string(), o_id, "layer_in".to_string());

        let result = evaluator.evaluate(&module, &crate::module::SharedMediaState::default(), 0);

        // Verify RenderOp
        assert_eq!(result.render_ops.len(), 1);
        let op = &result.render_ops[0];
        assert_eq!(op.output_part_id, o_id);
        assert_eq!(op.layer_part_id, l_id);
        assert_eq!(op.source_part_id, Some(s_id));

        // Verify SourceCommand
        assert!(result.source_commands.contains_key(&s_id));
        if let Some(SourceCommand::PlayMedia { path, .. }) = result.source_commands.get(&s_id) {
            assert_eq!(path, "test.mp4");
        } else {
            panic!("Expected PlayMedia command");
        }
    }

    #[test]
    fn test_render_trace_prefers_layer_visual_input_over_trigger_input() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        let t_id = module.add_part_with_type(
            ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 0, offset_ms: 0 }),
            (0.0, 0.0),
        );

        let s_id = module.add_part(crate::module::PartType::Source, (100.0, 0.0));
        if let Some(part) = module.parts.iter_mut().find(|p| p.id == s_id) {
            if let ModulePartType::Source(SourceType::MediaFile { path, .. }) = &mut part.part_type
            {
                *path = "test.mp4".to_string();
            }
        }

        let l_id = module.add_part(crate::module::PartType::Layer, (200.0, 0.0));
        let o_id = module.add_part(crate::module::PartType::Output, (300.0, 0.0));

        // Repro: if the trigger connection is inserted first, the render trace must
        // still follow layer socket 0 (visual chain) rather than socket 1 (trigger).
        module.add_connection(t_id, "trigger_out".to_string(), l_id, "trigger_in".to_string());
        module.add_connection(s_id, "media_out".to_string(), l_id, "media_in".to_string());
        module.add_connection(l_id, "layer_out".to_string(), o_id, "layer_in".to_string());

        let result = evaluator.evaluate(&module, &crate::module::SharedMediaState::default(), 0);

        assert_eq!(result.render_ops.len(), 1);
        let op = &result.render_ops[0];
        assert_eq!(op.output_part_id, o_id);
        assert_eq!(op.layer_part_id, l_id);
        assert_eq!(op.source_part_id, Some(s_id));
    }

    #[test]
    fn test_link_system_master_slave() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        // Master Node (Trigger Type for simplicity, acting as master)
        let m_type = ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 0, offset_ms: 0 });
        let m_id = module.add_part_with_type(m_type, (0.0, 0.0));

        // Configure as Master
        if let Some(part) = module.parts.iter_mut().find(|p| p.id == m_id) {
            part.link_data.mode = LinkMode::Master;
            part.link_data.trigger_input_enabled = true; // Use trigger input to drive link
            part.outputs.push(crate::module::ModuleSocket::output(
                "link_out",
                "Link Out",
                crate::module::ModuleSocketType::Link,
            ));
            // Also needs Trigger In socket if enabled
            part.inputs.push(
                crate::module::ModuleSocket::input_mappable(
                    "trigger_vis_in",
                    "Trigger In (Vis)",
                    crate::module::ModuleSocketType::Trigger,
                )
                .multi_input(),
            );
        }

        // Driving Trigger
        let t_id = module.add_part_with_type(
            ModulePartType::Trigger(TriggerType::Fixed { interval_ms: 0, offset_ms: 0 }),
            (-100.0, 0.0),
        );

        // Connect Driving Trigger -> Master Trigger In (Vis)
        module.add_connection(t_id, "trigger_out".to_string(), m_id, "trigger_vis_in".to_string());

        // Slave Node (Layer)
        let s_id = module.add_part(crate::module::PartType::Layer, (100.0, 0.0));
        // Configure as Slave
        if let Some(part) = module.parts.iter_mut().find(|p| p.id == s_id) {
            part.link_data.mode = LinkMode::Slave;
            part.inputs.push(crate::module::ModuleSocket::input(
                "link_in",
                "Link In",
                crate::module::ModuleSocketType::Link,
            ));
        }

        // Connect Master Link Out -> Slave Link In
        module.add_connection(m_id, "link_out".to_string(), s_id, "link_in".to_string());

        let result = evaluator.evaluate(&module, &crate::module::SharedMediaState::default(), 0);

        // Master ID in trigger_values should have 2 values: Trigger Out (1.0) and Link Out (1.0)
        let m_values = &result.trigger_values[&m_id];
        assert!(m_values.len() >= 2);
        // We need to find the link_out value.
        // The trigger_values are stored by socket index.
        // Link out was pushed last, trigger_out is first.
        assert_eq!(m_values[1], 1.0); // Link Out should be active
    }

    #[test]
    fn test_render_op_pooling() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        // 1. Layer -> Output
        let l_id = module.add_part(crate::module::PartType::Layer, (0.0, 0.0));
        let o_id = module.add_part(crate::module::PartType::Output, (100.0, 0.0));
        module.add_connection(l_id, "layer_out".to_string(), o_id, "layer_in".to_string());

        let shared = crate::module::SharedMediaState::default();

        // Pass 1: Should create one RenderOp
        evaluator.evaluate(&module, &shared, 0);
        assert_eq!(evaluator.cached_result.render_ops.len(), 1);
        assert_eq!(evaluator.cached_result.spare_render_ops.len(), 0);

        // Pass 2: Should recycle the RenderOp
        // Note: evaluate() calls clear() at the start, moving render_ops to spare.
        // Then it pops one.
        evaluator.evaluate(&module, &shared, 0);
        assert_eq!(evaluator.cached_result.render_ops.len(), 1);
        // Spare should be 0 because we popped the one that was recycled
        assert_eq!(evaluator.cached_result.spare_render_ops.len(), 0);

        // Pass 3: Reduce workload (no output connection)
        module.remove_connection(l_id, "layer_out".to_string(), o_id, "layer_in".to_string());
        evaluator.evaluate(&module, &shared, 1);

        // render_ops should be empty
        assert_eq!(evaluator.cached_result.render_ops.len(), 0);
        // spare_render_ops should contain the recycled one
        assert_eq!(evaluator.cached_result.spare_render_ops.len(), 1);
    }

    #[test]
    fn test_hue_node_uses_static_defaults_without_trigger_inputs() {
        let mut evaluator = ModuleEvaluator::new();
        let mut module = create_test_module();

        let hue_id = module.add_part_with_type(
            ModulePartType::Hue(HueNodeType::SingleLamp {
                id: "lamp-1".to_string(),
                name: "Lamp 1".to_string(),
                brightness: 0.75,
                color: [0.2, 0.6, 1.0],
                effect: Some("strobe".to_string()),
                effect_active: true,
            }),
            (0.0, 0.0),
        );

        let result = evaluator.evaluate(&module, &crate::module::SharedMediaState::default(), 0);
        let Some(SourceCommand::HueOutput { brightness, hue, saturation, strobe, ids }) =
            result.source_commands.get(&hue_id)
        else {
            panic!("Expected HueOutput command");
        };

        assert_eq!(*brightness, 0.75);
        assert!(hue.is_some());
        assert!(saturation.is_some());
        assert_eq!(*strobe, Some(1.0));
        assert_eq!(ids.as_ref(), Some(&vec!["lamp-1".to_string()]));
    }
}
