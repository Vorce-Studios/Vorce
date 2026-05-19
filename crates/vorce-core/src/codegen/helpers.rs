use super::error::{CodegenError, Result};
use super::generator::WGSLCodegen;
use crate::shader_graph::NodeType;
use std::collections::HashSet;
use std::fmt::Write;

pub(crate) fn generate_helper_functions(
    codegen: &mut WGSLCodegen,
    code: &mut String,
) -> Result<()> {
    writeln!(code, "// Helper Functions\n")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    // Generate functions for complex node types
    // Optimization: Iterate directly over node_execution_order without cloning.
    // We pass &mut generated_functions to helper methods to avoid full codegen: &mut WGSLCodegen borrow conflicts.
    for node_id in &codegen.node_execution_order {
        if let Some(node) = codegen.graph.nodes.get(node_id) {
            match node.node_type {
                NodeType::Blur => generate_blur_function(&mut codegen.generated_functions, code)?,
                NodeType::ChromaticAberration => {
                    generate_chromatic_aberration_function(&mut codegen.generated_functions, code)?
                }
                NodeType::EdgeDetect => {
                    generate_edge_detect_function(&mut codegen.generated_functions, code)?
                }
                NodeType::Kaleidoscope => {
                    generate_kaleidoscope_function(&mut codegen.generated_functions, code)?
                }
                NodeType::HSVToRGB => {
                    generate_hsv_to_rgb_function(&mut codegen.generated_functions, code)?
                }
                NodeType::RGBToHSV => {
                    generate_rgb_to_hsv_function(&mut codegen.generated_functions, code)?
                }
                _ => {}
            }
        }
    }

    Ok(())
}

pub(crate) fn generate_blur_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("blur") {
        return Ok(());
    }

    writeln!(code, "fn blur_sample(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, radius: f32) -> vec4<f32> {{").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    var color = vec4<f32>(0.0);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let samples = 9;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let offset = radius / 100.0;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    for (var x = -1; x <= 1; x++) {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        for (var y = -1; y <= 1; y++) {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "            let sample_uv = uv + vec2<f32>(f32(x), f32(y)) * offset;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "            color += textureSample(tex, samp, sample_uv);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        }}").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    }}").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return color / f32(samples);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("blur".to_string());
    Ok(())
}
pub(crate) fn generate_chromatic_aberration_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("chromatic_aberration") {
        return Ok(());
    }

    writeln!(code, "fn chromatic_aberration(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, amount: f32) -> vec4<f32> {{").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let offset = (uv - 0.5) * amount;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let r = textureSample(tex, samp, uv + offset).r;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let g = textureSample(tex, samp, uv).g;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let b = textureSample(tex, samp, uv - offset).b;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return vec4<f32>(r, g, b, 1.0);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("chromatic_aberration".to_string());
    Ok(())
}
pub(crate) fn generate_edge_detect_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("edge_detect") {
        return Ok(());
    }

    writeln!(
        code,
        "fn edge_detect(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>) -> vec4<f32> {{"
    )
    .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let offset = 1.0 / 512.0;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let c = textureSample(tex, samp, uv).rgb;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let t = textureSample(tex, samp, uv + vec2<f32>(0.0, offset)).rgb;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let b = textureSample(tex, samp, uv - vec2<f32>(0.0, offset)).rgb;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let l = textureSample(tex, samp, uv - vec2<f32>(offset, 0.0)).rgb;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let r = textureSample(tex, samp, uv + vec2<f32>(offset, 0.0)).rgb;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let edge = abs(c - t) + abs(c - b) + abs(c - l) + abs(c - r);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return vec4<f32>(edge, 1.0);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("edge_detect".to_string());
    Ok(())
}
pub(crate) fn generate_kaleidoscope_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("kaleidoscope") {
        return Ok(());
    }

    writeln!(code, "fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let center = uv - 0.5;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let angle = atan2(center.y, center.x);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let radius = length(center);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let slice = 6.28318530718 / segments;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let new_angle = abs((angle % slice) - slice * 0.5) + slice * 0.5;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return vec2<f32>(cos(new_angle), sin(new_angle)) * radius + 0.5;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("kaleidoscope".to_string());
    Ok(())
}
pub(crate) fn generate_hsv_to_rgb_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("hsv_to_rgb") {
        return Ok(());
    }

    writeln!(code, "fn hsv_to_rgb(hsv: vec3<f32>) -> vec3<f32> {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let h = hsv.x * 6.0;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let s = hsv.y;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let v = hsv.z;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let c = v * s;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let x = c * (1.0 - abs((h % 2.0) - 1.0));")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let m = v - c;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    var rgb = vec3<f32>(0.0);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    if (h < 1.0) {{ rgb = vec3<f32>(c, x, 0.0); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    else if (h < 2.0) {{ rgb = vec3<f32>(x, c, 0.0); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    else if (h < 3.0) {{ rgb = vec3<f32>(0.0, c, x); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    else if (h < 4.0) {{ rgb = vec3<f32>(0.0, x, c); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    else if (h < 5.0) {{ rgb = vec3<f32>(x, 0.0, c); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    else {{ rgb = vec3<f32>(c, 0.0, x); }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return rgb + m;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("hsv_to_rgb".to_string());
    Ok(())
}
pub(crate) fn generate_rgb_to_hsv_function(
    generated_functions: &mut HashSet<String>,
    code: &mut String,
) -> Result<()> {
    if generated_functions.contains("rgb_to_hsv") {
        return Ok(());
    }

    writeln!(code, "fn rgb_to_hsv(rgb: vec3<f32>) -> vec3<f32> {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let max_c = max(max(rgb.r, rgb.g), rgb.b);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let min_c = min(min(rgb.r, rgb.g), rgb.b);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let delta = max_c - min_c;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    var h = 0.0;").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    if (delta > 0.0) {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        if (max_c == rgb.r) {{ h = ((rgb.g - rgb.b) / delta) % 6.0; }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        else if (max_c == rgb.g) {{ h = (rgb.b - rgb.r) / delta + 2.0; }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        else {{ h = (rgb.r - rgb.g) / delta + 4.0; }}")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "        h = h / 6.0;")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    }}").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    let s = select(0.0, delta / max_c, max_c > 0.0);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    return vec3<f32>(h, s, max_c);")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "}}\n").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    generated_functions.insert("rgb_to_hsv".to_string());
    Ok(())
}
