use crate::module::{
    HueNodeType, LayerType, LinkBehavior, LinkMode, ModulePartType, OutputType, SharedMediaState, SourceType,
    VorceModule,
};
use crate::module_eval::types::ModuleGraphIndices;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use super::state::ModuleEvaluator;
use super::result::{ModuleEvalResult, SourceCommand};
use crate::module_eval::types::primary_render_connection_idx;

impl ModuleEvaluator {
    fn rgb_to_hue_saturation(color: [f32; 3]) -> (f32, f32) {
        let r = color[0].clamp(0.0, 1.0);
        let g = color[1].clamp(0.0, 1.0);
        let b = color[2].clamp(0.0, 1.0);
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let delta = max - min;

        let hue = if delta <= f32::EPSILON {
            0.0
        } else if max == r {
            (((g - b) / delta).rem_euclid(6.0)) / 6.0
        } else if max == g {
            (((b - r) / delta) + 2.0) / 6.0
        } else {
            (((r - g) / delta) + 4.0) / 6.0
        };
        let saturation = if max <= f32::EPSILON { 0.0 } else { delta / max };

        (hue, saturation)
    }
    #[allow(clippy::type_complexity)]
    fn hue_node_defaults(
        hue_node: &HueNodeType,
    ) -> (f32, Option<f32>, Option<f32>, Option<f32>, Option<Vec<String>>) {
        match hue_node {
            HueNodeType::SingleLamp { id, brightness, color, effect_active, .. } => {
                let (hue, saturation) = Self::rgb_to_hue_saturation(*color);
                (
                    *brightness,
                    Some(hue),
                    Some(saturation),
                    effect_active.then_some(1.0),
                    Some(vec![id.clone()]),
                )
            }
            HueNodeType::MultiLamp { ids, brightness, color, effect_active, .. } => {
                let (hue, saturation) = Self::rgb_to_hue_saturation(*color);
                (
                    *brightness,
                    Some(hue),
                    Some(saturation),
                    effect_active.then_some(1.0),
                    Some(ids.clone()),
                )
            }
            HueNodeType::EntertainmentGroup { brightness, color, effect_active, .. } => {
                let (hue, saturation) = Self::rgb_to_hue_saturation(*color);
                (*brightness, Some(hue), Some(saturation), effect_active.then_some(1.0), None)
            }
        }
    }
    /// Evaluate the module graph for the current frame.
    pub fn evaluate(
        &mut self,
        module: &VorceModule,
        shared_state: &SharedMediaState,
        graph_revision: u64,
    ) -> &mut ModuleEvalResult {
        let mut rng = rand::rng();
        let now = Instant::now();

        self.current_dt = now.duration_since(self.last_eval_time).as_secs_f32().min(0.5);
        self.last_eval_time = now;
        self.current_frame = self.current_frame.wrapping_add(1);

        // Clear previous result for reuse
        self.cached_result.clear();
        let indices_valid = if let Some(cache) = self.indices_cache.get(&module.id) {
            cache.last_revision == graph_revision
        } else {
            false
        };
        if !indices_valid {
            // Rebuild cache
            let mut part_index_cache = HashMap::new();
            let mut conn_index_cache = HashMap::new();
            for (idx, part) in module.parts.iter().enumerate() {
                part_index_cache.insert(part.id, idx);
            }
            for (idx, conn) in module.connections.iter().enumerate() {
                conn_index_cache.entry(conn.to_part).or_insert_with(Vec::new).push(idx);
            }
            self.indices_cache.insert(
                module.id,
                Arc::new(ModuleGraphIndices {
                    part_index_cache,
                    conn_index_cache,
                    last_revision: graph_revision,
                }),
            );
        }

        // Clone the Arc to avoid borrowing self.indices_cache while borrowing self mutably later
        let indices = self.indices_cache[&module.id].clone();

        // Step 1: Evaluate all trigger nodes
        for part in &module.parts {
            if let ModulePartType::Trigger(trigger_type) = &part.part_type {
                let state = self.trigger_states.entry(part.id).or_default();
                let values = self.cached_result.trigger_values.entry(part.id).or_default();
                values.clear();

                let manual_fired = self.manual_triggers.contains(&part.id);
                Self::compute_trigger_output(
                    trigger_type,
                    state,
                    &self.audio_trigger_data,
                    self.start_time,
                    shared_state,
                    &self.active_keys,
                    manual_fired,
                    values,
                    &mut rng,
                );
            }
        }
        let mut trigger_inputs =
            self.compute_trigger_inputs(module, &self.cached_result.trigger_values);
        for part in &module.parts {
            if part.link_data.mode == LinkMode::Master {
                let mut activity = 1.0;
                if part.link_data.trigger_input_enabled {
                    activity = trigger_inputs.get(&part.id).copied().unwrap_or(0.0);
                }
                if !part.outputs.is_empty() {
                    let output_count = part.outputs.len();
                    let values = self.cached_result.trigger_values.entry(part.id).or_default();
                    values.clear();
                    values.resize(output_count, 0.0);
                    values[output_count - 1] = activity;
                }
            }
        }

        // Step 4: Second propagation (Master Link Out -> Slave Link In)
        trigger_inputs = self.compute_trigger_inputs(module, &self.cached_result.trigger_values);

        // Step 5: Process Slave Behaviors (Invert Link Input)
        for part in &module.parts {
            if part.link_data.mode == LinkMode::Slave {
                if let Some(val) = trigger_inputs.get_mut(&part.id) {
                    if part.link_data.behavior == LinkBehavior::Inverted {
                        *val = 1.0 - (*val).clamp(0.0, 1.0);
                    }
                }
            }
        }

        // Step 6: Generate source commands
        let socket_inputs = self.compute_socket_inputs(module, &self.cached_result.trigger_values);

        for part in &module.parts {
            if let ModulePartType::Source(source_type) = &part.part_type {
                // Default to 1.0 (playing) so media files play even if no trigger is attached
                let trigger_value = trigger_inputs.get(&part.id).copied().unwrap_or(1.0);
                if let Some(mut cmd) =
                    self.create_source_command(source_type, trigger_value, shared_state)
                {
                    for (socket_idx, config) in &part.trigger_targets {
                        if let Some(socket_vals) = socket_inputs.get(&part.id) {
                            if let Some(&raw_val) = socket_vals.get(socket_idx) {
                                let val = self.apply_smoothing(
                                    part.id,
                                    *socket_idx,
                                    config.apply(raw_val),
                                    &config.mode,
                                );
                                match (&mut cmd, &config.target) {
                                    (
                                        SourceCommand::Bevy3DModel { position, .. },
                                        crate::module::TriggerTarget::Position3D,
                                    ) => {
                                        position[0] = val;
                                        position[1] = val;
                                        position[2] = val;
                                    }
                                    (
                                        SourceCommand::Bevy3DModel { scale, .. },
                                        crate::module::TriggerTarget::Scale3D,
                                    ) => {
                                        scale[0] = val;
                                        scale[1] = val;
                                        scale[2] = val;
                                    }
                                    _ => {}
                                }
                            }
                        }
                    }
                    self.cached_result.source_commands.insert(part.id, cmd);
                }
            }
            // Generate output commands for Hue (which acts like a Sink/Output)
            if let ModulePartType::Output(OutputType::Hue { .. }) = &part.part_type {
                let trigger_value = trigger_inputs.get(&part.id).copied().unwrap_or(0.0);
                self.cached_result.source_commands.insert(
                    part.id,
                    SourceCommand::HueOutput {
                        brightness: trigger_value,
                        hue: None,
                        saturation: None,
                        strobe: None,
                        ids: None,
                    },
                );
            }

            // Generate output commands for New Hue Nodes
            if let ModulePartType::Hue(hue_node) = &part.part_type {
                let (default_brightness, default_hue, default_saturation, default_strobe, ids) =
                    Self::hue_node_defaults(hue_node);
                let brightness = socket_inputs
                    .get(&part.id)
                    .and_then(|m| m.get(&0))
                    .copied()
                    .unwrap_or(default_brightness);
                let hue =
                    socket_inputs.get(&part.id).and_then(|m| m.get(&1)).copied().or(default_hue);
                let strobe =
                    socket_inputs.get(&part.id).and_then(|m| m.get(&2)).copied().or(default_strobe);
                self.cached_result.source_commands.insert(
                    part.id,
                    SourceCommand::HueOutput {
                        brightness,
                        hue,
                        saturation: default_saturation,
                        strobe,
                        ids,
                    },
                );
            }
        }

        // Step 4: Trace Render Pipeline
        for part in &module.parts {
            if let ModulePartType::Output(output_type) = &part.part_type {
                if let Some(conn_idx) = primary_render_connection_idx(module, &indices, part.id) {
                    let conn = &module.connections[conn_idx];

                    // Look up the layer part
                    if let Some(&layer_idx) = indices.part_index_cache.get(&conn.from_part) {
                        let layer_part = &module.parts[layer_idx];
                        let link_opacity =
                            trigger_inputs.get(&layer_part.id).copied().unwrap_or(1.0);
                        if let ModulePartType::Layer(layer_type) = &layer_part.part_type {
                            let (mesh, opacity, blend_mode, mapping_mode) = match layer_type {
                                LayerType::Single {
                                    mesh,
                                    opacity,
                                    blend_mode,
                                    mapping_mode,
                                    ..
                                } => (mesh, opacity, blend_mode, mapping_mode),
                                LayerType::Group {
                                    mesh,
                                    opacity,
                                    blend_mode,
                                    mapping_mode,
                                    ..
                                } => (mesh, opacity, blend_mode, mapping_mode),
                                _ => continue,
                            };
                            let mut op = self.get_spare_render_op();
                            op.output_part_id = part.id;
                            op.output_type = output_type.clone();
                            op.layer_part_id = layer_part.id;
                            op.opacity = *opacity * link_opacity;
                            op.blend_mode = *blend_mode;
                            op.mapping_mode = *mapping_mode;
                            self.trace_chain_into(layer_part.id, module, &mut op, mesh, &indices);
                            self.cached_result.render_ops.push(op);
                        }
                    } else {
                        tracing::warn!(
                            "ModuleEval: Output {} connected to non-Layer node {}",
                            part.id,
                            conn.from_part
                        );
                    }
                }
            }
        }

        // Final step: Clear triggers for next frame
        self.manual_triggers.clear();
        self.midi_triggers.clear();
        self.osc_triggers.clear();

        &mut self.cached_result
    }
    fn create_source_command(
        &self,
        source_type: &SourceType,
        trigger_value: f32,
        shared_state: &SharedMediaState,
    ) -> Option<SourceCommand> {
        if trigger_value < 0.1 {
            return None;
        }
        match source_type {
            SourceType::MediaFile { path, .. }
            | SourceType::VideoUni { path, .. }
            | SourceType::ImageUni { path, .. } => {
                if path.is_empty() {
                    return None;
                }
                Some(SourceCommand::PlayMedia { path: path.clone(), trigger_value })
            }
            SourceType::VideoMulti { shared_id, .. } | SourceType::ImageMulti { shared_id, .. } => {
                shared_state.get(shared_id).map(|item| SourceCommand::PlaySharedMedia {
                    id: shared_id.clone(),
                    path: item.path.clone(),
                    trigger_value,
                })
            }
            SourceType::Shader { name, params } => Some(SourceCommand::PlayShader {
                name: name.clone(),
                params: params.clone(),
                trigger_value,
            }),
            SourceType::NdiInput { source_name } => {
                Some(SourceCommand::NdiInput { source_name: source_name.clone(), trigger_value })
            }
            SourceType::LiveInput { device_id } => {
                Some(SourceCommand::LiveInput { device_id: *device_id, trigger_value })
            }
            #[cfg(target_os = "windows")]
            SourceType::SpoutInput { sender_name } => {
                Some(SourceCommand::SpoutInput { sender_name: sender_name.clone(), trigger_value })
            }
            SourceType::Bevy3DModel { path, position, rotation, scale, .. } => {
                Some(SourceCommand::Bevy3DModel {
                    path: path.clone(),
                    position: *position,
                    rotation: *rotation,
                    scale: *scale,
                    trigger_value,
                })
            }
            _ => Some(SourceCommand::BevyInput { trigger_value }),
        }
    }
}
