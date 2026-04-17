use super::capabilities::*;
use vorce_core::module::{BlendModeType, EffectType};

#[test]
fn test_is_blend_mode_supported() {
    for mode in BlendModeType::all() {
        if matches!(mode, BlendModeType::Normal) {
            assert!(is_blend_mode_supported(mode), "Normal blend mode should be supported");
        } else {
            assert!(
                !is_blend_mode_supported(mode),
                "{:?} blend mode should NOT be supported yet",
                mode
            );
        }
    }
}

#[test]
fn test_is_effect_supported() {
    for effect in EffectType::all() {
        let expected = matches!(
            effect,
            EffectType::Blur
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
        );
        assert_eq!(is_effect_supported(effect), expected, "Mismatch for effect {:?}", effect);
    }
    assert!(is_effect_supported(&EffectType::ShaderGraph(0)));
}

#[test]
fn test_is_mask_supported() {
    assert!(!is_mask_supported(), "Masks should currently be unsupported per DOC-C10");
}

#[test]
fn test_has_advanced_blend_mode_support() {
    // Since only Normal is supported, advanced support should be false
    assert!(!has_advanced_blend_mode_support());
}

#[test]
fn test_is_source_type_enum_supported() {
    // Fully supported: standard (none of the special flags)
    assert!(is_source_type_enum_supported(false, false, false, false));

    // Unsupported ones
    assert!(!is_source_type_enum_supported(true, false, false, false)); // shader
    assert!(!is_source_type_enum_supported(false, true, false, false)); // live input
    assert!(!is_source_type_enum_supported(false, false, true, false)); // ndi
    assert!(!is_source_type_enum_supported(false, false, false, true)); // spout
}

#[test]
fn test_is_output_type_enum_supported() {
    // Currently all special output types are unsupported in this helper
    assert!(!is_output_type_enum_supported(true, false, false));
    assert!(!is_output_type_enum_supported(false, true, false));
    assert!(!is_output_type_enum_supported(false, false, true));
    assert!(!is_output_type_enum_supported(false, false, false));
}

#[test]
fn test_mapping_and_transform_supported() {
    assert!(is_mapping_mode_supported());
    assert!(is_transform_supported());
}
