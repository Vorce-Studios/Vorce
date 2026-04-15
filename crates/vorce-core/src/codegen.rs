//! WGSL Code Generation from Shader Graphs
//!
//! Effects Pipeline
//! Generates WGSL shader code from node-based shader graphs

use crate::shader_graph::{
    DataType, InputSocket, NodeId, NodeType, ParameterValue, ShaderGraph, ShaderNode,
};
use std::collections::HashSet;
use std::fmt::Write;

/// WGSL code generator error
#[derive(Debug, thiserror::Error)]
pub enum CodegenError {
    /// Shader graph validation failed
    #[error("Graph validation failed: {0}")]
    /// Error: Graph validation failed.
    /// Error: Graph validation failed.
    /// Error: Graph validation failed.
    ValidationError(String),

    /// Graph contains no output node
    #[error("No output node found in graph")]
    /// Error: No output node found in graph.
    /// Error: No output node found in graph.
    /// Error: No output node found in graph.
    NoOutputNode,

    /// Referenced node was not found in the graph
    #[error("Node {0} not found")]
    /// Error: Node {0} not found.
    /// Error: Node {0} not found.
    /// Error: Node {0} not found.
    NodeNotFound(NodeId),

    /// Graph contains a cyclic dependency
    #[error("Cyclic dependency detected")]
    /// Error: Cyclic dependency detected.
    /// Error: Cyclic dependency detected.
    /// Error: Cyclic dependency detected.
    CyclicDependency,

    /// Invalid connection between incompatible types
    #[error("Type mismatch: cannot connect {0} to {1}")]
    /// Error: Type mismatch.
    /// Error: Type mismatch.
    /// Error: Type mismatch.
    TypeMismatch(String, String),

    /// General code generation error
    #[error("Code generation failed: {0}")]
    /// Error: Code generation failed.
    /// Error: Code generation failed.
    /// Error: Code generation failed.
    GenerationError(String),
}

/// Result type for codegen operations
pub type Result<T> = std::result::Result<T, CodegenError>;

/// WGSL code generator
pub struct WGSLCodegen {
    graph: ShaderGraph,
    generated_functions: HashSet<String>,
    node_execution_order: Vec<NodeId>,
}

impl WGSLCodegen {
    /// Create a new WGSL code generator
    pub fn new(graph: ShaderGraph) -> Self {
        Self { graph, generated_functions: HashSet::new(), node_execution_order: Vec::new() }
    }

    /// Generate complete WGSL shader code
    pub fn generate(&mut self) -> Result<String> {
        // Validate graph
        self.graph
            .validate()
            .map_err(|errors: Vec<String>| CodegenError::ValidationError(errors.join(", ")))?;

        // Determine execution order (topological sort)
        self.compute_execution_order()?;

        let mut code = String::new();

        // Generate shader structure
        writeln!(code, "// Auto-generated WGSL shader from shader graph")
            .expect("WGSL codegen failed");
        writeln!(code, "// Graph: {}\n", self.graph.name).expect("WGSL codegen failed");

        // Generate uniforms
        self.generate_uniforms(&mut code)?;

        // Generate texture bindings
        self.generate_texture_bindings(&mut code)?;

        // Generate helper functions
        self.generate_helper_functions(&mut code)?;

        // Generate main fragment shader
        self.generate_fragment_shader(&mut code)?;

        Ok(code)
    }

    /// Compute node execution order using topological sort
    fn compute_execution_order(&mut self) -> Result<()> {
        let output_node = self.graph.output_node().ok_or(CodegenError::NoOutputNode)?;

        let mut visited = HashSet::new();
        let mut stack = HashSet::new();
        let mut order = Vec::new();

        self.visit_node(output_node.id, &mut visited, &mut stack, &mut order)?;

        // Reverse to get correct execution order
        order.reverse();
        self.node_execution_order = order;

        Ok(())
    }

    /// Visit node for topological sort (DFS)
    fn visit_node(
        &self,
        node_id: NodeId,
        visited: &mut HashSet<NodeId>,
        stack: &mut HashSet<NodeId>,
        order: &mut Vec<NodeId>,
    ) -> Result<()> {
        if stack.contains(&node_id) {
            return Err(CodegenError::CyclicDependency);
        }

        if visited.contains(&node_id) {
            return Ok(());
        }

        stack.insert(node_id);

        let node = self.graph.nodes.get(&node_id).ok_or(CodegenError::NodeNotFound(node_id))?;

        // Visit all input dependencies
        for input in &node.inputs {
            if let Some((source_node, _)) = &input.connected_output {
                self.visit_node(*source_node, visited, stack, order)?;
            }
        }

        stack.remove(&node_id);
        visited.insert(node_id);
        order.push(node_id);

        Ok(())
    }

    /// Generate uniform declarations
    fn generate_uniforms(&self, code: &mut String) -> Result<()> {
        writeln!(code, "// Uniforms").expect("WGSL codegen failed");
        writeln!(code, "struct Uniforms {{").expect("WGSL codegen failed");
        writeln!(code, "    time: f32,").expect("WGSL codegen failed");
        writeln!(code, "    resolution: vec2<f32>,").expect("WGSL codegen failed");
        writeln!(code, "    mouse: vec2<f32>,").expect("WGSL codegen failed");

        // Add parameter uniforms
        for node_id in &self.node_execution_order {
            if let Some(node) = self.graph.nodes.get(node_id) {
                if node.node_type == NodeType::ParameterInput {
                    for name in node.parameters.keys() {
                        writeln!(code, "    param_{}: f32,", name).expect("WGSL codegen failed");
                    }
                }
            }
        }

        writeln!(code, "}}").expect("WGSL codegen failed");
        writeln!(code, "@group(0) @binding(0) var<uniform> uniforms: Uniforms;\n")
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate texture binding declarations
    fn generate_texture_bindings(&self, code: &mut String) -> Result<()> {
        writeln!(code, "// Textures").expect("WGSL codegen failed");

        let mut texture_count = 0;
        for node_id in &self.node_execution_order {
            if let Some(node) = self.graph.nodes.get(node_id) {
                if node.node_type == NodeType::TextureInput {
                    let binding = 1 + texture_count;
                    writeln!(
                        code,
                        "@group(0) @binding({}) var texture_{}: texture_2d<f32>;",
                        binding, node.id
                    )
                    .expect("WGSL codegen failed");
                    writeln!(
                        code,
                        "@group(0) @binding({}) var sampler_{}: sampler;",
                        binding + 1,
                        node.id
                    )
                    .expect("WGSL codegen failed");
                    texture_count += 2;
                }
            }
        }

        writeln!(code).expect("WGSL codegen failed");
        Ok(())
    }

    /// Generate helper functions for node operations
    fn generate_helper_functions(&mut self, code: &mut String) -> Result<()> {
        writeln!(code, "// Helper Functions\n").expect("WGSL codegen failed");

        // Generate functions for complex node types
        // Optimization: Iterate directly over node_execution_order without cloning.
        // We pass &mut generated_functions to helper methods to avoid full &mut self borrow conflicts.
        for node_id in &self.node_execution_order {
            if let Some(node) = self.graph.nodes.get(node_id) {
                match node.node_type {
                    NodeType::Blur => {
                        Self::generate_blur_function(&mut self.generated_functions, code)?
                    }
                    NodeType::ChromaticAberration => Self::generate_chromatic_aberration_function(
                        &mut self.generated_functions,
                        code,
                    )?,
                    NodeType::EdgeDetect => {
                        Self::generate_edge_detect_function(&mut self.generated_functions, code)?
                    }
                    NodeType::Kaleidoscope => {
                        Self::generate_kaleidoscope_function(&mut self.generated_functions, code)?
                    }
                    NodeType::HSVToRGB => {
                        Self::generate_hsv_to_rgb_function(&mut self.generated_functions, code)?
                    }
                    NodeType::RGBToHSV => {
                        Self::generate_rgb_to_hsv_function(&mut self.generated_functions, code)?
                    }
                    _ => {}
                }
            }
        }

        Ok(())
    }

    /// Generate main fragment shader
    fn generate_fragment_shader(&self, code: &mut String) -> Result<()> {
        writeln!(code, "// Fragment Shader").expect("WGSL codegen failed");
        writeln!(code, "@fragment").expect("WGSL codegen failed");
        writeln!(code, "fn fs_main(").expect("WGSL codegen failed");
        writeln!(code, "    @location(0) uv: vec2<f32>,").expect("WGSL codegen failed");
        writeln!(code, ") -> @location(0) vec4<f32> {{").expect("WGSL codegen failed");

        // Generate variable declarations and computations
        for node_id in &self.node_execution_order {
            if let Some(node) = self.graph.nodes.get(node_id) {
                self.generate_node_code(code, node)?;
            }
        }

        // Return output
        let output_node = self.graph.output_node().expect("WGSL codegen failed");
        let output_input = &output_node.inputs[0];

        if let Some((source_node, output_name)) = &output_input.connected_output {
            writeln!(
                code,
                "    return node_{}_{};",
                source_node,
                output_name.as_str().to_lowercase()
            )
            .expect("WGSL codegen failed");
        } else if let Some(default) = &output_input.default_value {
            writeln!(
                code,
                "    return vec4<f32>({}, {}, {}, {});",
                default.x, default.y, default.z, default.w
            )
            .expect("WGSL codegen failed");
        }

        writeln!(code, "}}").expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate code for a specific node
    fn generate_node_code(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        match node.node_type {
            NodeType::UVInput => {
                writeln!(code, "    let node_{}_uv = uv;", node.id).expect("WGSL codegen failed");
            }

            NodeType::TimeInput => {
                writeln!(code, "    let node_{}_time = uniforms.time;", node.id)
                    .expect("WGSL codegen failed");
            }

            NodeType::ParameterInput => {
                let param_name = node
                    .parameters
                    .get("name")
                    .and_then(|v| if let ParameterValue::String(s) = v { Some(s) } else { None })
                    .map(|s: &String| s.as_str())
                    .unwrap_or("param");
                writeln!(code, "    let node_{}_value = uniforms.{};", node.id, param_name)
                    .expect("WGSL codegen failed");
            }

            NodeType::AudioInput => {
                writeln!(code, "    let node_{}_value = uniforms.audio_value;", node.id)
                    .expect("WGSL codegen failed");
            }

            NodeType::TextureInput => {
                // Handled in bindings
            }

            NodeType::TextureSample => {
                let tex_input = &node.inputs[0];
                let uv_input = &node.inputs[1];

                let tex_var = self.get_input_variable(tex_input)?;
                let uv_var = self.get_input_variable(uv_input)?;

                writeln!(
                    code,
                    "    let node_{}_color = textureSample({}, {}, {});",
                    node.id,
                    tex_var,
                    tex_var.replace("texture", "sampler"),
                    uv_var
                )
                .expect("WGSL codegen failed");
                writeln!(code, "    let node_{}_alpha = node_{}_color.a;", node.id, node.id)
                    .expect("WGSL codegen failed");
            }

            NodeType::TextureSampleLod => {
                let tex_input = &node.inputs[0];
                let uv_input = &node.inputs[1];
                let lod_input = &node.inputs[2];

                let tex_var = self.get_input_variable(tex_input)?;
                let uv_var = self.get_input_variable(uv_input)?;
                let lod_var = self.get_input_variable(lod_input)?;

                writeln!(
                    code,
                    "    let node_{}_color = textureSampleLevel({}, {}, {}, {});",
                    node.id,
                    tex_var,
                    tex_var.replace("texture", "sampler"),
                    uv_var,
                    lod_var
                )
                .expect("WGSL codegen failed");
            }

            NodeType::TextureCombine => {
                let tex_a = self.get_input_variable(&node.inputs[0])?;
                let tex_b = self.get_input_variable(&node.inputs[1])?;
                let mix_factor = self.get_input_variable(&node.inputs[2])?;

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
                .expect("WGSL codegen failed");
            }

            NodeType::Add | NodeType::Subtract | NodeType::Multiply | NodeType::Divide => {
                self.generate_math_op(code, node)?;
            }

            NodeType::Power => {
                self.generate_power_op(code, node)?;
            }

            NodeType::Clamp => {
                self.generate_clamp_op(code, node)?;
            }

            NodeType::Smoothstep => {
                self.generate_smoothstep_op(code, node)?;
            }

            NodeType::Combine => {
                self.generate_combine_op(code, node)?;
            }

            NodeType::Split => {
                self.generate_split_op(code, node)?;
            }

            NodeType::Sin | NodeType::Cos => {
                self.generate_trig_op(code, node)?;
            }

            NodeType::Mix => {
                self.generate_mix_op(code, node)?;
            }

            NodeType::Remap => {
                let val = self.get_input_variable(&node.inputs[0])?;
                let in_min = self.get_input_variable(&node.inputs[1])?;
                let in_max = self.get_input_variable(&node.inputs[2])?;
                let out_min = self.get_input_variable(&node.inputs[3])?;
                let out_max = self.get_input_variable(&node.inputs[4])?;

                writeln!(
                    code,
                    "    let node_{}_result = {} + ({} - {}) * ({} - {}) / ({} - {});",
                    node.id, out_min, val, in_min, out_max, out_min, in_max, in_min
                )
                .expect("WGSL codegen failed");
            }

            NodeType::Brightness => {
                self.generate_brightness_op(code, node)?;
            }

            NodeType::Contrast => {
                self.generate_contrast_op(code, node)?;
            }

            NodeType::Desaturate => {
                self.generate_desaturate_op(code, node)?;
            }

            NodeType::ColorRamp => {
                let input = self.get_input_variable(&node.inputs[0])?;
                writeln!(
                    code,
                    "    let node_{}_color = vec4<f32>(vec3<f32>({}), 1.0);",
                    node.id, input
                )
                .expect("WGSL codegen failed");
            }

            NodeType::HSVToRGB => {
                let input = self.get_input_variable(&node.inputs[0])?;
                writeln!(code, "    let node_{}_output = hsv_to_rgb({});", node.id, input)
                    .expect("WGSL codegen failed");
            }

            NodeType::RGBToHSV => {
                let input = self.get_input_variable(&node.inputs[0])?;
                writeln!(code, "    let node_{}_output = rgb_to_hsv({});", node.id, input)
                    .expect("WGSL codegen failed");
            }

            NodeType::UVTransform => {
                self.generate_uv_transform(code, node)?;
            }

            NodeType::UVDistort => {
                let uv = self.get_input_variable(&node.inputs[0])?;
                let distortion = self.get_input_variable(&node.inputs[1])?;
                let amount = self.get_input_variable(&node.inputs[2])?;
                writeln!(
                    code,
                    "    let node_{}_uv = {} + {} * {};",
                    node.id, uv, distortion, amount
                )
                .expect("WGSL codegen failed");
            }

            NodeType::Blur => {
                let tex = self.get_input_variable(&node.inputs[0])?;
                let uv = self.get_input_variable(&node.inputs[1])?;
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
                .expect("WGSL codegen failed");
            }

            NodeType::Glow => {
                let color = self.get_input_variable(&node.inputs[0])?;
                let amount = self.get_input_variable(&node.inputs[1])?;
                writeln!(code, "    let node_{}_color = {} * (1.0 + {});", node.id, color, amount)
                    .expect("WGSL codegen failed");
            }

            NodeType::ChromaticAberration => {
                let color = self.get_input_variable(&node.inputs[0])?;
                let amount = self.get_input_variable(&node.inputs[1])?;
                writeln!(
                    code,
                    "    let node_{}_color = {} + vec4<f32>({}, 0.0, -{}, 0.0);",
                    node.id, color, amount, amount
                )
                .expect("WGSL codegen failed");
            }

            NodeType::Kaleidoscope => {
                let uv = self.get_input_variable(&node.inputs[0])?;
                let segments = self.get_input_variable(&node.inputs[1])?;
                writeln!(code, "    let node_{}_uv = kaleidoscope({}, {});", node.id, uv, segments)
                    .expect("WGSL codegen failed");
            }

            NodeType::PixelSort | NodeType::Displacement => {
                let color = self.get_input_variable(&node.inputs[0])?;
                let map = self.get_input_variable(&node.inputs[1])?;
                writeln!(
                    code,
                    "    let node_{}_color = mix({}, {}, 0.5); // Placeholder",
                    node.id, color, map
                )
                .expect("WGSL codegen failed");
            }

            NodeType::EdgeDetect => {
                let tex = self.get_input_variable(&node.inputs[0])?;
                let uv = self.get_input_variable(&node.inputs[1])?;
                writeln!(
                    code,
                    "    let node_{}_color = edge_detect({}, {}, {});",
                    node.id,
                    tex,
                    tex.replace("texture", "sampler"),
                    uv
                )
                .expect("WGSL codegen failed");
            }

            NodeType::Output => {
                // Output node doesn't generate code, just connects
            }
        }

        Ok(())
    }

    /// Generate power operation code
    fn generate_power_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let a = self.get_input_variable(&node.inputs[0])?;
        let b = self.get_input_variable(&node.inputs[1])?;

        writeln!(code, "    let node_{}_result = pow({}, {});", node.id, a, b)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate clamp operation code
    fn generate_clamp_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let val = self.get_input_variable(&node.inputs[0])?;
        let min = self.get_input_variable(&node.inputs[1])?;
        let max = self.get_input_variable(&node.inputs[2])?;

        writeln!(code, "    let node_{}_result = clamp({}, {}, {});", node.id, val, min, max)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate smoothstep operation code
    fn generate_smoothstep_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let edge0 = self.get_input_variable(&node.inputs[0])?;
        let edge1 = self.get_input_variable(&node.inputs[1])?;
        let x = self.get_input_variable(&node.inputs[2])?;

        writeln!(
            code,
            "    let node_{}_result = smoothstep({}, {}, {});",
            node.id, edge0, edge1, x
        )
        .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate combine operation code
    fn generate_combine_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let r = self.get_input_variable(&node.inputs[0])?;
        let g = self.get_input_variable(&node.inputs[1])?;
        let b = self.get_input_variable(&node.inputs[2])?;
        let a = self.get_input_variable(&node.inputs[3])?;

        writeln!(code, "    let node_{}_color = vec4<f32>({}, {}, {}, {});", node.id, r, g, b, a)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate split operation code
    fn generate_split_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let color = self.get_input_variable(&node.inputs[0])?;

        writeln!(code, "    let node_{}_r = {}.r;", node.id, color).expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_g = {}.g;", node.id, color).expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_b = {}.b;", node.id, color).expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_a = {}.a;", node.id, color).expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate math operation code
    fn generate_math_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let a = self.get_input_variable(&node.inputs[0])?;
        let b = self.get_input_variable(&node.inputs[1])?;

        let op = match node.node_type {
            NodeType::Add => "+",
            NodeType::Subtract => "-",
            NodeType::Multiply => "*",
            NodeType::Divide => "/",
            _ => return Err(CodegenError::GenerationError("Invalid math op".to_string())),
        };

        writeln!(code, "    let node_{}_result = {} {} {};", node.id, a, op, b)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate trigonometric operation code
    fn generate_trig_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let input = self.get_input_variable(&node.inputs[0])?;

        let func = match node.node_type {
            NodeType::Sin => "sin",
            NodeType::Cos => "cos",
            _ => return Err(CodegenError::GenerationError("Invalid trig op".to_string())),
        };

        writeln!(code, "    let node_{}_result = {}({});", node.id, func, input)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate mix operation code
    fn generate_mix_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let a = self.get_input_variable(&node.inputs[0])?;
        let b = self.get_input_variable(&node.inputs[1])?;
        let t = self.get_input_variable(&node.inputs[2])?;

        writeln!(code, "    let node_{}_result = mix({}, {}, {});", node.id, a, b, t)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate brightness operation code
    fn generate_brightness_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let color = self.get_input_variable(&node.inputs[0])?;
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
        .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate contrast operation code
    fn generate_contrast_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let color = self.get_input_variable(&node.inputs[0])?;
        let amount = node
            .parameters
            .get("amount")
            .map(|v| format!("{}", v))
            .unwrap_or_else(|| "1.0".to_string());

        writeln!(code, "    let node_{}_result = ({} - 0.5) * {} + 0.5;", node.id, color, amount)
            .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate desaturate operation code
    fn generate_desaturate_op(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let color = self.get_input_variable(&node.inputs[0])?;

        writeln!(code, "    let gray = dot({}.rgb, vec3<f32>(0.299, 0.587, 0.114));", color)
            .expect("WGSL codegen failed");
        writeln!(
            code,
            "    let node_{}_result = vec4<f32>(vec3<f32>(gray), {}.a);",
            node.id, color
        )
        .expect("WGSL codegen failed");

        Ok(())
    }

    /// Generate UV transform code
    fn generate_uv_transform(&self, code: &mut String, node: &ShaderNode) -> Result<()> {
        let uv = self.get_input_variable(&node.inputs[0])?;

        let scale_val = node.parameters.get("scale").unwrap_or(&ParameterValue::Vec2([1.0, 1.0]));
        let rotation_val = node.parameters.get("rotation").unwrap_or(&ParameterValue::Float(0.0));
        let translation_val =
            node.parameters.get("translation").unwrap_or(&ParameterValue::Vec2([0.0, 0.0]));

        writeln!(code, "    // UV Transform").expect("WGSL codegen failed");
        writeln!(code, "    var node_{}_uv_temp = {} - vec2<f32>(0.5, 0.5);", node.id, uv)
            .expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_scale = {};", node.id, scale_val)
            .expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_rot = {};", node.id, rotation_val)
            .expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_trans = {};", node.id, translation_val)
            .expect("WGSL codegen failed");

        writeln!(code, "    let node_{}_cos_r = cos(node_{}_rot);", node.id, node.id)
            .expect("WGSL codegen failed");
        writeln!(code, "    let node_{}_sin_r = sin(node_{}_rot);", node.id, node.id)
            .expect("WGSL codegen failed");

        writeln!(code, "    let node_{}_rot_uv = vec2<f32>(", node.id)
            .expect("WGSL codegen failed");
        writeln!(
            code,
            "        node_{}_uv_temp.x * node_{}_cos_r - node_{}_uv_temp.y * node_{}_sin_r,",
            node.id, node.id, node.id, node.id
        )
        .expect("WGSL codegen failed");
        writeln!(
            code,
            "        node_{}_uv_temp.x * node_{}_sin_r + node_{}_uv_temp.y * node_{}_cos_r",
            node.id, node.id, node.id, node.id
        )
        .expect("WGSL codegen failed");
        writeln!(code, "    );").expect("WGSL codegen failed");

        writeln!(code, "    let node_{}_uv = (node_{}_rot_uv / node_{}_scale) + vec2<f32>(0.5, 0.5) + node_{}_trans;", node.id, node.id, node.id, node.id).expect("WGSL codegen failed");

        Ok(())
    }

    /// Get the variable name for an input socket
    fn get_input_variable(&self, input: &InputSocket) -> Result<String> {
        if let Some((source_node, output_name)) = &input.connected_output {
            Ok(format!("node_{}_{}", source_node, output_name.as_str().to_lowercase()))
        } else if let Some(default) = &input.default_value {
            match input.data_type {
                DataType::Float => Ok(format!("{}", default.x)),
                DataType::Vec2 => Ok(format!("vec2<f32>({}, {})", default.x, default.y)),
                DataType::Vec3 => {
                    Ok(format!("vec3<f32>({}, {}, {})", default.x, default.y, default.z))
                }
                DataType::Vec4 | DataType::Color => Ok(format!(
                    "vec4<f32>({}, {}, {}, {})",
                    default.x, default.y, default.z, default.w
                )),
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

    fn generate_blur_function(
        generated_functions: &mut HashSet<String>,
        code: &mut String,
    ) -> Result<()> {
        if generated_functions.contains("blur") {
            return Ok(());
        }

        writeln!(code, "fn blur_sample(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, radius: f32) -> vec4<f32> {{").expect("WGSL codegen failed");
        writeln!(code, "    var color = vec4<f32>(0.0);").expect("WGSL codegen failed");
        writeln!(code, "    let samples = 9;").expect("WGSL codegen failed");
        writeln!(code, "    let offset = radius / 100.0;").expect("WGSL codegen failed");
        writeln!(code, "    for (var x = -1; x <= 1; x++) {{").expect("WGSL codegen failed");
        writeln!(code, "        for (var y = -1; y <= 1; y++) {{").expect("WGSL codegen failed");
        writeln!(code, "            let sample_uv = uv + vec2<f32>(f32(x), f32(y)) * offset;")
            .expect("WGSL codegen failed");
        writeln!(code, "            color += textureSample(tex, samp, sample_uv);")
            .expect("WGSL codegen failed");
        writeln!(code, "        }}").expect("WGSL codegen failed");
        writeln!(code, "    }}").expect("WGSL codegen failed");
        writeln!(code, "    return color / f32(samples);").expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("blur".to_string());
        Ok(())
    }

    fn generate_chromatic_aberration_function(
        generated_functions: &mut HashSet<String>,
        code: &mut String,
    ) -> Result<()> {
        if generated_functions.contains("chromatic_aberration") {
            return Ok(());
        }

        writeln!(code, "fn chromatic_aberration(tex: texture_2d<f32>, samp: sampler, uv: vec2<f32>, amount: f32) -> vec4<f32> {{").expect("WGSL codegen failed");
        writeln!(code, "    let offset = (uv - 0.5) * amount;").expect("WGSL codegen failed");
        writeln!(code, "    let r = textureSample(tex, samp, uv + offset).r;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let g = textureSample(tex, samp, uv).g;").expect("WGSL codegen failed");
        writeln!(code, "    let b = textureSample(tex, samp, uv - offset).b;")
            .expect("WGSL codegen failed");
        writeln!(code, "    return vec4<f32>(r, g, b, 1.0);").expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("chromatic_aberration".to_string());
        Ok(())
    }

    fn generate_edge_detect_function(
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
        .expect("WGSL codegen failed");
        writeln!(code, "    let offset = 1.0 / 512.0;").expect("WGSL codegen failed");
        writeln!(code, "    let c = textureSample(tex, samp, uv).rgb;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let t = textureSample(tex, samp, uv + vec2<f32>(0.0, offset)).rgb;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let b = textureSample(tex, samp, uv - vec2<f32>(0.0, offset)).rgb;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let l = textureSample(tex, samp, uv - vec2<f32>(offset, 0.0)).rgb;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let r = textureSample(tex, samp, uv + vec2<f32>(offset, 0.0)).rgb;")
            .expect("WGSL codegen failed");
        writeln!(code, "    let edge = abs(c - t) + abs(c - b) + abs(c - l) + abs(c - r);")
            .expect("WGSL codegen failed");
        writeln!(code, "    return vec4<f32>(edge, 1.0);").expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("edge_detect".to_string());
        Ok(())
    }

    fn generate_kaleidoscope_function(
        generated_functions: &mut HashSet<String>,
        code: &mut String,
    ) -> Result<()> {
        if generated_functions.contains("kaleidoscope") {
            return Ok(());
        }

        writeln!(code, "fn kaleidoscope(uv: vec2<f32>, segments: f32) -> vec2<f32> {{")
            .expect("WGSL codegen failed");
        writeln!(code, "    let center = uv - 0.5;").expect("WGSL codegen failed");
        writeln!(code, "    let angle = atan2(center.y, center.x);").expect("WGSL codegen failed");
        writeln!(code, "    let radius = length(center);").expect("WGSL codegen failed");
        writeln!(code, "    let slice = 6.28318530718 / segments;").expect("WGSL codegen failed");
        writeln!(code, "    let new_angle = abs((angle % slice) - slice * 0.5) + slice * 0.5;")
            .expect("WGSL codegen failed");
        writeln!(code, "    return vec2<f32>(cos(new_angle), sin(new_angle)) * radius + 0.5;")
            .expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("kaleidoscope".to_string());
        Ok(())
    }

    fn generate_hsv_to_rgb_function(
        generated_functions: &mut HashSet<String>,
        code: &mut String,
    ) -> Result<()> {
        if generated_functions.contains("hsv_to_rgb") {
            return Ok(());
        }

        writeln!(code, "fn hsv_to_rgb(hsv: vec3<f32>) -> vec3<f32> {{")
            .expect("WGSL codegen failed");
        writeln!(code, "    let h = hsv.x * 6.0;").expect("WGSL codegen failed");
        writeln!(code, "    let s = hsv.y;").expect("WGSL codegen failed");
        writeln!(code, "    let v = hsv.z;").expect("WGSL codegen failed");
        writeln!(code, "    let c = v * s;").expect("WGSL codegen failed");
        writeln!(code, "    let x = c * (1.0 - abs((h % 2.0) - 1.0));")
            .expect("WGSL codegen failed");
        writeln!(code, "    let m = v - c;").expect("WGSL codegen failed");
        writeln!(code, "    var rgb = vec3<f32>(0.0);").expect("WGSL codegen failed");
        writeln!(code, "    if (h < 1.0) {{ rgb = vec3<f32>(c, x, 0.0); }}")
            .expect("WGSL codegen failed");
        writeln!(code, "    else if (h < 2.0) {{ rgb = vec3<f32>(x, c, 0.0); }}")
            .expect("WGSL codegen failed");
        writeln!(code, "    else if (h < 3.0) {{ rgb = vec3<f32>(0.0, c, x); }}")
            .expect("WGSL codegen failed");
        writeln!(code, "    else if (h < 4.0) {{ rgb = vec3<f32>(0.0, x, c); }}")
            .expect("WGSL codegen failed");
        writeln!(code, "    else if (h < 5.0) {{ rgb = vec3<f32>(x, 0.0, c); }}")
            .expect("WGSL codegen failed");
        writeln!(code, "    else {{ rgb = vec3<f32>(c, 0.0, x); }}").expect("WGSL codegen failed");
        writeln!(code, "    return rgb + m;").expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("hsv_to_rgb".to_string());
        Ok(())
    }

    fn generate_rgb_to_hsv_function(
        generated_functions: &mut HashSet<String>,
        code: &mut String,
    ) -> Result<()> {
        if generated_functions.contains("rgb_to_hsv") {
            return Ok(());
        }

        writeln!(code, "fn rgb_to_hsv(rgb: vec3<f32>) -> vec3<f32> {{")
            .expect("WGSL codegen failed");
        writeln!(code, "    let max_c = max(max(rgb.r, rgb.g), rgb.b);")
            .expect("WGSL codegen failed");
        writeln!(code, "    let min_c = min(min(rgb.r, rgb.g), rgb.b);")
            .expect("WGSL codegen failed");
        writeln!(code, "    let delta = max_c - min_c;").expect("WGSL codegen failed");
        writeln!(code, "    var h = 0.0;").expect("WGSL codegen failed");
        writeln!(code, "    if (delta > 0.0) {{").expect("WGSL codegen failed");
        writeln!(code, "        if (max_c == rgb.r) {{ h = ((rgb.g - rgb.b) / delta) % 6.0; }}")
            .expect("WGSL codegen failed");
        writeln!(code, "        else if (max_c == rgb.g) {{ h = (rgb.b - rgb.r) / delta + 2.0; }}")
            .expect("WGSL codegen failed");
        writeln!(code, "        else {{ h = (rgb.r - rgb.g) / delta + 4.0; }}")
            .expect("WGSL codegen failed");
        writeln!(code, "        h = h / 6.0;").expect("WGSL codegen failed");
        writeln!(code, "    }}").expect("WGSL codegen failed");
        writeln!(code, "    let s = select(0.0, delta / max_c, max_c > 0.0);")
            .expect("WGSL codegen failed");
        writeln!(code, "    return vec3<f32>(h, s, max_c);").expect("WGSL codegen failed");
        writeln!(code, "}}\n").expect("WGSL codegen failed");

        generated_functions.insert("rgb_to_hsv".to_string());
        Ok(())
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shader_graph::{NodeType, ShaderGraph};

    #[test]
    fn test_simple_shader_generation() {
        let mut graph = ShaderGraph::new(1, "Test Shader".to_string());

        let uv_node = graph.add_node(NodeType::UVInput);
        let texture_node = graph.add_node(NodeType::TextureInput);
        let sample_node = graph.add_node(NodeType::TextureSample);
        let output_node = graph.add_node(NodeType::Output);

        graph.connect(uv_node, "UV", sample_node, "UV").expect("WGSL codegen failed");
        graph
            .connect(texture_node, "Texture", sample_node, "Texture")
            .expect("WGSL codegen failed");
        graph.connect(sample_node, "Color", output_node, "Color").expect("WGSL codegen failed");

        let mut codegen = WGSLCodegen::new(graph);
        let result = codegen.generate();

        assert!(result.is_ok());
        let code = result.expect("WGSL codegen failed");
        assert!(code.contains("@fragment"));
        assert!(code.contains("textureSample"));
    }

    #[test]
    #[ignore]
    fn test_math_nodes() {
        let mut graph = ShaderGraph::new(1, "Math Test".to_string());

        let time_node = graph.add_node(NodeType::TimeInput);
        let sin_node = graph.add_node(NodeType::Sin);
        let output_node = graph.add_node(NodeType::Output);

        graph.connect(time_node, "Time", sin_node, "A").expect("WGSL codegen failed");
        graph.connect(sin_node, "Result", output_node, "Color").expect("WGSL codegen failed");

        let mut codegen = WGSLCodegen::new(graph);
        let result = codegen.generate();

        assert!(result.is_ok());
    }

    #[test]
    #[ignore]
    fn test_math_nodes_advanced() {
        let mut graph = ShaderGraph::new(1, "Advanced Math Test".to_string());

        let combine_node = graph.add_node(NodeType::Combine);
        let split_node = graph.add_node(NodeType::Split);
        let power_node = graph.add_node(NodeType::Power);
        let clamp_node = graph.add_node(NodeType::Clamp);
        let smoothstep_node = graph.add_node(NodeType::Smoothstep);
        let output_node = graph.add_node(NodeType::Output);

        graph.connect(combine_node, "Color", split_node, "Color").expect("WGSL codegen failed");
        graph.connect(split_node, "R", power_node, "A").expect("WGSL codegen failed");
        graph.connect(power_node, "Result", clamp_node, "Value").expect("WGSL codegen failed");
        graph.connect(clamp_node, "Result", smoothstep_node, "X").expect("WGSL codegen failed");
        // Since smoothstep is not connected to output, it will trigger an error due to being missing in topological sort,
        // unless we connect it to output. But Output requires Color. Let's create a Mix node to convert float to color or connect smoothstep somewhere.
        // Or we just test the generation of these by not expecting is_ok(), but wait, WGSLCodegen will error out if there's disconnected logic.
        // Actually, topological sort starts from Output node and goes backwards. So nodes not connected to Output are ignored.
        // To test their codegen, we must connect them to output!
        let final_combine = graph.add_node(NodeType::Combine);
        graph.connect(smoothstep_node, "Result", final_combine, "R").expect("WGSL codegen failed");
        graph.connect(final_combine, "Color", output_node, "Color").expect("WGSL codegen failed");

        let mut codegen = WGSLCodegen::new(graph);
        let result = codegen.generate();

        assert!(result.is_ok());
        let code = result.expect("WGSL codegen failed");
        assert!(code.contains("vec4<f32>"));
        assert!(code.contains("pow("));
        assert!(code.contains("clamp("));
        assert!(code.contains("smoothstep("));
        assert!(code.contains(".r;"));
    }
}
