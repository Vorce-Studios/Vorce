use egui::Color32;
use vorce_core::module::{
    BevyCameraMode, BlendModeType, EffectType, HueNodeType, LayerType, MaskShape, MaskType,
    ModulePartType, ModuleSocketType, ModulizerType, OutputType, PartType, SourceType, TriggerType,
};

pub fn get_part_style(
    part_type: &ModulePartType,
) -> (Color32, Color32, &'static str, &'static str) {
    match part_type {
        ModulePartType::Trigger(trigger) => {
            let name = match trigger {
                TriggerType::AudioFFT { .. } => "Audio FFT",
                TriggerType::Beat => "Beat",
                TriggerType::Midi { .. } => "MIDI",
                TriggerType::Osc { .. } => "OSC",
                TriggerType::Shortcut { .. } => "Shortcut",
                TriggerType::Random { .. } => "Random",
                TriggerType::Fixed { .. } => "Fixed Timer",
            };
            (
                crate::theme::colors::CYAN_ACCENT.linear_multiply(0.2),
                crate::theme::colors::CYAN_ACCENT,
                "⚡",
                name,
            )
        }
        ModulePartType::Source(SourceType::BevyAtmosphere { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "â˜ ï¸ ",
            "Atmosphere",
        ),
        ModulePartType::Source(SourceType::BevyHexGrid { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "\u{1F6D1}",
            "Hex Grid",
        ),
        ModulePartType::Source(SourceType::BevyParticles { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "\u{2728}",
            "Particles",
        ),
        ModulePartType::Source(SourceType::Bevy3DText { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "T",
            "3D Text",
        ),
        ModulePartType::Source(SourceType::BevyCamera { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "🎥",
            "Camera",
        ),
        ModulePartType::Source(SourceType::Bevy3DShape { .. }) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.15),
            crate::theme::colors::CYAN_ACCENT,
            "\u{1F9CA}",
            "3D Shape",
        ),
        ModulePartType::Source(source) => {
            let name = match source {
                SourceType::MediaFile { .. } => "Media File",
                SourceType::Shader { .. } => "Shader",
                SourceType::LiveInput { .. } => "Live Input",
                SourceType::NdiInput { .. } => "NDI Input",
                #[cfg(target_os = "windows")]
                SourceType::SpoutInput { .. } => "Spout Input",
                SourceType::VideoUni { .. } => "Video (Uni)",
                SourceType::ImageUni { .. } => "Image (Uni)",
                SourceType::VideoMulti { .. } => "Video (Multi)",
                SourceType::ImageMulti { .. } => "Image (Multi)",
                SourceType::Bevy => "Bevy Scene",
                SourceType::BevyAtmosphere { .. } => "Atmosphere",
                SourceType::BevyHexGrid { .. } => "Hex Grid",
                SourceType::BevyParticles { .. } => "Particles",
                SourceType::Bevy3DText { .. } => "3D Text",
                SourceType::BevyCamera { .. } => "Camera",
                SourceType::Bevy3DShape { .. } => "3D Shape",
                SourceType::Bevy3DModel { .. } => "3D Model",
            };
            (
                crate::theme::colors::CYAN_ACCENT.linear_multiply(0.2),
                crate::theme::colors::CYAN_ACCENT,
                "🎬",
                name,
            )
        }

        ModulePartType::Mask(mask) => {
            let name = match mask {
                MaskType::File { .. } => "File Mask",
                MaskType::Shape(shape) => match shape {
                    MaskShape::Circle => "Circle",
                    MaskShape::Rectangle => "Rectangle",
                    MaskShape::Triangle => "Triangle",
                    MaskShape::Star => "Star",
                    MaskShape::Ellipse => "Ellipse",
                },
                MaskType::Gradient { .. } => "Gradient",
            };
            (
                crate::theme::colors::CYAN_ACCENT.linear_multiply(0.25),
                crate::theme::colors::CYAN_ACCENT,
                "🎭",
                name,
            )
        }
        ModulePartType::Modulizer(mod_type) => {
            let name = match mod_type {
                ModulizerType::Effect { effect_type: effect, .. } => match effect {
                    EffectType::Blur => "Blur",
                    EffectType::Sharpen => "Sharpen",
                    EffectType::Invert => "Invert",
                    EffectType::Threshold => "Threshold",
                    EffectType::Brightness => "Brightness",
                    EffectType::Contrast => "Contrast",
                    EffectType::Saturation => "Saturation",
                    EffectType::HueShift => "Hue Shift",
                    EffectType::Colorize => "Colorize",
                    EffectType::Wave => "Wave",
                    EffectType::Spiral => "Spiral",
                    EffectType::Pinch => "Pinch",
                    EffectType::Mirror => "Mirror",
                    EffectType::Kaleidoscope => "Kaleidoscope",
                    EffectType::Pixelate => "Pixelate",
                    EffectType::Halftone => "Halftone",
                    EffectType::EdgeDetect => "Edge Detect",
                    EffectType::Posterize => "Posterize",
                    EffectType::Glitch => "Glitch",
                    EffectType::RgbSplit => "RGB Split",
                    EffectType::ChromaticAberration => "Chromatic",
                    EffectType::VHS => "VHS",
                    EffectType::FilmGrain => "Film Grain",
                    EffectType::Vignette => "Vignette",
                    EffectType::LoadLUT => "Load 3D LUT",
                    EffectType::ShaderGraph(_) => "Custom Graph",
                },
                ModulizerType::BlendMode(blend) => match blend {
                    BlendModeType::Normal => "Normal",
                    BlendModeType::Add => "Add",
                    BlendModeType::Multiply => "Multiply",
                    BlendModeType::Screen => "Screen",
                    BlendModeType::Overlay => "Overlay",
                    BlendModeType::Difference => "Difference",
                    BlendModeType::Exclusion => "Exclusion",
                },
                ModulizerType::AudioReactive { .. } => "Audio Reactive",
            };
            (
                crate::theme::colors::WARN_COLOR.linear_multiply(0.2),
                crate::theme::colors::WARN_COLOR,
                "ã€°ï¸ ",
                name,
            )
        }
        ModulePartType::Mesh(_) => (
            crate::theme::colors::CYAN_ACCENT.linear_multiply(0.2),
            crate::theme::colors::CYAN_ACCENT,
            "🕸️ï¸ ",
            "Mesh",
        ),
        ModulePartType::Layer(layer) => {
            let name = match layer {
                LayerType::Single { .. } => "Single Layer",
                LayerType::Group { .. } => "Layer Group",
                LayerType::All { .. } => "All Layers",
            };
            (
                crate::theme::colors::MINT_ACCENT.linear_multiply(0.2),
                crate::theme::colors::MINT_ACCENT,
                "📑",
                name,
            )
        }
        ModulePartType::Output(output) => {
            let name = match output {
                OutputType::Projector { .. } => "Projector",
                OutputType::NdiOutput { .. } => "NDI Output",
                #[cfg(target_os = "windows")]
                OutputType::Spout { .. } => "Spout Output",
                OutputType::Hue { .. } => "Philips Hue",
            };
            (
                crate::theme::colors::ERROR_COLOR.linear_multiply(0.2),
                crate::theme::colors::ERROR_COLOR,
                "📺",
                name,
            )
        }
        ModulePartType::Hue(hue) => {
            let name = match hue {
                HueNodeType::SingleLamp { .. } => "Single Lamp",
                HueNodeType::MultiLamp { .. } => "Multi Lamp",
                HueNodeType::EntertainmentGroup { .. } => "Entertainment Group",
            };
            (
                crate::theme::colors::WARN_COLOR.linear_multiply(0.2),
                crate::theme::colors::WARN_COLOR,
                "💡",
                name,
            )
        }
    }
}

pub fn get_part_category(part_type: &ModulePartType) -> &'static str {
    match part_type {
        ModulePartType::Trigger(_) => "Trigger",
        ModulePartType::Source(_) => "Source",
        ModulePartType::Mask(_) => "Mask",
        ModulePartType::Modulizer(_) => "Modulator",
        ModulePartType::Mesh(_) => "Mesh",
        ModulePartType::Layer(_) => "Layer",
        ModulePartType::Output(_) => "Output",
        ModulePartType::Hue(_) => "Hue",
    }
}

pub fn get_socket_color(socket_type: &ModuleSocketType) -> Color32 {
    match socket_type {
        ModuleSocketType::Trigger => crate::theme::colors::CYAN_ACCENT.linear_multiply(0.8),
        ModuleSocketType::Media => crate::theme::colors::CYAN_ACCENT,
        ModuleSocketType::Effect => crate::theme::colors::WARN_COLOR,
        ModuleSocketType::Layer => crate::theme::colors::MINT_ACCENT,
        ModuleSocketType::Output => crate::theme::colors::ERROR_COLOR,
        ModuleSocketType::Link => crate::theme::colors::STROKE_GREY,
    }
}

pub fn get_part_property_text(part_type: &ModulePartType) -> String {
    match part_type {
        ModulePartType::Trigger(trigger_type) => match trigger_type {
            TriggerType::AudioFFT { band, .. } => format!("\u{1F50A} Audio: {:?}", band),
            TriggerType::Random { .. } => "\u{1F3B2} Random".to_string(),
            TriggerType::Fixed { interval_ms, .. } => format!("⏱️ {}ms", interval_ms),
            TriggerType::Midi { channel, note, .. } => {
                format!("\u{1F3B9} Ch{} N{}", channel, note)
            }
            TriggerType::Osc { address } => format!("\u{1F4E1} {}", address),
            TriggerType::Shortcut { key_code, .. } => format!("âŒ¨ï¸  {}", key_code),
            TriggerType::Beat => "🥁 Beat".to_string(),
        },
        ModulePartType::Source(source_type) => match source_type {
            SourceType::MediaFile { path, .. } => {
                if path.is_empty() {
                    "📁 Select file...".to_string()
                } else {
                    format!("📁 {}", path.split(['/', '\\']).next_back().unwrap_or(path))
                }
            }
            SourceType::Shader { name, .. } => format!("\u{1F3A8} {}", name),
            SourceType::LiveInput { device_id } => format!("\u{1F4F9} Device {}", device_id),
            SourceType::NdiInput { source_name } => {
                format!("\u{1F4E1} {}", source_name.as_deref().unwrap_or("None"))
            }
            SourceType::Bevy => "\u{1F3AE} Bevy Scene".to_string(),
            #[cfg(target_os = "windows")]
            SourceType::SpoutInput { sender_name } => format!("\u{1F6B0} {}", sender_name),
            SourceType::VideoUni { path, .. } => {
                if path.is_empty() {
                    "📁 Select video...".to_string()
                } else {
                    format!("\u{1F4F9} {}", path.split(['/', '\\']).next_back().unwrap_or(path))
                }
            }
            SourceType::ImageUni { path, .. } => {
                if path.is_empty() {
                    "\u{1F5BC} Select image...".to_string()
                } else {
                    format!("\u{1F5BC} {}", path.split(['/', '\\']).next_back().unwrap_or(path))
                }
            }
            SourceType::VideoMulti { shared_id, .. } => {
                format!("\u{1F4F9} Shared: {}", shared_id)
            }
            SourceType::ImageMulti { shared_id, .. } => {
                format!("\u{1F5BC} Shared: {}", shared_id)
            }
            SourceType::BevyAtmosphere { .. } => "â˜ ï¸  Atmosphere".to_string(),
            SourceType::BevyHexGrid { .. } => "\u{1F6D1} Hex Grid".to_string(),
            SourceType::BevyParticles { .. } => "\u{2728} Particles".to_string(),
            SourceType::Bevy3DText { text, .. } => {
                format!("T: {}", text.chars().take(10).collect::<String>())
            }
            SourceType::BevyCamera { mode, .. } => match mode {
                BevyCameraMode::Orbit { .. } => "\u{1F3A5} Orbit".to_string(),
                BevyCameraMode::Fly { .. } => "\u{1F3A5} Fly".to_string(),
                BevyCameraMode::Static { .. } => "\u{1F3A5} Static".to_string(),
            },
            SourceType::Bevy3DShape { shape_type, .. } => format!("\u{1F9CA} {:?}", shape_type),
            SourceType::Bevy3DModel { path, .. } => format!("\u{1F3AE} Model: {}", path),
        },
        ModulePartType::Mask(mask_type) => match mask_type {
            MaskType::File { path } => {
                if path.is_empty() {
                    "📁 Select mask...".to_string()
                } else {
                    format!("📁 {}", path.split(['/', '\\']).next_back().unwrap_or(path))
                }
            }
            MaskType::Shape(shape) => format!("\u{1F537} {:?}", shape),
            MaskType::Gradient { angle, .. } => {
                format!("\u{1F308} Gradient {}Â°", *angle as i32)
            }
        },
        ModulePartType::Modulizer(modulizer_type) => match modulizer_type {
            ModulizerType::Effect { effect_type: effect, .. } => {
                format!("\u{2728} {}", effect.name())
            }
            ModulizerType::BlendMode(blend) => format!("🔄 {}", blend.name()),
            ModulizerType::AudioReactive { source } => format!("\u{1F50A} {}", source),
        },
        ModulePartType::Mesh(_) => "🕸️ï¸  Mesh".to_string(),
        ModulePartType::Layer(layer_type) => {
            use vorce_core::module::LayerType;
            match layer_type {
                LayerType::Single { name, .. } => format!("\u{1F4D1} {}", name),
                LayerType::Group { name, .. } => format!("📁 {}", name),
                LayerType::All { .. } => "\u{1F4D1} All Layers".to_string(),
            }
        }
        ModulePartType::Output(output_type) => match output_type {
            OutputType::Projector { name, .. } => format!("\u{1F4FA} {}", name),
            OutputType::NdiOutput { name } => format!("\u{1F4E1} {}", name),
            #[cfg(target_os = "windows")]
            OutputType::Spout { name } => format!("\u{1F6B0} {}", name),
            OutputType::Hue { bridge_ip, .. } => {
                if bridge_ip.is_empty() {
                    "\u{1F4A1} Not Connected".to_string()
                } else {
                    format!("\u{1F4A1} {}", bridge_ip)
                }
            }
        },
        ModulePartType::Hue(hue) => match hue {
            HueNodeType::SingleLamp { name, .. } => {
                format!("\u{1F4A1} {}", name)
            }
            HueNodeType::MultiLamp { name, .. } => {
                format!("\u{1F4A1}\u{1F4A1} {}", name)
            }
            HueNodeType::EntertainmentGroup { name, .. } => {
                format!("\u{1F3AD} {}", name)
            }
        },
    }
}

pub fn part_type_from_module_part_type(mpt: &ModulePartType) -> PartType {
    match mpt {
        ModulePartType::Trigger(_) => PartType::Trigger,
        ModulePartType::Source(_) => PartType::Source,
        ModulePartType::Mask(_) => PartType::Mask,
        ModulePartType::Modulizer(_) => PartType::Modulator,
        ModulePartType::Mesh(_) => PartType::Mesh,
        ModulePartType::Layer(_) => PartType::Layer,
        ModulePartType::Output(_) => PartType::Output,
        ModulePartType::Hue(_) => PartType::Hue,
    }
}
