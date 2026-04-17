import re

with open("crates/vorce-control/src/osc/mapping.rs", "r") as f:
    content = f.read()

content = content.replace("fn test_serialization() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_serialization() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

with open("crates/vorce-control/src/osc/mapping.rs", "w") as f:
    f.write(content)

with open("crates/vorce-control/src/osc/server.rs", "r") as f:
    content = f.read()

content = content.replace("fn test_osc_server_client_communication() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_server_client_communication() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_osc_backpressure() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_backpressure() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

with open("crates/vorce-control/src/osc/server.rs", "w") as f:
    f.write(content)

with open("crates/vorce-control/src/osc/types.rs", "r") as f:
    content = f.read()

content = content.replace("fn test_osc_to_control_value() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_to_control_value() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_osc_to_vec2() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_to_vec2() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

with open("crates/vorce-control/src/osc/types.rs", "w") as f:
    f.write(content)
