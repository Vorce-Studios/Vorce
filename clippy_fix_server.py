import re

with open("crates/vorce-control/src/osc/server.rs", "r") as f:
    content = f.read()

# Replace test functions signatures
content = content.replace("fn test_osc_server_client_communication() {", "fn test_osc_server_client_communication() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_osc_backpressure() {", "fn test_osc_backpressure() -> Result<(), Box<dyn std::error::Error>> {")

content = content.replace('        assert!(count > 0, "Should have received messages");\n    }', '        assert!(count > 0, "Should have received messages");\n        Ok(())\n    }')

content = content.replace('        assert!(found_alive, "Server should be responsive after flood");\n    }', '        assert!(found_alive, "Server should be responsive after flood");\n        Ok(())\n    }')

with open("crates/vorce-control/src/osc/server.rs", "w") as f:
    f.write(content)
