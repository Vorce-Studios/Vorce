import re

with open("crates/vorce-control/src/osc/address.rs", "r") as f:
    content = f.read()

content = content.replace("fn test_parse_osc_address_layer() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_layer() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_osc_address_effect() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_effect() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_osc_address_playback() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_playback() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_osc_address_invalid() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_osc_address_invalid() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_control_target_to_osc_address() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_control_target_to_osc_address() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_legacy_namespaces() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_legacy_namespaces() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_layer_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_layer_position() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_position() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_paint_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_paint_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_effect_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_effect_parameter() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_playback_speed() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_playback_speed() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_layer_rotation() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_rotation() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_layer_scale() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_scale() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_layer_visibility() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_layer_visibility() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_playback_position() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_playback_position() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_output_brightness() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_output_brightness() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_master_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_master_opacity() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_parse_master_blackout() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_parse_master_blackout() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_round_trip_layer_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_layer_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_round_trip_master_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_master_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_round_trip_playback_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_round_trip_playback_targets() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

content = content.replace("fn test_serialization() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_serialization() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

content = content.replace("fn test_osc_server_client_communication() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_server_client_communication() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_osc_backpressure() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_backpressure() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")

content = content.replace("fn test_osc_to_control_value() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_to_control_value() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")
content = content.replace("fn test_osc_to_vec2() -> std::result::Result<(), Box<dyn std::error::Error>> {", "fn test_osc_to_vec2() -> std::result::Result<(), Box<dyn std::error::Error>> {\n    #[allow(unreachable_code)]\n")


with open("crates/vorce-control/src/osc/address.rs", "w") as f:
    f.write(content)
