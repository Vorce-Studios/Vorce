use crate::app::core::app_struct::App;
use crate::app::core::app_struct::RuntimeRenderQueueItem;
use mapmap_core::audio::AudioAnalysis;
use std::collections::HashMap;

/// Orchestrates the evaluation of the module graph and synchronizes with the Bevy engine.
pub fn perform_evaluation(
    app: &mut App,
    modules_for_eval: &[u64],
    analysis: &AudioAnalysis,
    graph_dirty: bool,
) {
    app.render_queue.clear();
    app.render_queue.graph_revision = app.state.module_manager.graph_revision;
    app.ui_state.module_canvas.last_trigger_values.clear();
    let mut node_triggers = HashMap::new();

    for module_id in modules_for_eval {
        if let Some(module_ref) = app.state.module_manager.get_module(*module_id) {
            // Only sync graph structure to Bevy if it actually changed
            if graph_dirty {
                if let Some(runner) = &mut app.bevy_runner {
                    runner.apply_graph_state(module_ref);
                }
            }

            let eval_result = app.module_evaluator.evaluate(
                module_ref,
                &app.state.module_manager.shared_media,
                app.state.module_manager.graph_revision,
            );

            for (part_id, values) in &eval_result.trigger_values {
                let max_val = values.iter().cloned().fold(0.0, f32::max);
                node_triggers.insert((*module_id, *part_id), max_val);
                app.ui_state
                    .module_canvas
                    .last_trigger_values
                    .insert(*part_id, max_val);
            }

            let render_ops = app.module_evaluator.drain_render_ops();
            for render_op in render_ops {
                let mut diagnostics = Vec::new();

                if render_op.blend_mode.is_some() {
                    diagnostics.push(crate::app::core::app_struct::RenderDiagnostic {
                        module_id: *module_id,
                        part_id: render_op.layer_part_id,
                        severity: crate::app::core::app_struct::DiagnosticSeverity::Warning,
                        code: "blend_mode_unsupported".to_string(),
                        message: "Blend modes are currently only supported via specific compositing passes.".to_string(),
                    });
                }

                if !render_op.masks.is_empty() {
                    diagnostics.push(crate::app::core::app_struct::RenderDiagnostic {
                        module_id: *module_id,
                        part_id: render_op.layer_part_id,
                        severity: crate::app::core::app_struct::DiagnosticSeverity::Warning,
                        code: "masks_unsupported".to_string(),
                        message: "Masks are not yet supported in this render path.".to_string(),
                    });
                }

                let output_id = match render_op.output_type {
                    mapmap_core::module::OutputType::Projector { id, .. } => id,
                    _ => render_op.output_part_id,
                };

                let item = RuntimeRenderQueueItem {
                    module_id: *module_id,
                    render_op,
                    diagnostics,
                };
                app.render_queue
                    .items
                    .entry(output_id)
                    .or_default()
                    .push(item);
            }
        }
    }

    for ops in app.render_queue.items.values_mut() {
        ops.sort_by(|a, b| b.render_op.output_part_id.cmp(&a.render_op.output_part_id));
    }

    // Sync with Bevy (only if runner exists)
    if let Some(runner) = &mut app.bevy_runner {
        let trigger_data = mapmap_core::audio_reactive::AudioTriggerData {
            band_energies: analysis.band_energies,
            rms_volume: analysis.rms_volume,
            peak_volume: analysis.peak_volume,
            beat_detected: analysis.beat_detected,
            beat_strength: analysis.beat_strength,
            bpm: analysis.tempo_bpm,
        };
        runner.update(&trigger_data, &node_triggers);
    }
}
