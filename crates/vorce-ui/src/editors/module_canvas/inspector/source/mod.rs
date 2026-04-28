pub mod bevy;
pub mod inputs;
pub mod media;
pub mod shader;

use super::super::state::ModuleCanvas;
use crate::UIAction;
use egui::Ui;
use vorce_core::module::{ModuleId, ModulePartId, SourceType};

/// Renders the configuration UI for a `ModulePartType::Source`.
pub fn render_source_ui(
    canvas: &mut ModuleCanvas,
    ui: &mut Ui,
    source: &mut SourceType,
    part_id: ModulePartId,
    module_id: ModuleId,
    shared_media_ids: &[String],
    actions: &mut Vec<UIAction>,
) {
    ui.horizontal(|ui| {
        ui.label("Source Type:");
        let current_mode = match source {
            SourceType::MediaFile { .. } => "\u{1F4F9} Media File",
            SourceType::VideoUni { .. } => "\u{1F4F9} Video (Uni)",
            SourceType::ImageUni { .. } => "\u{1F5BC} Image (Uni)",
            SourceType::VideoMulti { .. } => "\u{1F517} Video (Multi)",
            SourceType::ImageMulti { .. } => "\u{1F517} Image (Multi)",
            SourceType::Shader { .. } => "\u{1F3A8} Shader",
            SourceType::LiveInput { .. } => "\u{1F4F9} Live Input",
            SourceType::NdiInput { .. } => "\u{1F4E1} NDI Input",
            #[cfg(target_os = "windows")]
            SourceType::SpoutInput { .. } => "\u{1F6B0} Spout Input",
            SourceType::Bevy => "\u{1F3AE} Bevy Scene",
            SourceType::BevyAtmosphere { .. } => "☁️ Atmosphere",
            SourceType::BevyHexGrid { .. } => "\u{1F6D1} Hex Grid",
            SourceType::BevyParticles { .. } => "\u{2728} Particles",
            SourceType::Bevy3DShape { .. } => "\u{1F9CA} 3D Shape",
            SourceType::Bevy3DText { .. } => "📝 3D Text",
            SourceType::BevyCamera { .. } => "\u{1F3A5} Bevy Camera",
            SourceType::Bevy3DModel { .. } => "\u{1F3AE} 3D Model",
        };

        let mut next_type = None;
        egui::ComboBox::from_id_salt(format!("{}_source_type_picker", part_id))
            .selected_text(current_mode)
            .show_ui(ui, |ui| {
                ui.label("--- File Based ---");
                if ui
                    .selectable_label(
                        matches!(source, SourceType::MediaFile { .. }),
                        "\u{1F4F9} Media File",
                    )
                    .clicked()
                {
                    next_type = Some("MediaFile");
                }
                if ui
                    .selectable_label(
                        matches!(source, SourceType::VideoUni { .. }),
                        "\u{1F4F9} Video (Uni)",
                    )
                    .clicked()
                {
                    next_type = Some("VideoUni");
                }
                if ui
                    .selectable_label(
                        matches!(source, SourceType::ImageUni { .. }),
                        "\u{1F5BC} Image (Uni)",
                    )
                    .clicked()
                {
                    next_type = Some("ImageUni");
                }

                ui.label("--- Shared ---");
                if ui
                    .selectable_label(
                        matches!(source, SourceType::VideoMulti { .. }),
                        "\u{1F517} Video (Multi)",
                    )
                    .clicked()
                {
                    next_type = Some("VideoMulti");
                }
                if ui
                    .selectable_label(
                        matches!(source, SourceType::ImageMulti { .. }),
                        "\u{1F517} Image (Multi)",
                    )
                    .clicked()
                {
                    next_type = Some("ImageMulti");
                }
            });

        if let Some(t) = next_type {
            let path = match source {
                SourceType::MediaFile { path, .. } => path.clone(),
                SourceType::VideoUni { path, .. } => path.clone(),
                SourceType::ImageUni { path, .. } => path.clone(),
                _ => String::new(),
            };
            let shared_id = match source {
                SourceType::VideoMulti { shared_id, .. } => shared_id.clone(),
                SourceType::ImageMulti { shared_id, .. } => shared_id.clone(),
                _ => String::new(),
            };

            *source = match t {
                "MediaFile" => {
                    SourceType::new_media_file(if path.is_empty() { shared_id } else { path })
                }
                "VideoUni" => SourceType::VideoUni {
                    path: if path.is_empty() { shared_id } else { path },
                    speed: 1.0,
                    loop_enabled: true,
                    start_time: 0.0,
                    end_time: 0.0,
                    opacity: 1.0,
                    blend_mode: None,
                    brightness: 0.0,
                    contrast: 1.0,
                    saturation: 1.0,
                    hue_shift: 0.0,
                    scale_x: 1.0,
                    scale_y: 1.0,
                    rotation: 0.0,
                    offset_x: 0.0,
                    offset_y: 0.0,
                    target_width: None,
                    target_height: None,
                    target_fps: None,
                    flip_horizontal: false,
                    flip_vertical: false,
                    reverse_playback: false,
                },
                "ImageUni" => SourceType::ImageUni {
                    path: if path.is_empty() { shared_id } else { path },
                    opacity: 1.0,
                    blend_mode: None,
                    brightness: 0.0,
                    contrast: 1.0,
                    saturation: 1.0,
                    hue_shift: 0.0,
                    scale_x: 1.0,
                    scale_y: 1.0,
                    rotation: 0.0,
                    offset_x: 0.0,
                    offset_y: 0.0,
                    target_width: None,
                    target_height: None,
                    flip_horizontal: false,
                    flip_vertical: false,
                },
                "VideoMulti" => SourceType::VideoMulti {
                    shared_id: if shared_id.is_empty() { path } else { shared_id },
                    opacity: 1.0,
                    blend_mode: None,
                    brightness: 0.0,
                    contrast: 1.0,
                    saturation: 1.0,
                    hue_shift: 0.0,
                    scale_x: 1.0,
                    scale_y: 1.0,
                    rotation: 0.0,
                    offset_x: 0.0,
                    offset_y: 0.0,
                    flip_horizontal: false,
                    flip_vertical: false,
                },
                "ImageMulti" => SourceType::ImageMulti {
                    shared_id: if shared_id.is_empty() { path } else { shared_id },
                    opacity: 1.0,
                    blend_mode: None,
                    brightness: 0.0,
                    contrast: 1.0,
                    saturation: 1.0,
                    hue_shift: 0.0,
                    scale_x: 1.0,
                    scale_y: 1.0,
                    rotation: 0.0,
                    offset_x: 0.0,
                    offset_y: 0.0,
                    flip_horizontal: false,
                    flip_vertical: false,
                },
                "NdiInput" => SourceType::NdiInput { source_name: None },
                _ => source.clone(),
            };
        }
    });

    ui.separator();

    match source {
        SourceType::MediaFile { .. }
        | SourceType::VideoUni { .. }
        | SourceType::ImageUni { .. }
        | SourceType::VideoMulti { .. }
        | SourceType::ImageMulti { .. } => {
            media::render_media_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        SourceType::Shader { .. } => {
            shader::render_shader_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        SourceType::Bevy3DText { .. }
        | SourceType::BevyCamera { .. }
        | SourceType::BevyAtmosphere { .. }
        | SourceType::BevyHexGrid { .. }
        | SourceType::BevyParticles { .. }
        | SourceType::Bevy3DShape { .. }
        | SourceType::Bevy3DModel { .. }
        | SourceType::Bevy => {
            bevy::render_bevy_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        #[cfg(feature = "ndi")]
        SourceType::NdiInput { .. } => {
            inputs::render_inputs_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        #[cfg(target_os = "windows")]
        SourceType::SpoutInput { .. } => {
            inputs::render_inputs_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        SourceType::LiveInput { .. } => {
            inputs::render_inputs_source(
                canvas,
                ui,
                source,
                part_id,
                module_id,
                shared_media_ids,
                actions,
            );
        }
        _ => {}
    }
}
