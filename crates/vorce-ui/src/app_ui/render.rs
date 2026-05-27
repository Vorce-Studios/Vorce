use crate::action::UIAction;
use crate::AppUI;

impl AppUI {
    /// Render the media browser as left side panel
    #[allow(deprecated)]
    pub fn render_media_browser(&mut self, ctx: &egui::Context) {
        if !self.show_media_browser {
            return;
        }

        egui::Panel::left("media_browser_panel")
            .resizable(true)
            .default_size(280.0)
            .min_size(200.0)
            .max_size(400.0)
            .frame(crate::widgets::panel::cyber_panel_frame(&ctx.global_style()))
            .show(ctx, |ui: &mut egui::Ui| {
                crate::widgets::panel::render_panel_header(
                    ui,
                    &self.i18n.t("panel-media-browser"),
                    |ui| {
                        if ui.button("✕").on_hover_text("Close Media Browser").clicked() {
                            self.show_media_browser = false;
                        }
                    },
                );

                egui::Frame::default().inner_margin(egui::Margin::symmetric(8, 8)).show(ui, |ui| {
                    let _ = self.media_browser.ui(ui, &self.i18n, self.icon_manager.as_ref());
                });
            });
    }

    /// Render the control panel
    pub fn render_controls(&mut self, ctx: &egui::Context) {
        if !self.show_controls {
            return;
        }

        egui::Window::new(self.i18n.t("panel-playback"))
            .default_size([320.0, 360.0])
            .frame(crate::widgets::panel::cyber_panel_frame(&ctx.global_style()))
            .show(ctx, |ui| {
                crate::widgets::panel::render_panel_header(
                    ui,
                    &self.i18n.t("header-video-playback"),
                    |_| {},
                );
                ui.add_space(8.0);

                // Transport controls
                ui.horizontal(|ui| {
                    if ui.button(self.i18n.t("btn-play")).clicked() {
                        self.actions.push(UIAction::Play);
                    }
                    if ui.button(self.i18n.t("btn-pause")).clicked() {
                        self.actions.push(UIAction::Pause);
                    }
                    if ui.button(self.i18n.t("btn-stop")).clicked() {
                        self.actions.push(UIAction::Stop);
                    }
                });

                ui.separator();

                // Speed control
                let old_speed = self.playback_speed;
                ui.add(
                    egui::Slider::new(&mut self.playback_speed, 0.1..=2.0)
                        .text(self.i18n.t("label-speed")),
                );
                if (self.playback_speed - old_speed).abs() > 0.001 {
                    self.actions.push(UIAction::SetSpeed(self.playback_speed));
                }

                // Loop control
                ui.label(self.i18n.t("label-mode"));
                egui::ComboBox::from_label(self.i18n.t("label-mode"))
                    .selected_text(match self.loop_mode {
                        vorce_media::LoopMode::Loop => self.i18n.t("mode-loop"),
                        vorce_media::LoopMode::PlayOnce => self.i18n.t("mode-play-once"),
                    })
                    .show_ui(ui, |ui: &mut egui::Ui| {
                        if ui
                            .selectable_value(
                                &mut self.loop_mode,
                                vorce_media::LoopMode::Loop,
                                self.i18n.t("mode-loop"),
                            )
                            .clicked()
                        {
                            self.actions.push(UIAction::SetLoopMode(vorce_media::LoopMode::Loop));
                        }
                        if ui
                            .selectable_value(
                                &mut self.loop_mode,
                                vorce_media::LoopMode::PlayOnce,
                                self.i18n.t("mode-play-once"),
                            )
                            .clicked()
                        {
                            self.actions
                                .push(UIAction::SetLoopMode(vorce_media::LoopMode::PlayOnce));
                        }
                    });
            });
    }

    /// Render performance stats as top-right overlay (Phase 6 Migration)
    pub fn render_stats_overlay(&mut self, ctx: &egui::Context, fps: f32, frame_time_ms: f32) {
        if !self.show_stats {
            return;
        }

        // Use Area with anchor to position in top-right corner
        egui::Area::new(egui::Id::new("performance_overlay"))
            .anchor(egui::Align2::RIGHT_TOP, [-10.0, 50.0]) // Offset from menu bar
            .order(egui::Order::Foreground)
            .interactable(false)
            .show(ctx, |ui| {
                egui::Frame::default()
                    .fill(crate::core::theme::colors::DARKER_GREY.linear_multiply(0.9))
                    .corner_radius(egui::CornerRadius::ZERO)
                    .stroke(egui::Stroke::new(1.0, crate::core::theme::colors::STROKE_GREY))
                    .inner_margin(egui::Margin::symmetric(16, 8))
                    .show(ui, |ui| {
                        ui.horizontal(|ui| {
                            ui.label(
                                egui::RichText::new(format!("FPS: {:.0}", fps))
                                    .color(crate::core::theme::colors::MINT_ACCENT)
                                    .strong(),
                            );
                            ui.separator();
                            ui.label(
                                egui::RichText::new(format!("{:.1}ms", frame_time_ms))
                                    .color(crate::core::theme::colors::CYAN_ACCENT),
                            );
                        });
                    });
            });
    }

    /// Legacy floating window version (deprecated)
    pub fn render_stats(&mut self, ctx: &egui::Context, fps: f32, frame_time_ms: f32) {
        // Redirect to overlay version
        self.render_stats_overlay(ctx, fps, frame_time_ms);
    }

    /// Render the right-side inspector panel (docked)
    pub fn render_inspector(
        &mut self,
        ui: &mut egui::Ui,
        module_manager: &mut vorce_core::module::ModuleManager,
        layer_manager: &vorce_core::LayerManager,
        output_manager: &vorce_core::OutputManager,
        mapping_manager: &vorce_core::MappingManager,
    ) {
        if !self.show_inspector {
            return;
        }

        // Determine context priority: Module > Layer > Output
        let mut context = crate::panels::inspector::InspectorContext::None;
        let mut module_part_snapshot = None;

        // 1. Module Selection
        if self.show_module_canvas {
            if let Some(module_id) = self.module_canvas.active_module_id {
                // Collect shared media IDs before borrowing module mutably from manager
                let shared_media_ids: Vec<String> =
                    module_manager.shared_media.items.keys().cloned().collect();

                if let Some(part_id) = self.module_canvas.get_selected_part_id() {
                    module_part_snapshot =
                        module_manager.get_module(module_id).and_then(|module| {
                            module
                                .parts
                                .iter()
                                .find(|part| part.id == part_id)
                                .cloned()
                                .map(|part| (module_id, part_id, part))
                        });

                    if let Some(module) = module_manager.get_module_mut(module_id) {
                        context = crate::panels::inspector::InspectorContext::Module {
                            canvas: &mut self.module_canvas,
                            module,
                            part_id,
                            shared_media_ids,
                        };
                    }
                }
            }
        }

        // 2. Layer Selection (if not in module mode)
        if matches!(context, crate::panels::inspector::InspectorContext::None) {
            if let Some(id) = self.selected_layer_id {
                if let Some(layer) = layer_manager.get_layer(id) {
                    let index = layer_manager.layers().iter().position(|l| l.id == id).unwrap_or(0);

                    let first_mapping = layer
                        .mapping_ids
                        .first()
                        .and_then(|&mapping_id| mapping_manager.get_mapping(mapping_id));

                    context = crate::panels::inspector::InspectorContext::Layer {
                        layer,
                        transform: &layer.transform,
                        index,
                        first_mapping,
                    };
                }
            }
        }

        // 3. Output Selection
        if matches!(context, crate::panels::inspector::InspectorContext::None) {
            if let Some(id) = self.selected_output_id {
                if let Some(output) = output_manager.get_output(id) {
                    context = crate::panels::inspector::InspectorContext::Output(output);
                }
            }
        }

        let action = self.inspector_panel.show(ui, context, &self.i18n, &mut self.actions);

        if let Some((module_id, part_id, before_part)) = module_part_snapshot {
            let mut inspector_changed = false;
            if let Some(module) = module_manager.get_module_mut(module_id) {
                if let Some(after_part) =
                    module.parts.iter().find(|part| part.id == part_id).cloned()
                {
                    if after_part != before_part {
                        module.update_part_sockets(part_id);
                        inspector_changed = true;
                    }
                }
            }
            if inspector_changed {
                module_manager.mark_dirty();
            }
        }

        if let Some(action) = action {
            match action {
                crate::panels::inspector::InspectorAction::UpdateOpacity(id, val) => {
                    self.actions.push(crate::UIAction::SetLayerOpacity(id, val));
                }
                crate::panels::inspector::InspectorAction::UpdateTransform(id, transform) => {
                    self.actions.push(crate::UIAction::SetLayerTransform(id, transform));
                }
                crate::panels::inspector::InspectorAction::UpdateMappingMesh(id, mesh) => {
                    self.actions.push(crate::UIAction::UpdateMappingMesh(id, mesh));
                }
                crate::panels::inspector::InspectorAction::RequestClose => {
                    self.show_inspector = false;
                    self.user_config.show_inspector = false;
                    let _ = self.user_config.save();
                }
            }
        }
    }
    /// Render master controls panel (Phase 6 Migration)
    pub fn render_master_controls(
        &mut self,
        ctx: &egui::Context,
        layer_manager: &mut vorce_core::LayerManager,
    ) {
        if !self.show_master_controls {
            return;
        }

        egui::Window::new(self.i18n.t("panel-master")).default_size([360.0, 300.0]).show(
            ctx,
            |ui: &mut egui::Ui| {
                self.render_master_controls_embedded(ui, layer_manager);
            },
        );
    }

    /// Render master controls content (embedded)
    pub fn render_master_controls_embedded(
        &mut self,
        ui: &mut egui::Ui,
        layer_manager: &mut vorce_core::LayerManager,
    ) {
        // Determine learning state (capture values to avoid borrow conflict)
        let is_learning = self.is_midi_learn_mode;
        let last_active_element = self.controller_overlay.last_active_element.clone();
        let last_active_time = self.controller_overlay.last_active_time;

        let composition = &mut layer_manager.composition;

        let old_master_opacity = composition.master_opacity;
        let response = ui.add(
            egui::Slider::new(&mut composition.master_opacity, 0.0..=1.0)
                .text(self.i18n.t("label-master-opacity")),
        );
        Self::midi_learn_helper(
            ui,
            &response,
            vorce_control::target::ControlTarget::MasterOpacity,
            is_learning,
            last_active_element.as_ref(),
            last_active_time,
            &mut self.actions,
        );
        if (composition.master_opacity - old_master_opacity).abs() > 0.001 {
            self.actions.push(UIAction::SetMasterOpacity(composition.master_opacity));
        }

        // Master Speed
        let old_master_speed = composition.master_speed;
        let response = ui.add(
            egui::Slider::new(&mut composition.master_speed, 0.1..=10.0)
                .text(self.i18n.t("label-master-speed")),
        );
        Self::midi_learn_helper(
            ui,
            &response,
            vorce_control::target::ControlTarget::PlaybackSpeed(None),
            is_learning,
            last_active_element.as_ref(),
            last_active_time,
            &mut self.actions,
        );
        if (composition.master_speed - old_master_speed).abs() > 0.001 {
            self.actions.push(UIAction::SetMasterSpeed(composition.master_speed));
        }
    }

    /// Render Node Editor Window
    pub fn render_node_editor(&mut self, ctx: &egui::Context) {
        if !self.show_shader_graph {
            return;
        }

        let mut open = self.show_shader_graph;
        egui::Window::new(self.i18n.t("panel-node-editor"))
            .default_size([800.0, 600.0])
            .resizable(true)
            .vscroll(false) // Canvas handles panning
            .open(&mut open)
            .show(ctx, |ui: &mut egui::Ui| {
                if let Some(action) = self.node_editor_panel.ui(ui, &self.i18n) {
                    self.actions.push(UIAction::NodeAction(action));
                }
            });
        self.show_shader_graph = open;
    }
}
