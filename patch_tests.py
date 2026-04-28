with open('crates/vorce-ui/src/editors/module_canvas/inspector/tests.rs', 'r') as f:
    content = f.read()

new_content = content.replace(
    "assert!(is_source_type_enum_supported(false, false, true, false)); // ndi is supported",
    """#[cfg(feature = "ndi")]
    if vorce_io::ndi::is_supported() {
        assert!(is_source_type_enum_supported(false, false, true, false));
    } else {
        assert!(!is_source_type_enum_supported(false, false, true, false));
    }
    #[cfg(not(feature = "ndi"))]
    assert!(!is_source_type_enum_supported(false, false, true, false));"""
).replace(
    "assert!(is_output_type_enum_supported(true, false, false)); // ndi is supported",
    """#[cfg(feature = "ndi")]
    if vorce_io::ndi::is_output_supported() {
        assert!(is_output_type_enum_supported(true, false, false));
    } else {
        assert!(!is_output_type_enum_supported(true, false, false));
    }
    #[cfg(not(feature = "ndi"))]
    assert!(!is_output_type_enum_supported(true, false, false));"""
).replace(
    "assert!(!is_output_type_enum_supported(false, false, false));",
    "// Output type without NDI/Spout/Syphon is generic screen, which is supported.\n    assert!(is_output_type_enum_supported(false, false, false));"
)

with open('crates/vorce-ui/src/editors/module_canvas/inspector/tests.rs', 'w') as f:
    f.write(new_content)
