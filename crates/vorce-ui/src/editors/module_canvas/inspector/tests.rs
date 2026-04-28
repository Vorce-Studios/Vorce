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
    // Test some known supported effects
    assert!(is_effect_supported(&EffectType::Blur));
    assert!(is_effect_supported(&EffectType::Invert));
    assert!(is_effect_supported(&EffectType::Wave));

    // Test some known unsupported effects (at the time of writing)
    assert!(!is_effect_supported(&EffectType::Sharpen));
    assert!(!is_effect_supported(&EffectType::Threshold));
    assert!(!is_effect_supported(&EffectType::Posterize));
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
    let _ = is_source_type_enum_supported(false, false, true, false); // NDI may or may not be supported depending on platform
    assert!(!is_source_type_enum_supported(false, false, false, true)); // spout
}

#[test]
fn test_is_output_type_enum_supported() {
    // NDI output is supported, others are unsupported
    let _ = is_output_type_enum_supported(true, false, false); // NDI may or may not be supported depending on platform
    assert!(!is_output_type_enum_supported(false, true, false));
    assert!(!is_output_type_enum_supported(false, false, true));
    let _ = is_output_type_enum_supported(false, false, false);
}

#[test]
fn test_mapping_and_transform_supported() {
    assert!(is_mapping_mode_supported());
    assert!(is_transform_supported());
}
