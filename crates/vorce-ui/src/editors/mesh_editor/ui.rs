use super::state::*;
use super::types::*;
use crate::editors::mesh_editor::interaction::MeshEditorInteraction;
use egui::{Pos2, Rect, Sense, Stroke, Ui};

pub trait MeshEditorUi {
    fn ui(&mut self, ui: &mut Ui) -> Option<MeshEditorAction>;
    fn draw_grid(&self, painter: &egui::Painter, rect: Rect);
}

impl MeshEditorUi for MeshEditor {
    /// Render the mesh editor UI
    fn ui(&mut self, ui: &mut Ui) -> Option<MeshEditorAction> {
        let mut action = None;

        // Toolbar
        ui.horizontal(|ui| {
            ui.selectable_value(&mut self.mode, EditMode::Select, "Select");
            ui.selectable_value(&mut self.mode, EditMode::Add, "Add");
            ui.selectable_value(&mut self.mode, EditMode::Remove, "Remove");
            ui.selectable_value(&mut self.mode, EditMode::Bezier, "Bezier");

            ui.separator();

            ui.checkbox(&mut self.snap_to_grid, "Snap to Grid");
            if self.snap_to_grid {
                ui.add(egui::DragValue::new(&mut self.grid_size).prefix("Grid: "));
            }

            ui.separator();

            ui.label("Symmetry:");
            ui.selectable_value(&mut self.symmetry, SymmetryMode::None, "None");
            ui.selectable_value(&mut self.symmetry, SymmetryMode::Horizontal, "H");
            ui.selectable_value(&mut self.symmetry, SymmetryMode::Vertical, "V");
            ui.selectable_value(&mut self.symmetry, SymmetryMode::Both, "Both");

            ui.separator();

            if ui.button("Subdivide").clicked() {
                self.subdivide();
            }

            if ui.button("Create Quad").clicked() {
                self.create_quad(Pos2::new(400.0, 300.0), 200.0);
            }
        });

        ui.separator();

        // Canvas
        let (response, painter) = ui.allocate_painter(ui.available_size(), Sense::click_and_drag());

        // Draw grid if enabled
        if self.snap_to_grid {
            self.draw_grid(&painter, response.rect);
        }

        // Draw mesh faces
        for face in &self.faces {
            let points = [
                self.vertices[face.vertices[0]].position,
                self.vertices[face.vertices[1]].position,
                self.vertices[face.vertices[2]].position,
            ];

            painter.add(egui::Shape::convex_polygon(
                points.to_vec(),
                ui.visuals().selection.bg_fill.linear_multiply(0.2),
                Stroke::new(1.0, ui.visuals().text_color().linear_multiply(0.6)),
            ));
        }

        // Draw vertices
        for vertex in self.vertices.iter() {
            let color = if vertex.selected {
                ui.visuals().strong_text_color()
            } else {
                ui.visuals().text_color()
            };

            painter.circle_filled(vertex.position, 6.0, color);
            painter.circle_stroke(
                vertex.position,
                6.0,
                Stroke::new(2.0, ui.visuals().strong_text_color()),
            );

            // Draw Bezier control points if in Bezier mode
            if self.mode == EditMode::Bezier {
                if let Some(ctrl_in) = vertex.control_in {
                    let ctrl_pos = vertex.position + ctrl_in;
                    painter.line_segment(
                        [vertex.position, ctrl_pos],
                        Stroke::new(1.0, ui.visuals().text_color()),
                    );
                    painter.circle_filled(ctrl_pos, 4.0, ui.visuals().text_color());
                }

                if let Some(ctrl_out) = vertex.control_out {
                    let ctrl_pos = vertex.position + ctrl_out;
                    painter.line_segment(
                        [vertex.position, ctrl_pos],
                        Stroke::new(1.0, ui.visuals().strong_text_color()),
                    );
                    painter.circle_filled(ctrl_pos, 4.0, ui.visuals().strong_text_color());
                }
            }
        }

        // Handle interactions
        if let Some(pointer_pos) = response.interact_pointer_pos() {
            let input = InteractionInput {
                pointer_pos,
                clicked: response.clicked(),
                dragged: response.dragged(),
                drag_delta: response.drag_delta(),
                drag_started: response.drag_started(),
                drag_stopped: response.drag_stopped(),
            };

            if let Some(act) = self.handle_interaction(input) {
                action = Some(act);
            }
        }

        action
    }

    /// Draw grid background
    fn draw_grid(&self, painter: &egui::Painter, rect: Rect) {
        let color = painter.ctx().global_style().visuals.text_color().linear_multiply(0.1);

        let mut x = 0.0;
        while x < rect.width() {
            let pos_x = rect.min.x + x;
            painter.line_segment(
                [Pos2::new(pos_x, rect.min.y), Pos2::new(pos_x, rect.max.y)],
                Stroke::new(1.0, color),
            );
            x += self.grid_size;
        }

        let mut y = 0.0;
        while y < rect.height() {
            let pos_y = rect.min.y + y;
            painter.line_segment(
                [Pos2::new(rect.min.x, pos_y), Pos2::new(rect.max.x, pos_y)],
                Stroke::new(1.0, color),
            );
            y += self.grid_size;
        }
    }
}
