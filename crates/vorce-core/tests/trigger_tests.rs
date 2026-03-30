use std::collections::HashSet;
use vorce_core::module::{ModulePartType, ModulePlaybackMode, TriggerType, VorceModule};
use vorce_core::module_eval::ModuleEvaluator;

#[test]
fn test_audio_fft_fallback() {
    let mut evaluator = ModuleEvaluator::new();
    let mut module = VorceModule {
        id: 1,
        name: "Test".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    };

    // All outputs disabled, should fallback to Beat Out
    let output_config = vorce_core::module::AudioTriggerOutputConfig {
        frequency_bands: false,
        volume_outputs: false,
        beat_output: false,
        bpm_output: false,
        inverted_outputs: std::collections::HashSet::new(),
    };
    let t_id = module.add_part_with_type(
        ModulePartType::Trigger(TriggerType::AudioFFT {
            band: vorce_core::module::AudioBand::SubBass,
            threshold: 0.5,
            output_config,
        }),
        (0.0, 0.0),
    );

    let mut analysis = vorce_core::audio::analyzer_v2::AudioAnalysisV2 {
        beat_detected: true,
        ..Default::default()
    };
    evaluator.update_audio(&analysis);

    let shared = vorce_core::module::SharedMediaState::default();
    let res = evaluator.evaluate(&module, &shared, 0);

    let values = res.trigger_values.get(&t_id).unwrap();
    assert_eq!(
        values.len(),
        1,
        "Should fallback to exactly 1 output (beat_out)"
    );
    assert_eq!(
        values[0], 1.0,
        "Fallback beat output should be 1.0 when beat is detected"
    );

    // Test with beat detected false
    analysis.beat_detected = false;
    evaluator.update_audio(&analysis);
    let res = evaluator.evaluate(&module, &shared, 0);
    let values = res.trigger_values.get(&t_id).unwrap();
    assert_eq!(values.len(), 1);
    assert_eq!(values[0], 0.0);
}

#[test]
fn test_manual_trigger() {
    let mut evaluator = ModuleEvaluator::new();
    let mut module = VorceModule {
        id: 1,
        name: "Test".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    };

    // Add a trigger node
    let t_id = module.add_part_with_type(ModulePartType::Trigger(TriggerType::Beat), (0.0, 0.0));

    // Evaluate without manual trigger
    let shared = vorce_core::module::SharedMediaState::default();
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);

    // Fire manual trigger
    evaluator.trigger_node(t_id);
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 1.0);

    // Verify it's cleared next frame
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);
}

#[test]
fn test_shortcut_trigger() {
    let mut evaluator = ModuleEvaluator::new();
    let mut module = VorceModule {
        id: 1,
        name: "Test".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    };

    // Add a shortcut trigger
    let t_id = module.add_part_with_type(
        ModulePartType::Trigger(TriggerType::Shortcut {
            key_code: "Space".to_string(),
            modifiers: 0,
        }),
        (0.0, 0.0),
    );

    let shared = vorce_core::module::SharedMediaState::default();

    // No key pressed
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);

    // Press Space
    let mut keys = HashSet::new();
    keys.insert("Space".to_string());
    evaluator.update_keys(&keys);

    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 1.0);

    // Release Space
    keys.clear();
    evaluator.update_keys(&keys);
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);
}

#[test]
fn test_midi_trigger() {
    let mut evaluator = ModuleEvaluator::new();
    let mut module = VorceModule {
        id: 1,
        name: "Test".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    };

    // Add a MIDI trigger (Channel 1, Note 60)
    let t_id = module.add_part_with_type(
        ModulePartType::Trigger(TriggerType::Midi {
            device: "Any".to_string(),
            channel: 1,
            note: 60,
        }),
        (0.0, 0.0),
    );

    let shared = vorce_core::module::SharedMediaState::default();

    // No MIDI
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);

    // Send MIDI
    let mut shared_midi = shared.clone();
    shared_midi.active_midi_events.push((1, 60, 127));
    let res = evaluator.evaluate(&module, &shared_midi, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 1.0);

    // Verify cleared
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);
}

#[test]
fn test_osc_trigger() {
    let mut evaluator = ModuleEvaluator::new();
    let mut module = VorceModule {
        id: 1,
        name: "Test".to_string(),
        color: [1.0; 4],
        parts: vec![],
        connections: vec![],
        playback_mode: ModulePlaybackMode::LoopUntilManualSwitch,
        next_part_id: 1,
    };

    // Add an OSC trigger
    let t_id = module.add_part_with_type(
        ModulePartType::Trigger(TriggerType::Osc {
            address: "/trigger/1".to_string(),
        }),
        (0.0, 0.0),
    );

    let mut shared = vorce_core::module::SharedMediaState::default();

    // No OSC
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);

    // Send OSC
    shared
        .active_osc_messages
        .insert("/trigger/1".to_string(), vec![1.0]);
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 1.0);

    // Verify cleared
    shared.active_osc_messages.clear();
    let res = evaluator.evaluate(&module, &shared, 0);
    let val = res
        .trigger_values
        .get(&t_id)
        .and_then(|v| v.first())
        .copied()
        .unwrap_or(0.0);
    assert_eq!(val, 0.0);
}
