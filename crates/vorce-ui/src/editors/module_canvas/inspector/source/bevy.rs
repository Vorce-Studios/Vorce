// Extracted bevy module
use super::super::super::state::ModuleCanvas;
use super::super::common::render_info_label;
use crate::UIAction;
use egui::Ui;
use vorce_core::module::{BevyCameraMode, ModuleId, ModulePartId, SourceType};
pub fn render_bevy_source(
    _canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    _part_id: ModulePartId,
    _module_id: ModuleId,
    _shared_media_ids: &[String],
    _actions: &mut Vec<UIAction>,
) {
    match source {
        SourceType::Bevy3DText { text, font_size, color, position, rotation, alignment } => {
            ui.label("📝 3D Text");
            ui.add(egui::TextEdit::multiline(text).desired_rows(3).desired_width(f32::INFINITY));

            ui.horizontal(|ui| {
                ui.label("Size:");
                ui.add(egui::Slider::new(font_size, 1.0..=200.0));
            });

            ui.horizontal(|ui| {
                ui.label("Color:");
                ui.color_edit_button_rgba_unmultiplied(color);
            });

            ui.horizontal(|ui| {
                ui.label("Align:");
                egui::ComboBox::from_id_salt("text_align")
                    .selected_text(alignment.as_str())
                    .show_ui(ui, |ui| {
                        ui.selectable_value(alignment, "Left".to_string(), "Left");
                        ui.selectable_value(alignment, "Center".to_string(), "Center");
                        ui.selectable_value(alignment, "Right".to_string(), "Right");
                        ui.selectable_value(alignment, "Justify".to_string(), "Justify");
                    });
            });

            ui.separator();
            ui.label("📐 Transform 3D");

            ui.horizontal(|ui| {
                ui.label("Pos:");
                ui.add(egui::DragValue::new(&mut position[0]).prefix("X:"));
                ui.add(egui::DragValue::new(&mut position[1]).prefix("Y:"));
                ui.add(egui::DragValue::new(&mut position[2]).prefix("Z:"));
            });

            ui.horizontal(|ui| {
                ui.label("Rot:");
                ui.add(egui::DragValue::new(&mut rotation[0]).speed(1.0).prefix("X:").suffix("°"));
                ui.add(egui::DragValue::new(&mut rotation[1]).speed(1.0).prefix("Y:").suffix("°"));
                ui.add(egui::DragValue::new(&mut rotation[2]).speed(1.0).prefix("Z:").suffix("°"));
            });
        }
        SourceType::BevyCamera { mode, fov, active } => {
            ui.label("\u{1F3A5} Bevy Camera");
            ui.checkbox(active, "Active Control");
            ui.add(egui::Slider::new(fov, 10.0..=120.0).text("FOV"));

            ui.separator();
            ui.label("Mode:");

            egui::ComboBox::from_id_salt("camera_mode")
                .selected_text(match mode {
                    BevyCameraMode::Orbit { .. } => "Orbit",
                    BevyCameraMode::Fly { .. } => "Fly",
                    BevyCameraMode::Static { .. } => "Static",
                })
                .show_ui(ui, |ui| {
                    if ui
                        .selectable_label(matches!(mode, BevyCameraMode::Orbit { .. }), "Orbit")
                        .clicked()
                    {
                        *mode = BevyCameraMode::default(); // Default is Orbit
                    }
                    if ui
                        .selectable_label(matches!(mode, BevyCameraMode::Fly { .. }), "Fly")
                        .clicked()
                    {
                        *mode = BevyCameraMode::Fly { speed: 5.0, sensitivity: 1.0 };
                    }
                    if ui
                        .selectable_label(matches!(mode, BevyCameraMode::Static { .. }), "Static")
                        .clicked()
                    {
                        *mode = BevyCameraMode::Static {
                            position: [0.0, 5.0, 10.0],
                            look_at: [0.0, 0.0, 0.0],
                        };
                    }
                });

            ui.separator();
            match mode {
                BevyCameraMode::Orbit { radius, speed, target, height } => {
                    ui.label("Orbit Settings");
                    ui.add(egui::Slider::new(radius, 1.0..=50.0).text("Radius"));
                    ui.add(egui::Slider::new(speed, -90.0..=90.0).text("Speed (°/s)"));
                    ui.add(egui::Slider::new(height, -10.0..=20.0).text("Height"));

                    ui.label("Target:");
                    ui.horizontal(|ui| {
                        ui.add(egui::DragValue::new(&mut target[0]).prefix("X:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut target[1]).prefix("Y:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut target[2]).prefix("Z:").speed(0.1));
                    });
                }
                BevyCameraMode::Fly { speed, sensitivity: _ } => {
                    ui.label("Fly Settings");
                    ui.add(egui::Slider::new(speed, 0.0..=50.0).text("Speed"));
                    ui.label("Direction: Forward (Z-)");
                }
                BevyCameraMode::Static { position, look_at } => {
                    ui.label("Static Settings");
                    ui.label("Position:");
                    ui.horizontal(|ui| {
                        ui.add(egui::DragValue::new(&mut position[0]).prefix("X:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut position[1]).prefix("Y:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut position[2]).prefix("Z:").speed(0.1));
                    });
                    ui.label("Look At:");
                    ui.horizontal(|ui| {
                        ui.add(egui::DragValue::new(&mut look_at[0]).prefix("X:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut look_at[1]).prefix("Y:").speed(0.1));
                        ui.add(egui::DragValue::new(&mut look_at[2]).prefix("Z:").speed(0.1));
                    });
                }
            }
        }
        SourceType::BevyAtmosphere {
            turbidity,
            rayleigh,
            mie_coeff,
            mie_directional_g,
            sun_position,
            exposure,
        } => {
            ui.label("☁️ Atmosphere Settings");
            ui.separator();

            ui.add(egui::Slider::new(turbidity, 0.0..=10.0).text("Turbidity"));
            ui.add(egui::Slider::new(rayleigh, 0.0..=10.0).text("Rayleigh"));
            ui.add(egui::Slider::new(mie_coeff, 0.0..=0.1).text("Mie Coeff"));
            ui.add(egui::Slider::new(mie_directional_g, 0.0..=1.0).text("Mie Dir G"));
            ui.add(egui::Slider::new(exposure, 0.0..=10.0).text("Exposure"));

            ui.label("Sun Position (Azimuth, Elevation):");
            ui.horizontal(|ui| {
                ui.add(egui::DragValue::new(&mut sun_position.0).prefix("Az:").speed(0.1));
                ui.add(egui::DragValue::new(&mut sun_position.1).prefix("El:").speed(0.1));
            });
        }
        SourceType::BevyHexGrid {
            radius,
            rings,
            pointy_top,
            spacing,
            position,
            rotation,
            scale,
        } => {
            ui.label("\u{2B22} Hex Grid Settings");
            ui.separator();

            ui.add(egui::DragValue::new(radius).prefix("Radius:").speed(0.1));
            ui.add(egui::DragValue::new(rings).prefix("Rings:"));
            ui.add(egui::DragValue::new(spacing).prefix("Spacing:").speed(0.1));
            ui.checkbox(pointy_top, "Pointy Top");

            ui.label("Position:");
            ui.horizontal(|ui| {
                ui.add(egui::DragValue::new(&mut position[0]).prefix("X:").speed(0.1));
                ui.add(egui::DragValue::new(&mut position[1]).prefix("Y:").speed(0.1));
                ui.add(egui::DragValue::new(&mut position[2]).prefix("Z:").speed(0.1));
            });

            ui.label("Rotation:");
            ui.horizontal(|ui| {
                ui.add(egui::DragValue::new(&mut rotation[0]).prefix("X:").speed(1.0));
                ui.add(egui::DragValue::new(&mut rotation[1]).prefix("Y:").speed(1.0));
                ui.add(egui::DragValue::new(&mut rotation[2]).prefix("Z:").speed(1.0));
            });

            ui.add(egui::DragValue::new(scale).prefix("Scale:").speed(0.1));
        }
        SourceType::BevyParticles {
            rate,
            lifetime,
            speed,
            color_start,
            color_end,
            position,
            rotation,
        } => {
            ui.label("\u{2728} Particle System Settings");
            ui.separator();

            ui.add(egui::DragValue::new(rate).prefix("Rate:").speed(1.0));
            ui.add(egui::DragValue::new(lifetime).prefix("Lifetime:").speed(0.1));
            ui.add(egui::DragValue::new(speed).prefix("Speed:").speed(0.1));

            ui.horizontal(|ui| {
                ui.label("Start Color:");
                ui.color_edit_button_rgba_unmultiplied(color_start);
            });
            ui.horizontal(|ui| {
                ui.label("End Color:");
                ui.color_edit_button_rgba_unmultiplied(color_end);
            });

            ui.label("Position:");
            ui.horizontal(|ui| {
                ui.add(egui::DragValue::new(&mut position[0]).prefix("X:").speed(0.1));
                ui.add(egui::DragValue::new(&mut position[1]).prefix("Y:").speed(0.1));
                ui.add(egui::DragValue::new(&mut position[2]).prefix("Z:").speed(0.1));
            });

            ui.label("Rotation:");
            ui.horizontal(|ui| {
                ui.add(egui::DragValue::new(&mut rotation[0]).prefix("X:").speed(1.0));
                ui.add(egui::DragValue::new(&mut rotation[1]).prefix("Y:").speed(1.0));
                ui.add(egui::DragValue::new(&mut rotation[2]).prefix("Z:").speed(1.0));
            });
        }
        SourceType::Bevy3DShape {
            shape_type,
            position,
            rotation,
            scale,
            color,
            unlit,
            outline_width,
            outline_color,
            ..
        } => {
            ui.label("\u{1F9CA} Bevy 3D Shape");
            ui.separator();

            ui.horizontal(|ui| {
                ui.label("Shape:");
                egui::ComboBox::from_id_salt("shape_type_select")
                    .selected_text(format!("{:?}", shape_type))
                    .show_ui(ui, |ui| {
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Cube,
                            "Cube",
                        );
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Sphere,
                            "Sphere",
                        );
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Capsule,
                            "Capsule",
                        );
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Torus,
                            "Torus",
                        );
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Cylinder,
                            "Cylinder",
                        );
                        ui.selectable_value(
                            shape_type,
                            vorce_core::module::BevyShapeType::Plane,
                            "Plane",
                        );
                    });
            });

            ui.horizontal(|ui| {
                ui.label("Color:");
                ui.color_edit_button_rgba_unmultiplied(color);
            });

            ui.checkbox(unlit, "Unlit (No Shading)");

            ui.separator();

            ui.collapsing("📐 Transform (3D)", |ui| {
                ui.label("Position:");
                ui.horizontal(|ui| {
                    ui.add(egui::DragValue::new(&mut position[0]).speed(0.1).prefix("X: "));
                    ui.add(egui::DragValue::new(&mut position[1]).speed(0.1).prefix("Y: "));
                    ui.add(egui::DragValue::new(&mut position[2]).speed(0.1).prefix("Z: "));
                });

                ui.label("Rotation:");
                ui.horizontal(|ui| {
                    ui.add(
                        egui::DragValue::new(&mut rotation[0]).speed(1.0).prefix("X: ").suffix("°"),
                    );
                    ui.add(
                        egui::DragValue::new(&mut rotation[1]).speed(1.0).prefix("Y: ").suffix("°"),
                    );
                    ui.add(
                        egui::DragValue::new(&mut rotation[2]).speed(1.0).prefix("Z: ").suffix("°"),
                    );
                });

                ui.label("Scale:");
                ui.horizontal(|ui| {
                    ui.add(egui::DragValue::new(&mut scale[0]).speed(0.01).prefix("X: "));
                    ui.add(egui::DragValue::new(&mut scale[1]).speed(0.01).prefix("Y: "));
                    ui.add(egui::DragValue::new(&mut scale[2]).speed(0.01).prefix("Z: "));
                });
            });

            ui.separator();
            ui.collapsing("Outline", |ui| {
                ui.horizontal(|ui| {
                    ui.label("Width:");
                    ui.add(egui::Slider::new(outline_width, 0.0..=10.0));
                });
                ui.horizontal(|ui| {
                    ui.label("Color:");
                    ui.color_edit_button_rgba_unmultiplied(outline_color);
                });
            });
        }
        SourceType::Bevy3DModel {
            path,
            position,
            rotation,
            scale,
            color,
            unlit,
            outline_width,
            outline_color,
        } => {
            ui.label("\u{1F3AE} Bevy 3D Model");
            ui.horizontal(|ui| {
                ui.label("Model Path:");
                ui.text_edit_singleline(path);
            });
            ui.horizontal(|ui| {
                ui.label("Tint:");
                ui.color_edit_button_rgba_unmultiplied(color);
            });
            ui.checkbox(unlit, "Unlit (No Shading)");

            ui.separator();
            ui.collapsing("Transform (3D)", |ui| {
                ui.label("Position:");
                ui.horizontal(|ui| {
                    ui.add(egui::DragValue::new(&mut position[0]).speed(0.1).prefix("X: "));
                    ui.add(egui::DragValue::new(&mut position[1]).speed(0.1).prefix("Y: "));
                    ui.add(egui::DragValue::new(&mut position[2]).speed(0.1).prefix("Z: "));
                });

                ui.label("Rotation:");
                ui.horizontal(|ui| {
                    ui.add(
                        egui::DragValue::new(&mut rotation[0])
                            .speed(1.0)
                            .prefix("X: ")
                            .suffix(" deg"),
                    );
                    ui.add(
                        egui::DragValue::new(&mut rotation[1])
                            .speed(1.0)
                            .prefix("Y: ")
                            .suffix(" deg"),
                    );
                    ui.add(
                        egui::DragValue::new(&mut rotation[2])
                            .speed(1.0)
                            .prefix("Z: ")
                            .suffix(" deg"),
                    );
                });

                ui.label("Scale:");
                ui.horizontal(|ui| {
                    ui.add(egui::DragValue::new(&mut scale[0]).speed(0.01).prefix("X: "));
                    ui.add(egui::DragValue::new(&mut scale[1]).speed(0.01).prefix("Y: "));
                    ui.add(egui::DragValue::new(&mut scale[2]).speed(0.01).prefix("Z: "));
                });
            });

            ui.separator();
            ui.collapsing("Outline", |ui| {
                ui.horizontal(|ui| {
                    ui.label("Width:");
                    ui.add(egui::Slider::new(outline_width, 0.0..=10.0));
                });
                ui.horizontal(|ui| {
                    ui.label("Color:");
                    ui.color_edit_button_rgba_unmultiplied(outline_color);
                });
            });
        }
        SourceType::Bevy => {
            ui.label("\u{1F3AE} Bevy Scene");
            render_info_label(ui, "Rendering Internal 3D Scene");
            ui.small("The scene is rendered internally and available as 'bevy_output'");
        }
        _ => {}
    }
}
