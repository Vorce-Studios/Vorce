use super::bindings::{generate_texture_bindings, generate_uniforms};
use super::error::{CodegenError, Result};
use super::helpers::generate_helper_functions;
use super::operations::generate_fragment_shader;
use crate::shader_graph::{NodeId, ShaderGraph};
use std::collections::HashSet;
use std::fmt::Write;

/// WGSL code generator
pub struct WGSLCodegen {
    pub(crate) graph: ShaderGraph,
    pub(crate) generated_functions: HashSet<String>,
    pub(crate) node_execution_order: Vec<NodeId>,
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
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;
        writeln!(code, "// Graph: {}\n", self.graph.name)
            .map_err(|e| CodegenError::GenerationError(e.to_string()))?;

        // Generate uniforms
        generate_uniforms(self, &mut code)?;

        // Generate texture bindings
        generate_texture_bindings(self, &mut code)?;

        // Generate helper functions
        generate_helper_functions(self, &mut code)?;

        // Generate main fragment shader
        generate_fragment_shader(self, &mut code)?;

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

        // Visit all dependencies
        for input in node.inputs.iter() {
            if let Some(conn) = &input.connected_output {
                self.visit_node(conn.0, visited, stack, order)?;
            }
        }

        stack.remove(&node_id);
        visited.insert(node_id);
        order.push(node_id);

        Ok(())
    }
}
