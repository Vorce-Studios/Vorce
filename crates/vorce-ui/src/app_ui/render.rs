use super::state::AppUI;
use crate::action::UIAction;
/// UI state for the application
impl AppUI {
    /// Render the icon demo panel
    pub fn render_icon_demo(&mut self, ctx: &egui::Context) {
        self.icon_demo_panel.ui(ctx, self.icon_manager.as_ref(), &self.i18n);
    }
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
