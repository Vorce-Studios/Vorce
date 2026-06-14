use crate::shader_graph::NodeId;

#[derive(Debug, thiserror::Error)]
/// WGSL code generator error
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
