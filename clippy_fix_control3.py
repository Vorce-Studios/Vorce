import re

with open("crates/vorce-control/src/osc/server.rs", "r") as f:
    content = f.read()

content = content.replace('        } else {\n            panic!("Expected OSC packet");\n        }\n    }', '        } else {\n            panic!("Expected OSC packet");\n        }\n        Ok(())\n    }')

with open("crates/vorce-control/src/osc/server.rs", "w") as f:
    f.write(content)
