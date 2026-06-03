use super::super::mesh;
use super::super::state::{LayerInspectorViewMode, ModuleCanvas};
use super::capabilities;
use super::common;
use egui::Ui;
use vorce_core::module::{BlendModeType, LayerType, MaskShape, MaskType, MeshType, ModulePartId};

fn render_layer_blend_mode_ui(ui: &mut Ui, id_salt: u64, blend_mode: &mut Option<BlendModeType>) {
    let blend_text =
        blend_mode.as_ref().map(|mode| format!("{mode:?}")).unwrap_or_else(|| "None".to_string());

    egui::ComboBox::from_id_salt(("layer_blend", id_salt)).selected_text(blend_text).show_ui(
        ui,
        |ui| {
            if ui.selectable_label(blend_mode.is_none(), "None").clicked() {
                *blend_mode = None;
            }

            for mode in [BlendModeType::Normal, BlendModeType::Add, BlendModeType::Multiply] {
                ui.add_enabled_ui(capabilities::is_blend_mode_supported(&mode), |ui| {
                    if ui
                        .selectable_label(blend_mode.as_ref() == Some(&mode), mode.name())
                        .clicked()
                    {
                        *blend_mode = Some(mode);
                    }
                });
            }
        },
    );

    if !blend_mode.as_ref().map(capabilities::is_blend_mode_supported).unwrap_or(true) {
        capabilities::render_unsupported_warning(
            ui,
            "Blend modes other than Normal are currently ignored in final render.",
        );
    }
}

#[allow(clippy::too_many_arguments)]
fn render_standard_layer_controls(
    render_mesh_ui: &mut impl FnMut(&mut Ui, &mut MeshType, u64, bool),
    show_mesh_editor: bool,
    ui: &mut Ui,
    name: &mut String,
    opacity: &mut f32,
    blend_mode: &mut Option<BlendModeType>,
    mesh: &mut MeshType,
    mapping_mode: &mut bool,
    mesh_id_salt: u64,
) {
    ui.text_edit_singleline(name);
    ui.add(egui::Slider::new(opacity, 0.0..=1.0).text("Opacity"));

    ui.horizontal(|ui| {
        ui.label("Blend Mode:");
        render_layer_blend_mode_ui(ui, mesh_id_salt, blend_mode);
    });

    ui.checkbox(mapping_mode, "Mapping Mode (Grid)");
    render_mesh_ui(ui, mesh, mesh_id_salt, show_mesh_editor);
}

/// Renders the configuration UI for a `ModulePartType::Layer`.
pub fn render_layer_ui(
    canvas: &mut ModuleCanvas,
    mesh_editor: &mut crate::editors::mesh_editor::MeshEditor,
    last_mesh_edit_id: &mut Option<u64>,
    ui: &mut Ui,
    layer: &mut LayerType,
    part_id: ModulePartId,
) {
    ui.label("Layer:");

    let mut render_mesh_ui =
        |ui: &mut Ui, mesh: &mut MeshType, id_salt: u64, show_visual_editor: bool| {
            mesh::render_mesh_editor_ui(
                mesh_editor,
                last_mesh_edit_id,
                ui,
                mesh,
                part_id,
                id_salt,
                show_visual_editor,
            );
        };

    let show_mesh_editor = canvas.layer_inspector_view_mode == LayerInspectorViewMode::MeshEditor;

    match layer {
        LayerType::Single { id, name, opacity, blend_mode, mesh, mapping_mode } => {
            ui.label("Single Layer");
            ui.horizontal(|ui| {
                ui.label("ID:");
                ui.add(egui::DragValue::new(id));
            });
            render_standard_layer_controls(
                &mut render_mesh_ui,
                show_mesh_editor,
                ui,
                name,
                opacity,
                blend_mode,
                mesh,
                mapping_mode,
                *id,
            );
        }
        LayerType::Group { name, opacity, blend_mode, mesh, mapping_mode } => {
            ui.label("Group Layer");
            render_standard_layer_controls(
                &mut render_mesh_ui,
                show_mesh_editor,
                ui,
                name,
                opacity,
                blend_mode,
                mesh,
                mapping_mode,
                9_999,
            );
        }
        LayerType::All { opacity, .. } => {
            ui.add_enabled_ui(false, |ui| {
                ui.label("Master Layer");
                ui.add(egui::Slider::new(opacity, 0.0..=1.0).text("Opacity"));
            });
            capabilities::render_unsupported_warning(
                ui,
                "Master layers are currently unsupported and will not be rendered.",
            );
        }
    }
}

/// Renders the configuration UI for a `ModulePartType::Mask`.
pub fn render_mask_ui(ui: &mut Ui, mask: &mut MaskType) {
    ui.label("Mask Type:");
    let supported = capabilities::is_mask_supported();
    ui.add_enabled_ui(supported, |ui| match mask {
        MaskType::File { path } => {
            ui.label("Mask File");
            if path.is_empty() {
                ui.horizontal(|ui| {
                    if ui.button("Select...").clicked() {
                        if let Some(picked) = rfd::FileDialog::new()
                            .add_filter("Image", &["png", "jpg", "jpeg", "webp", "bmp"])
                            .pick_file()
                        {
                            *path = picked.display().to_string();
                        }
                    }
                    common::render_info_label(ui, "No mask loaded");
                });
            } else {
                ui.horizontal(|ui| {
                    ui.add(egui::TextEdit::singleline(path).desired_width(120.0));
                    if ui.button("Open").on_hover_text("Select Mask File").clicked() {
                        if let Some(picked) = rfd::FileDialog::new()
                            .add_filter("Image", &["png", "jpg", "jpeg", "webp", "bmp"])
                            .pick_file()
                        {
                            *path = picked.display().to_string();
                        }
                    }
                });
            }
        }
        MaskType::Shape(shape) => {
            ui.label("Shape Mask");
            egui::ComboBox::from_id_salt("mask_shape").selected_text(format!("{shape:?}")).show_ui(
                ui,
                |ui| {
                    if ui.selectable_label(matches!(shape, MaskShape::Circle), "Circle").clicked() {
                        *shape = MaskShape::Circle;
                    }
                    if ui
                        .selectable_label(matches!(shape, MaskShape::Rectangle), "Rectangle")
                        .clicked()
                    {
                        *shape = MaskShape::Rectangle;
                    }
                    if ui
                        .selectable_label(matches!(shape, MaskShape::Triangle), "Triangle")
                        .clicked()
                    {
                        *shape = MaskShape::Triangle;
                    }
                    if ui.selectable_label(matches!(shape, MaskShape::Star), "Star").clicked() {
                        *shape = MaskShape::Star;
                    }
                    if ui.selectable_label(matches!(shape, MaskShape::Ellipse), "Ellipse").clicked()
                    {
                        *shape = MaskShape::Ellipse;
                    }
                },
            );
        }
        MaskType::Gradient { angle, softness } => {
            ui.label("Gradient Mask");
            ui.add(egui::Slider::new(angle, 0.0..=360.0).text("Angle"));
            ui.add(egui::Slider::new(softness, 0.0..=1.0).text("Softness"));
        }
    });

    if !supported {
        capabilities::render_unsupported_warning(
            ui,
            "Masks are currently gated because the active render path ignores them.",
        );
    }
}
