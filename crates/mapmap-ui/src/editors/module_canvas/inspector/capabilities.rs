use mapmap_core::module::{BlendModeType, EffectType};

/// Determines if a given BlendMode is currently supported by the render pipeline.
pub fn is_blend_mode_supported(blend_mode: &BlendModeType) -> bool {
    // Currently ignored in the final render according to DOC-C10.
    // However, if we need to keep some active for testing or future-proofing, we can list them.
    // For now, let's just say only Normal is truly supported since others are ignored.
    matches!(blend_mode, BlendModeType::Normal)
}

/// Determines if a given EffectType is currently supported by the render pipeline.
pub fn is_effect_supported(effect_type: &EffectType) -> bool {
    matches!(
        effect_type,
        EffectType::ShaderGraph(_)
            | EffectType::Blur
            | EffectType::Invert
            | EffectType::HueShift
            | EffectType::Wave
            | EffectType::Mirror
            | EffectType::Kaleidoscope
            | EffectType::Pixelate
            | EffectType::EdgeDetect
            | EffectType::Glitch
            | EffectType::RgbSplit
            | EffectType::ChromaticAberration
            | EffectType::FilmGrain
            | EffectType::Vignette
    )
}

/// Determines if a layer's mapping mode (grid) is fully supported.
pub fn is_mapping_mode_supported() -> bool {
    false // Mapping mode grid is currently not end-to-end supported
}

/// Determines if source properties scale/rotation/offset are fully supported.
pub fn is_transform_supported() -> bool {
    false // scale, rotation, offset currently ignored in final render according to DOC-C10
}

/// Determines if a mask is fully supported.
pub fn is_mask_supported() -> bool {
    false // masks currently ignored in final render according to DOC-C10
}

/// Renders a standardized unsupported warning label for UI gating.
pub fn render_unsupported_warning(ui: &mut egui::Ui, text: &str) {
    ui.label(
        egui::RichText::new(format!("⚠ {}", text))
            .color(crate::theme::colors::WARN_COLOR)
            .small(),
    );
}

/// Helper that checks by variant enum without needing the data
pub fn is_source_type_enum_supported(
    is_shader: bool,
    is_live_input: bool,
    is_ndi: bool,
    #[allow(unused_variables)] is_spout: bool,
) -> bool {
    #[cfg(target_os = "windows")]
    if is_spout {
        return false;
    }

    #[cfg(not(target_os = "windows"))]
    if is_spout {
        return false;
    }

    !(is_shader || is_live_input || is_ndi || is_spout)
}

/// Helper that checks if an output type is fully supported
pub fn is_output_type_enum_supported(is_ndi: bool, is_spout: bool) -> bool {
    !(is_ndi || is_spout)
}
