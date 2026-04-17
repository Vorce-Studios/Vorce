import re
import glob

def fix_control(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    content = content.replace("fn test_parse_osc_address_layer() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_layer() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_osc_address_effect() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_effect() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_osc_address_playback() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_playback() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_osc_address_invalid() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_invalid() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_control_target_to_osc_address() -> Result<(), Box<dyn std::error::Error>> {", "fn test_control_target_to_osc_address() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_legacy_namespaces() -> Result<(), Box<dyn std::error::Error>> {", "fn test_legacy_namespaces() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_layer_opacity() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_layer_position() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_position() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_paint_parameter() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_paint_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_effect_parameter() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_effect_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_playback_speed() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_playback_speed() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_layer_rotation() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_rotation() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_layer_scale() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_scale() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_layer_visibility() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_visibility() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_playback_position() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_playback_position() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_output_brightness() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_output_brightness() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_master_opacity() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_master_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_parse_master_blackout() -> Result<(), Box<dyn std::error::Error>> {", "fn test_parse_master_blackout() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_round_trip_layer_targets() -> Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_layer_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_round_trip_master_targets() -> Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_master_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_round_trip_playback_targets() -> Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_playback_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {")

    content = content.replace("fn test_serialization() -> Result<(), Box<dyn std::error::Error>> {", "fn test_serialization() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_osc_server_client_communication() -> Result<(), Box<dyn std::error::Error>> {", "fn test_osc_server_client_communication() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_osc_backpressure() -> Result<(), Box<dyn std::error::Error>> {", "fn test_osc_backpressure() -> std::result::Result<(), Box<dyn std::error::Error>> {")

    content = content.replace("fn test_osc_to_control_value() {", "fn test_osc_to_control_value() -> std::result::Result<(), Box<dyn std::error::Error>> {")
    content = content.replace("fn test_osc_to_vec2() {", "fn test_osc_to_vec2() -> std::result::Result<(), Box<dyn std::error::Error>> {")

    content = content.replace('        } else {\n            panic!("Expected OscPacket::Message");\n        }', '        } else {\n            panic!("Expected OscPacket::Message");\n        }\n        Ok(())')

    with open(filepath, "w") as f:
        f.write(content)

for filepath in glob.glob("crates/vorce-control/src/**/*.rs", recursive=True):
    fix_control(filepath)
