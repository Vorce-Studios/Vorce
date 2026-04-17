import re

with open("crates/vorce-control/src/osc/mapping.rs", "r") as f:
    content = f.read()

# Replace test functions signatures
content = content.replace("fn test_serialization() {", "fn test_serialization() -> Result<(), Box<dyn std::error::Error>> {")

content = content.replace('        assert_eq!(mapping, loaded);\n    }', '        assert_eq!(mapping, loaded);\n        Ok(())\n    }')

with open("crates/vorce-control/src/osc/mapping.rs", "w") as f:
    f.write(content)
