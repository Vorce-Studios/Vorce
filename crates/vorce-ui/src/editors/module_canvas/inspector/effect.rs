use super::capabilities;
use super::common;
use egui::Ui;
use vorce_core::module::{BlendModeType, EffectType, ModulePartId, ModulizerType};

fn render_effect_choice(
    ui: &mut Ui,
    current: &EffectType,
    changed_type: &mut Option<EffectType>,
    candidate: EffectType,
    label: &str,
) {
    let supported = capabilities::is_effect_supported(&candidate);
    ui.add_enabled_ui(supported, |ui| {
        if ui.selectable_label(*current == candidate, label).clicked() {
            *changed_type = Some(candidate);
        }
    });
}

#[allow(clippy::too_many_arguments)]
fn render_param_slider(
    ui: &mut Ui,
    effect_type: &EffectType,
    part_id: ModulePartId,
    param_name: &str,
    val: &mut f32,
    range: std::ops::RangeInclusive<f32>,
    label: &str,
    actions: &mut Vec<crate::UIAction>,
    animator_bindings: &[vorce_core::effect_animation::EffectParameterBinding],
) {
    ui.horizontal(|ui| {
        ui.add(egui::Slider::new(val, range).text(label));
        // Convert module::EffectType to vorce_core::effects::EffectType for bindings
        let core_effect_type = match effect_type {
            EffectType::Blur => vorce_core::effects::EffectType::Blur,
            EffectType::Invert => vorce_core::effects::EffectType::Invert,
            EffectType::Brightness => vorce_core::effects::EffectType::ColorAdjust,
            EffectType::Contrast => vorce_core::effects::EffectType::ColorAdjust,
            EffectType::Saturation => vorce_core::effects::EffectType::ColorAdjust,
            EffectType::HueShift => vorce_core::effects::EffectType::HueShift,
            EffectType::Wave => vorce_core::effects::EffectType::Wave,
            EffectType::Mirror => vorce_core::effects::EffectType::Mirror,
            EffectType::Kaleidoscope => vorce_core::effects::EffectType::Kaleidoscope,
            EffectType::Pixelate => vorce_core::effects::EffectType::Pixelate,
            EffectType::EdgeDetect => vorce_core::effects::EffectType::EdgeDetect,
            EffectType::Glitch => vorce_core::effects::EffectType::Glitch,
            EffectType::RgbSplit => vorce_core::effects::EffectType::RgbSplit,
            EffectType::ChromaticAberration => vorce_core::effects::EffectType::ChromaticAberration,
            EffectType::FilmGrain => vorce_core::effects::EffectType::FilmGrain,
            EffectType::Vignette => vorce_core::effects::EffectType::Vignette,
            EffectType::LoadLUT => vorce_core::effects::EffectType::LoadLUT {
                path: "".to_string(),
            },
            EffectType::ShaderGraph(id) => vorce_core::effects::EffectType::ShaderGraph(*id),
            _ => vorce_core::effects::EffectType::Custom,
        };

        let is_bound = animator_bindings.iter().any(|b| {
            b.effect_type == core_effect_type
                && b.effect_instance == part_id
                && b.parameter_name == param_name
        });

        let button_text = if is_bound { "★" } else { "☆" };
        let tooltip = if is_bound {
            "Unbind from Timeline"
        } else {
            "Bind to Timeline"
        };

        if ui.button(button_text).on_hover_text(tooltip).clicked() {
            actions.push(crate::UIAction::ToggleEffectParameterBinding {
                effect_type: core_effect_type,
                effect_instance: part_id,
                parameter_name: param_name.to_string(),
                default_value: *val,
            });
        }
    });
}

/// Sets default parameters for a given effect type.
pub fn set_default_effect_params(
    effect_type: EffectType,
    params: &mut std::collections::HashMap<String, f32>,
) {
    params.clear();
    match effect_type {
        EffectType::Blur => {
            params.insert("radius".to_string(), 5.0);
            params.insert("samples".to_string(), 9.0);
        }
        EffectType::Pixelate => {
            params.insert("pixel_size".to_string(), 8.0);
        }
        EffectType::FilmGrain => {
            params.insert("amount".to_string(), 0.1);
            params.insert("speed".to_string(), 1.0);
        }
        EffectType::Vignette => {
            params.insert("radius".to_string(), 0.5);
            params.insert("softness".to_string(), 0.5);
        }
        EffectType::ChromaticAberration => {
            params.insert("amount".to_string(), 0.01);
        }
        EffectType::EdgeDetect => {
            // Usually no params, or threshold?
        }
        EffectType::Brightness | EffectType::Contrast | EffectType::Saturation => {
            params.insert("brightness".to_string(), 0.0);
            params.insert("contrast".to_string(), 1.0);
            params.insert("saturation".to_string(), 1.0);
        }
        _ => {}
    }
}


/// Renders the configuration UI for a `ModulePartType::Modulizer`.
pub fn render_effect_ui(
    ui: &mut Ui,
    mod_type: &mut ModulizerType,
    part_id: ModulePartId,
    _module_id: vorce_core::module::ModuleId,
    actions: &mut Vec<crate::UIAction>,
    animator_bindings: &[vorce_core::effect_animation::EffectParameterBinding],
) {
    ui.label("Modulator:");
    match mod_type {
        ModulizerType::Effect {
            effect_type: effect,
            params,
        } => {
            // === LIVE HEADER ===
            ui.add_space(5.0);

            // 1. Big Title
            ui.vertical_centered(|ui| {
                ui.label(
                    egui::RichText::new(effect.name())
                        .size(22.0)
                        .color(crate::theme::colors::CYAN_ACCENT)
                        .strong(),
                );
            });
            ui.add_space(10.0);

            // 2. Safe Reset Button (Prominent)
            ui.vertical_centered(|ui| {
                if crate::widgets::custom::hold_to_action_button(
                    ui,
                    "\u{27F2} Safe Reset",
                    crate::theme::colors::WARN_COLOR,
                    "Safe Reset",
                ) {
                    set_default_effect_params(*effect, params);
                }
            });

            ui.add_space(10.0);
            ui.separator();

            let mut changed_type = None;

            egui::ComboBox::from_id_salt(format!("{}_effect", part_id))
                .selected_text(effect.name())
                .show_ui(ui, |ui| {
                    ui.label("--- Basic ---");
                    render_effect_choice(ui, effect, &mut changed_type, EffectType::Blur, "Blur");
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Invert,
                        "Invert",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Sharpen,
                        "Sharpen",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Threshold,
                        "Threshold",
                    );

                    ui.label("--- Color ---");
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Brightness,
                        "Brightness",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Contrast,
                        "Contrast",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Saturation,
                        "Saturation",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::HueShift,
                        "Hue Shift",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Colorize,
                        "Colorize",
                    );

                    ui.label("--- Distortion ---");
                    render_effect_choice(ui, effect, &mut changed_type, EffectType::Wave, "Wave");
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Spiral,
                        "Spiral",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Kaleidoscope,
                        "Kaleidoscope",
                    );

                    ui.label("--- Stylize ---");
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Pixelate,
                        "Pixelate",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::EdgeDetect,
                        "Edge Detect",
                    );

                    ui.label("--- Composite ---");
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::RgbSplit,
                        "RGB Split",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::ChromaticAberration,
                        "Chromatic",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::FilmGrain,
                        "Film Grain",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::Vignette,
                        "Vignette",
                    );
                    render_effect_choice(
                        ui,
                        effect,
                        &mut changed_type,
                        EffectType::LoadLUT,
                        "Load 3D LUT",
                    );
                });

            if let Some(new_type) = changed_type {
                *effect = new_type;
                set_default_effect_params(new_type, params);
            }

            ui.separator();
            let effect_supported = capabilities::is_effect_supported(effect);
            if !effect_supported {
                capabilities::render_unsupported_warning(
                    ui,
                    "This effect type has no active runtime path and is intentionally gated.",
                );
            }
            ui.add_enabled_ui(effect_supported, |ui| match effect {
                EffectType::Blur => {
                    let val = params.entry("radius".to_string()).or_insert(5.0);
                    render_param_slider(ui, effect, part_id, "radius", val, 0.0..=50.0, "Radius", actions, animator_bindings);
                    let samples = params.entry("samples".to_string()).or_insert(9.0);
                    render_param_slider(ui, effect, part_id, "samples", samples, 1.0..=20.0, "Samples", actions, animator_bindings);
                }
                EffectType::Pixelate => {
                    let val = params.entry("pixel_size".to_string()).or_insert(8.0);
                    render_param_slider(ui, effect, part_id, "pixel_size", val, 1.0..=100.0, "Pixel Size", actions, animator_bindings);
                }
                EffectType::FilmGrain => {
                    let amt = params.entry("amount".to_string()).or_insert(0.1);
                    render_param_slider(ui, effect, part_id, "amount", amt, 0.0..=1.0, "Amount", actions, animator_bindings);
                    let spd = params.entry("speed".to_string()).or_insert(1.0);
                    render_param_slider(ui, effect, part_id, "speed", spd, 0.0..=5.0, "Speed", actions, animator_bindings);
                }
                EffectType::Vignette => {
                    let rad = params.entry("radius".to_string()).or_insert(0.5);
                    render_param_slider(ui, effect, part_id, "radius", rad, 0.0..=1.0, "Radius", actions, animator_bindings);
                    let soft = params.entry("softness".to_string()).or_insert(0.5);
                    render_param_slider(ui, effect, part_id, "softness", soft, 0.0..=1.0, "Softness", actions, animator_bindings);
                }
                EffectType::ChromaticAberration => {
                    let amt = params.entry("amount".to_string()).or_insert(0.01);
                    render_param_slider(ui, effect, part_id, "amount", amt, 0.0..=0.1, "Amount", actions, animator_bindings);
                }
                EffectType::Brightness | EffectType::Contrast | EffectType::Saturation => {
                    let bri = params.entry("brightness".to_string()).or_insert(0.0);
                    render_param_slider(ui, effect, part_id, "brightness", bri, -1.0..=1.0, "Brightness", actions, animator_bindings);
                    let con = params.entry("contrast".to_string()).or_insert(1.0);
                    render_param_slider(ui, effect, part_id, "contrast", con, 0.0..=2.0, "Contrast", actions, animator_bindings);
                    let sat = params.entry("saturation".to_string()).or_insert(1.0);
                    render_param_slider(ui, effect, part_id, "saturation", sat, 0.0..=2.0, "Saturation", actions, animator_bindings);
                }
                EffectType::LoadLUT => {
                    ui.label(
                        "LUT Loading requires a .cube file (not yet implemented in properties panel).",
                    );
                }
                _ => {
                    common::render_info_label(ui, "No configurable parameters");
                }
            });
        }
        ModulizerType::BlendMode(blend) => {
            ui.label("\u{1F3A8} Blend Mode");
            egui::ComboBox::from_id_salt("blend_mode")
                .selected_text(format!("{:?}", blend))
                .show_ui(ui, |ui| {
                    if ui
                        .selectable_label(matches!(blend, BlendModeType::Normal), "Normal")
                        .clicked()
                    {
                        *blend = BlendModeType::Normal;
                    }
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Add),
                        |ui| {
                            if ui
                                .selectable_label(matches!(blend, BlendModeType::Add), "Add")
                                .clicked()
                            {
                                *blend = BlendModeType::Add;
                            }
                        },
                    );
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Multiply),
                        |ui| {
                            if ui
                                .selectable_label(
                                    matches!(blend, BlendModeType::Multiply),
                                    "Multiply",
                                )
                                .clicked()
                            {
                                *blend = BlendModeType::Multiply;
                            }
                        },
                    );
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Screen),
                        |ui| {
                            if ui
                                .selectable_label(matches!(blend, BlendModeType::Screen), "Screen")
                                .clicked()
                            {
                                *blend = BlendModeType::Screen;
                            }
                        },
                    );
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Overlay),
                        |ui| {
                            if ui
                                .selectable_label(
                                    matches!(blend, BlendModeType::Overlay),
                                    "Overlay",
                                )
                                .clicked()
                            {
                                *blend = BlendModeType::Overlay;
                            }
                        },
                    );
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Difference),
                        |ui| {
                            if ui
                                .selectable_label(
                                    matches!(blend, BlendModeType::Difference),
                                    "Difference",
                                )
                                .clicked()
                            {
                                *blend = BlendModeType::Difference;
                            }
                        },
                    );
                    ui.add_enabled_ui(
                        capabilities::is_blend_mode_supported(&BlendModeType::Exclusion),
                        |ui| {
                            if ui
                                .selectable_label(
                                    matches!(blend, BlendModeType::Exclusion),
                                    "Exclusion",
                                )
                                .clicked()
                            {
                                *blend = BlendModeType::Exclusion;
                            }
                        },
                    );
                });
            if !capabilities::is_blend_mode_supported(blend) {
                capabilities::render_unsupported_warning(
                    ui,
                    "Blend modes other than Normal are currently ignored.",
                );
            }
            ui.add(egui::Slider::new(&mut 1.0_f32, 0.0..=1.0).text("Opacity"));
        }
        ModulizerType::AudioReactive { source } => {
            ui.label("\u{1F50A} Audio Reactive");
            ui.horizontal(|ui| {
                ui.label("Source:");
                egui::ComboBox::from_id_salt("audio_source")
                    .selected_text(source.as_str())
                    .show_ui(ui, |ui| {
                        if ui
                            .selectable_label(source == "SubBass", "SubBass")
                            .clicked()
                        {
                            *source = "SubBass".to_string();
                        }
                        if ui.selectable_label(source == "Bass", "Bass").clicked() {
                            *source = "Bass".to_string();
                        }
                        if ui.selectable_label(source == "LowMid", "LowMid").clicked() {
                            *source = "LowMid".to_string();
                        }
                        if ui.selectable_label(source == "Mid", "Mid").clicked() {
                            *source = "Mid".to_string();
                        }
                        if ui
                            .selectable_label(source == "HighMid", "HighMid")
                            .clicked()
                        {
                            *source = "HighMid".to_string();
                        }
                        if ui
                            .selectable_label(source == "Presence", "Presence")
                            .clicked()
                        {
                            *source = "Presence".to_string();
                        }
                        if ui
                            .selectable_label(source == "Brilliance", "Brilliance")
                            .clicked()
                        {
                            *source = "Brilliance".to_string();
                        }
                        if ui.selectable_label(source == "RMS", "RMS Volume").clicked() {
                            *source = "RMS".to_string();
                        }
                        if ui.selectable_label(source == "Peak", "Peak").clicked() {
                            *source = "Peak".to_string();
                        }
                        if ui.selectable_label(source == "BPM", "BPM").clicked() {
                            *source = "BPM".to_string();
                        }
                    });
            });
            ui.add(egui::Slider::new(&mut 0.1_f32, 0.0..=1.0).text("Smoothing"));
        }
    }
}
