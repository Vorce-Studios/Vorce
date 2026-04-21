#[cfg(test)]
mod tests {
    use crate::editors::module_canvas::state::ModuleCanvas;
    use crate::editors::mesh_editor::MeshEditor;
    use crate::UIAction;
    use egui::{Ui, Context, RawInput};
    use vorce_core::module::{ModulePart, ModulePartId, ModulePartType, TriggerType, SourceType};
    use crate::editors::module_canvas::inspector::InspectorPreviewContext;
    use std::collections::HashMap;

    #[test]
    fn test_stale_snapshot_fix_vor_39() {
        let mut canvas = ModuleCanvas::default();
        let mut mesh_editor = MeshEditor::new();
        let mut last_mesh_edit_id = None;
        let mut actions = Vec::new();
        let ctx = Context::default();
        
        let mut part1 = ModulePart {
            id: 1,
            part_type: ModulePartType::Trigger(TriggerType::Beat),
            position: (0.0, 0.0),
            size: None,
            link_data: Default::default(),
            inputs: vec![],
            outputs: vec![],
            trigger_targets: HashMap::new(),
        };

        let mut part2 = ModulePart {
            id: 2,
            part_type: ModulePartType::Source(SourceType::SolidColor { color: [1.0, 0.0, 0.0, 1.0] }),
            position: (100.0, 100.0),
            size: None,
            link_data: Default::default(),
            inputs: vec![],
            outputs: vec![],
            trigger_targets: HashMap::new(),
        };

        let preview_context = InspectorPreviewContext::default();

        // 1. Simulate interaction with Part 1
        let mut raw_input = RawInput::default();
        raw_input.pointer.any_pressed = true;
        raw_input.pointer.any_down = true;

        ctx.run(raw_input.clone(), |ctx| {
            egui::CentralPanel::default().show(ctx, |ui| {
                canvas.render_inspector_for_part(
                    &mut mesh_editor,
                    &mut last_mesh_edit_id,
                    ui,
                    &mut part1,
                    &mut actions,
                    0,
                    &[],
                    &preview_context,
                );
            });
        });

        assert!(canvas.edit_snapshot.is_some());
        assert_eq!(canvas.edit_snapshot.as_ref().unwrap().id, 1);

        // 2. Simulate interaction with Part 2 (WITHOUT releasing first, or in a new frame)
        // This simulates moving the mouse/pointer between nodes while clicking or just fast switching.
        // Actually, render_inspector_for_part is usually called for ONE part (the selected one).
        // If the selection changes, the NEXT frame calls it with a different `part`.

        ctx.run(raw_input.clone(), |ctx| {
            egui::CentralPanel::default().show(ctx, |ui| {
                canvas.render_inspector_for_part(
                    &mut mesh_editor,
                    &mut last_mesh_edit_id,
                    ui,
                    &mut part2,
                    &mut actions,
                    0,
                    &[],
                    &preview_context,
                );
            });
        });

        // WITHOUT the fix, edit_snapshot would still be Part 1 because it's already Some.
        // WITH the fix, it should be updated to Part 2.
        assert_eq!(canvas.edit_snapshot.as_ref().unwrap().id, 2, "Snapshot should update to Part 2 when interacting with it");
    }
}
