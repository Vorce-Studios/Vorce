import re

with open("crates/vorce-control/src/osc/server.rs", "r") as f:
    content = f.read()

content = content.replace('        } else {\n            panic!("Expected OscPacket::Message");\n        }\n        Ok(())', '        } else {\n            panic!("Expected OscPacket::Message");\n        }\n        Ok(())')
content = content.replace('        } else {\n            panic!("Expected OscPacket::Message");\n        }', '        } else {\n            panic!("Expected OscPacket::Message");\n        }\n        Ok(())')


with open("crates/vorce-control/src/osc/server.rs", "w") as f:
    f.write(content)

with open("crates/vorce-control/src/osc/types.rs", "r") as f:
    content = f.read()

content = content.replace('        assert_eq!(value, ControlValue::Bool(true));\n    }', '        assert_eq!(value, ControlValue::Bool(true));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(value, ControlValue::Vec2(1.0, 2.0));\n    }', '        assert_eq!(value, ControlValue::Vec2(1.0, 2.0));\n        Ok(())\n    }')

with open("crates/vorce-control/src/osc/types.rs", "w") as f:
    f.write(content)
