use super::error::{CodegenError, Result};
use super::generator::WGSLCodegen;
use crate::shader_graph::NodeType;
use std::fmt::Write;

pub(crate) fn generate_uniforms(codegen: &WGSLCodegen, code: &mut String) -> Result<()> {
    writeln!(code, "// Uniforms").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "struct Uniforms {{")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    time: f32,").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    resolution: vec2<f32>,")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "    mouse: vec2<f32>,")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    // Add parameter uniforms
    for node_id in &codegen.node_execution_order {
        if let Some(node) = codegen.graph.nodes.get(node_id) {
            if node.node_type == NodeType::ParameterInput {
                for name in node.parameters.keys() {
                    writeln!(code, "    param_{}: f32,", name)
                        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
                }
            }
        }
    }

    writeln!(code, "}}").map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    writeln!(code, "@group(0) @binding(0) var<uniform> uniforms: Uniforms;\n")
        .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    Ok(())
}

pub(crate) fn generate_texture_bindings(codegen: &WGSLCodegen, code: &mut String) -> Result<()> {
    writeln!(code, "// Textures").map_err(|e| CodegenError::GenerationError(e.to_string()))?;

    let mut texture_count = 0;
    for node_id in &codegen.node_execution_order {
        if let Some(node) = codegen.graph.nodes.get(node_id) {
            if node.node_type == NodeType::TextureInput {
                let binding = 1 + texture_count;
                writeln!(
                    code,
                    "@group(0) @binding({}) var texture_{}: texture_2d<f32>;",
                    binding, node.id
                )
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
                writeln!(
                    code,
                    "@group(0) @binding({}) var sampler_{}: sampler;",
                    binding + 1,
                    node.id
                )
                .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
                texture_count += 2;
            }
        }
    }

    writeln!(code).map_err(|e| CodegenError::GenerationError(e.to_string()))?;
    Ok(())
}
