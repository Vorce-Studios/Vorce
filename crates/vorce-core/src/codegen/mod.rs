//! WGSL Code Generation from Shader Graphs
//!
//! Effects Pipeline
//! Generates WGSL shader code from node-based shader graphs

/// Texture and uniform bindings generators
mod bindings;
/// Error types for codegen
pub mod error;
/// Main WGSL codegen struct and generation flow
pub mod generator;
/// Helper function generators for specific nodes
mod helpers;
/// Emitters for specific operations
mod operations;

#[cfg(test)]
mod tests;

pub use error::{CodegenError, Result};
pub use generator::WGSLCodegen;
