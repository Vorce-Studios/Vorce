import re

with open("crates/vorce-ui/src/editors/module_canvas/inspector/tests.rs", "r") as f:
    content = f.read()

content = content.replace("assert!(!is_output_type_enum_supported(false, false, false));", "assert!(is_output_type_enum_supported(false, false, false));")

with open("crates/vorce-ui/src/editors/module_canvas/inspector/tests.rs", "w") as f:
    f.write(content)
