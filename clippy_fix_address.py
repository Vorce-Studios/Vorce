import re

with open("crates/vorce-control/src/osc/address.rs", "r") as f:
    content = f.read()

# Replace test functions signatures
content = content.replace("fn test_parse_osc_address_layer() {", "fn test_parse_osc_address_layer() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_osc_address_effect() {", "fn test_parse_osc_address_effect() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_osc_address_playback() {", "fn test_parse_osc_address_playback() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_osc_address_invalid() {", "fn test_parse_osc_address_invalid() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_control_target_to_osc_address() {", "fn test_control_target_to_osc_address() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_legacy_namespaces() {", "fn test_legacy_namespaces() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_layer_opacity() {", "fn test_parse_layer_opacity() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_layer_position() {", "fn test_parse_layer_position() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_paint_parameter() {", "fn test_parse_paint_parameter() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_effect_parameter() {", "fn test_parse_effect_parameter() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_playback_speed() {", "fn test_parse_playback_speed() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_layer_rotation() {", "fn test_parse_layer_rotation() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_layer_scale() {", "fn test_parse_layer_scale() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_layer_visibility() {", "fn test_parse_layer_visibility() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_playback_position() {", "fn test_parse_playback_position() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_output_brightness() {", "fn test_parse_output_brightness() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_master_opacity() {", "fn test_parse_master_opacity() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_parse_master_blackout() {", "fn test_parse_master_blackout() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_round_trip_layer_targets() {", "fn test_round_trip_layer_targets() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_round_trip_master_targets() {", "fn test_round_trip_master_targets() -> Result<(), Box<dyn std::error::Error>> {")
content = content.replace("fn test_round_trip_playback_targets() {", "fn test_round_trip_playback_targets() -> Result<(), Box<dyn std::error::Error>> {")

content = content.replace('        assert_eq!(target2, ControlTarget::LayerPosition(5));\n    }', '        assert_eq!(target2, ControlTarget::LayerPosition(5));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::LayerOpacity(0));\n    }', '        assert_eq!(target, ControlTarget::LayerOpacity(0));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::LayerPosition(5));\n    }', '        assert_eq!(target, ControlTarget::LayerPosition(5));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(\n            target,\n            ControlTarget::PaintParameter(3, "speed".to_string())\n        );\n    }', '        assert_eq!(\n            target,\n            ControlTarget::PaintParameter(3, "speed".to_string())\n        );\n        Ok(())\n    }')
content = content.replace('        assert_eq!(\n            target,\n            ControlTarget::EffectParameter(1, "intensity".to_string())\n        );\n    }', '        assert_eq!(\n            target,\n            ControlTarget::EffectParameter(1, "intensity".to_string())\n        );\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::PlaybackSpeed(None));\n    }', '        assert_eq!(target, ControlTarget::PlaybackSpeed(None));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::LayerRotation(2));\n    }', '        assert_eq!(target, ControlTarget::LayerRotation(2));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::LayerScale(7));\n    }', '        assert_eq!(target, ControlTarget::LayerScale(7));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::LayerVisibility(10));\n    }', '        assert_eq!(target, ControlTarget::LayerVisibility(10));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::PlaybackPosition);\n    }', '        assert_eq!(target, ControlTarget::PlaybackPosition);\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::OutputBrightness(0));\n    }', '        assert_eq!(target, ControlTarget::OutputBrightness(0));\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::MasterOpacity);\n    }', '        assert_eq!(target, ControlTarget::MasterOpacity);\n        Ok(())\n    }')
content = content.replace('        assert_eq!(target, ControlTarget::MasterBlackout);\n    }', '        assert_eq!(target, ControlTarget::MasterBlackout);\n        Ok(())\n    }')

content = content.replace('        }\n    }', '        }\n        Ok(())\n    }')


with open("crates/vorce-control/src/osc/address.rs", "w") as f:
    f.write(content)
