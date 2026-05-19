use super::error::{CodegenError, Result};
use super::generator::WGSLCodegen;
use crate::shader_graph::{DataType, InputSocket, NodeType, ParameterValue, ShaderNode};
use std::fmt::Write;

pub(crate) fn generate_fragment_shader(codegen: &WGSLCodegen, code: &mut String) -> Result<()> {
    writeln!(code, "// Fragment Shader")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "@fragment").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "fn fs_main(").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    @location(0) uv: vec2<f32>,")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, ") -> @location(0) vec4<f32> {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    // Generate variable declarations and computations
    for node_id in &codegen.node_execution_order {
        if let Some(node) = codegen.graph.nodes.get(node_id) {
            generate_node_code(codegen, code, node)?;
        }
    }

    // Return output
    let output_node = codegen.graph.output_node().ok_or(CodegenError::NoOutputNode)?;
    let output_input = &output_node.inputs[0];

    if let Some((source_node, output_name)) = &output_input.connected_output {
        writeln!(code, "    return node_{}_{};", source_node, output_name.as_str().to_lowercase())
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    } else if let Some(default) = &output_input.default_value {
        writeln!(
            code,
            "    return vec4<f32>({}, {}, {}, {});",
            default.x, default.y, default.z, default.w
        )
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    }

    writeln!(code, "}}").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate code for a specific node
pub(crate) fn generate_node_code(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    match node.node_type {
        NodeType::UVInput => {
            writeln!(code, "    let node_{}_uv = uv;", node.id)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::TimeInput => {
            writeln!(code, "    let node_{}_time = uniforms.time;", node.id)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::ParameterInput => {
            let param_name = node
                .parameters
                .get("name")
                .and_then(|v| if let ParameterValue::String(s) = v { Some(s) } else { None })
                .map(|s: &String| s.as_str())
                .unwrap_or("param");
            writeln!(code, "    let node_{}_value = uniforms.{};", node.id, param_name)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::AudioInput => {
            writeln!(code, "    let node_{}_value = uniforms.audio_value;", node.id)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::TextureInput => {
            // Handled in bindings
        }

        NodeType::TextureSample => {
            let tex_input = &node.inputs[0];
            let uv_input = &node.inputs[1];

            let tex_var = get_input_variable(codegen, tex_input)?;
            let uv_var = get_input_variable(codegen, uv_input)?;

            writeln!(
                code,
                "    let node_{}_color = textureSample({}, {}, {});",
                node.id,
                tex_var,
                tex_var.replace("texture", "sampler"),
                uv_var
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
            writeln!(code, "    let node_{}_alpha = node_{}_color.a;", node.id, node.id)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::TextureSampleLod => {
            let tex_input = &node.inputs[0];
            let uv_input = &node.inputs[1];
            let lod_input = &node.inputs[2];

            let tex_var = get_input_variable(codegen, tex_input)?;
            let uv_var = get_input_variable(codegen, uv_input)?;
            let lod_var = get_input_variable(codegen, lod_input)?;

            writeln!(
                code,
                "    let node_{}_color = textureSampleLevel({}, {}, {}, {});",
                node.id,
                tex_var,
                tex_var.replace("texture", "sampler"),
                uv_var,
                lod_var
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::TextureCombine => {
            let tex_a = get_input_variable(codegen, &node.inputs[0])?;
            let tex_b = get_input_variable(codegen, &node.inputs[1])?;
            let mix_factor = get_input_variable(codegen, &node.inputs[2])?;

            writeln!(
                    code,
                    "    let node_{}_color = mix(textureSample({}, {}, uv), textureSample({}, {}, uv), {});",
                    node.id,
                    tex_a,
                    tex_a.replace("texture", "sampler"),
                    tex_b,
                    tex_b.replace("texture", "sampler"),
                    mix_factor
                )
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Add | NodeType::Subtract | NodeType::Multiply | NodeType::Divide => {
            generate_math_op(codegen, code, node)?;
        }

        NodeType::Power => {
            generate_power_op(codegen, code, node)?;
        }

        NodeType::Clamp => {
            generate_clamp_op(codegen, code, node)?;
        }

        NodeType::Smoothstep => {
            generate_smoothstep_op(codegen, code, node)?;
        }

        NodeType::Combine => {
            generate_combine_op(codegen, code, node)?;
        }

        NodeType::Split => {
            generate_split_op(codegen, code, node)?;
        }

        NodeType::Sin | NodeType::Cos => {
            generate_trig_op(codegen, code, node)?;
        }

        NodeType::Mix => {
            generate_mix_op(codegen, code, node)?;
        }

        NodeType::Remap => {
            let val = get_input_variable(codegen, &node.inputs[0])?;
            let in_min = get_input_variable(codegen, &node.inputs[1])?;
            let in_max = get_input_variable(codegen, &node.inputs[2])?;
            let out_min = get_input_variable(codegen, &node.inputs[3])?;
            let out_max = get_input_variable(codegen, &node.inputs[4])?;

            writeln!(
                code,
                "    let node_{}_result = {} + ({} - {}) * ({} - {}) / ({} - {});",
                node.id, out_min, val, in_min, out_max, out_min, in_max, in_min
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Brightness => {
            generate_brightness_op(codegen, code, node)?;
        }

        NodeType::Contrast => {
            generate_contrast_op(codegen, code, node)?;
        }

        NodeType::Desaturate => {
            generate_desaturate_op(codegen, code, node)?;
        }

        NodeType::ColorRamp => {
            let input = get_input_variable(codegen, &node.inputs[0])?;
            writeln!(
                code,
                "    let node_{}_color = vec4<f32>(vec3<f32>({}), 1.0);",
                node.id, input
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::HSVToRGB => {
            let input = get_input_variable(codegen, &node.inputs[0])?;
            writeln!(code, "    let node_{}_output = hsv_to_rgb({});", node.id, input)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::RGBToHSV => {
            let input = get_input_variable(codegen, &node.inputs[0])?;
            writeln!(code, "    let node_{}_output = rgb_to_hsv({});", node.id, input)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::UVTransform => {
            generate_uv_transform(codegen, code, node)?;
        }

        NodeType::UVDistort => {
            let uv = get_input_variable(codegen, &node.inputs[0])?;
            let distortion = get_input_variable(codegen, &node.inputs[1])?;
            let amount = get_input_variable(codegen, &node.inputs[2])?;
            writeln!(code, "    let node_{}_uv = {} + {} * {};", node.id, uv, distortion, amount)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Blur => {
            let tex = get_input_variable(codegen, &node.inputs[0])?;
            let uv = get_input_variable(codegen, &node.inputs[1])?;
            let radius = node
                .parameters
                .get("radius")
                .map(|v| format!("{}", v))
                .unwrap_or_else(|| "1.0".to_string());
            writeln!(
                code,
                "    let node_{}_color = blur_sample({}, {}, {}, {});",
                node.id,
                tex,
                tex.replace("texture", "sampler"),
                uv,
                radius
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Glow => {
            let color = get_input_variable(codegen, &node.inputs[0])?;
            let amount = get_input_variable(codegen, &node.inputs[1])?;
            writeln!(code, "    let node_{}_color = {} * (1.0 + {});", node.id, color, amount)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::ChromaticAberration => {
            let color = get_input_variable(codegen, &node.inputs[0])?;
            let amount = get_input_variable(codegen, &node.inputs[1])?;
            writeln!(
                code,
                "    let node_{}_color = {} + vec4<f32>({}, 0.0, -{}, 0.0);",
                node.id, color, amount, amount
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Kaleidoscope => {
            let uv = get_input_variable(codegen, &node.inputs[0])?;
            let segments = get_input_variable(codegen, &node.inputs[1])?;
            writeln!(code, "    let node_{}_uv = kaleidoscope({}, {});", node.id, uv, segments)
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::PixelSort | NodeType::Displacement => {
            let color = get_input_variable(codegen, &node.inputs[0])?;
            let map = get_input_variable(codegen, &node.inputs[1])?;
            writeln!(
                code,
                "    let node_{}_color = mix({}, {}, 0.5); // Placeholder",
                node.id, color, map
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::EdgeDetect => {
            let tex = get_input_variable(codegen, &node.inputs[0])?;
            let uv = get_input_variable(codegen, &node.inputs[1])?;
            writeln!(
                code,
                "    let node_{}_color = edge_detect({}, {}, {});",
                node.id,
                tex,
                tex.replace("texture", "sampler"),
                uv
            )
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        }

        NodeType::Output => {
            // Output node doesn't generate code, just connects
        }
    }

    Ok(())
}

/// Generate power operation code
pub(crate) fn generate_power_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let a = get_input_variable(codegen, &node.inputs[0])?;
    let b = get_input_variable(codegen, &node.inputs[1])?;

    writeln!(code, "    let node_{}_result = pow({}, {});", node.id, a, b)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate clamp operation code
pub(crate) fn generate_clamp_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let val = get_input_variable(codegen, &node.inputs[0])?;
    let min = get_input_variable(codegen, &node.inputs[1])?;
    let max = get_input_variable(codegen, &node.inputs[2])?;

    writeln!(code, "    let node_{}_result = clamp({}, {}, {});", node.id, val, min, max)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate smoothstep operation code
pub(crate) fn generate_smoothstep_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let edge0 = get_input_variable(codegen, &node.inputs[0])?;
    let edge1 = get_input_variable(codegen, &node.inputs[1])?;
    let x = get_input_variable(codegen, &node.inputs[2])?;

    writeln!(code, "    let node_{}_result = smoothstep({}, {}, {});", node.id, edge0, edge1, x)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate combine operation code
pub(crate) fn generate_combine_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let r = get_input_variable(codegen, &node.inputs[0])?;
    let g = get_input_variable(codegen, &node.inputs[1])?;
    let b = get_input_variable(codegen, &node.inputs[2])?;
    let a = get_input_variable(codegen, &node.inputs[3])?;

    writeln!(code, "    let node_{}_color = vec4<f32>({}, {}, {}, {});", node.id, r, g, b, a)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate split operation code
pub(crate) fn generate_split_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let color = get_input_variable(codegen, &node.inputs[0])?;

    writeln!(code, "    let node_{}_r = {}.r;", node.id, color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_g = {}.g;", node.id, color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_b = {}.b;", node.id, color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_a = {}.a;", node.id, color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate math operation code
pub(crate) fn generate_math_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let a = get_input_variable(codegen, &node.inputs[0])?;
    let b = get_input_variable(codegen, &node.inputs[1])?;

    let op = match node.node_type {
        NodeType::Add => "+",
        NodeType::Subtract => "-",
        NodeType::Multiply => "*",
        NodeType::Divide => "/",
        _ => return Err(CodegenError::GenerationError("Invalid math op".to_string())),
    };

    writeln!(code, "    let node_{}_result = {} {} {};", node.id, a, op, b)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate trigonometric operation code
pub(crate) fn generate_trig_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let input = get_input_variable(codegen, &node.inputs[0])?;

    let func = match node.node_type {
        NodeType::Sin => "sin",
        NodeType::Cos => "cos",
        _ => return Err(CodegenError::GenerationError("Invalid trig op".to_string())),
    };

    writeln!(code, "    let node_{}_result = {}({});", node.id, func, input)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate mix operation code
pub(crate) fn generate_mix_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let a = get_input_variable(codegen, &node.inputs[0])?;
    let b = get_input_variable(codegen, &node.inputs[1])?;
    let t = get_input_variable(codegen, &node.inputs[2])?;

    writeln!(code, "    let node_{}_result = mix({}, {}, {});", node.id, a, b, t)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate brightness operation code
pub(crate) fn generate_brightness_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let color = get_input_variable(codegen, &node.inputs[0])?;
    let amount = node
        .parameters
        .get("amount")
        .map(|v| format!("{}", v))
        .unwrap_or_else(|| "0.0".to_string());

    writeln!(
        code,
        "    let node_{}_result = {} + vec4<f32>({}, {}, {}, 0.0);",
        node.id, color, amount, amount, amount
    )
    .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate contrast operation code
pub(crate) fn generate_contrast_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let color = get_input_variable(codegen, &node.inputs[0])?;
    let amount = node
        .parameters
        .get("amount")
        .map(|v| format!("{}", v))
        .unwrap_or_else(|| "1.0".to_string());

    writeln!(code, "    let node_{}_result = ({} - 0.5) * {} + 0.5;", node.id, color, amount)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate desaturate operation code
pub(crate) fn generate_desaturate_op(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let color = get_input_variable(codegen, &node.inputs[0])?;

    writeln!(code, "    let gray = dot({}.rgb, vec3<f32>(0.299, 0.587, 0.114));", color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_result = vec4<f32>(vec3<f32>(gray), {}.a);", node.id, color)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Generate UV transform code
pub(crate) fn generate_uv_transform(
    codegen: &WGSLCodegen,
    code: &mut String,
    node: &ShaderNode,
) -> Result<()> {
    let uv = get_input_variable(codegen, &node.inputs[0])?;

    let scale_val = node.parameters.get("scale").unwrap_or(&ParameterValue::Vec2([1.0, 1.0]));
    let rotation_val = node.parameters.get("rotation").unwrap_or(&ParameterValue::Float(0.0));
    let translation_val =
        node.parameters.get("translation").unwrap_or(&ParameterValue::Vec2([0.0, 0.0]));

    writeln!(code, "    // UV Transform")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    var node_{}_uv_temp = {} - vec2<f32>(0.5, 0.5);", node.id, uv)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_scale = {};", node.id, scale_val)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_rot = {};", node.id, rotation_val)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_trans = {};", node.id, translation_val)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    writeln!(code, "    let node_{}_cos_r = cos(node_{}_rot);", node.id, node.id)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let node_{}_sin_r = sin(node_{}_rot);", node.id, node.id)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    writeln!(code, "    let node_{}_rot_uv = vec2<f32>(", node.id)
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(
        code,
        "        node_{}_uv_temp.x * node_{}_cos_r - node_{}_uv_temp.y * node_{}_sin_r,",
        node.id, node.id, node.id, node.id
    )
    .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(
        code,
        "        node_{}_uv_temp.x * node_{}_sin_r + node_{}_uv_temp.y * node_{}_cos_r",
        node.id, node.id, node.id, node.id
    )
    .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    );").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    writeln!(code, "    let node_{}_uv = (node_{}_rot_uv / node_{}_scale) + vec2<f32>(0.5, 0.5) + node_{}_trans;", node.id, node.id, node.id, node.id).map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

/// Get the variable name for an input socket
pub(crate) fn get_input_variable(_codegen: &WGSLCodegen, input: &InputSocket) -> Result<String> {
    if let Some((source_node, output_name)) = &input.connected_output {
        Ok(format!("node_{}_{}", source_node, output_name.as_str().to_lowercase()))
    } else if let Some(default) = &input.default_value {
        match input.data_type {
            DataType::Float => Ok(format!("{}", default.x)),
            DataType::Vec2 => Ok(format!("vec2<f32>({}, {})", default.x, default.y)),
            DataType::Vec3 => Ok(format!("vec3<f32>({}, {}, {})", default.x, default.y, default.z)),
            DataType::Vec4 | DataType::Color => {
                Ok(format!("vec4<f32>({}, {}, {}, {})", default.x, default.y, default.z, default.w))
            }
            _ => Err(CodegenError::GenerationError(
                "Cannot generate default for texture/sampler".to_string(),
            )),
        }
    } else {
        Err(CodegenError::GenerationError(format!(
            "Input '{}' has no connection or default",
            input.name
        )))
    }
}

// Helper function generators

impl std::fmt::Display for ParameterValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ParameterValue::Float(v) => write!(f, "{}", v),
            ParameterValue::Vec2(v) => write!(f, "vec2<f32>({}, {})", v[0], v[1]),
            ParameterValue::Vec3(v) => write!(f, "vec3<f32>({}, {}, {})", v[0], v[1], v[2]),
            ParameterValue::Vec4(v) => {
                write!(f, "vec4<f32>({}, {}, {}, {})", v[0], v[1], v[2], v[3])
            }
            ParameterValue::Color(c) => {
                write!(f, "vec4<f32>({}, {}, {}, {})", c[0], c[1], c[2], c[3])
            }
            ParameterValue::String(_) => write!(f, "0.0"), // Strings not supported in WGSL
        }
    }
}
