//! WGSL/Rust Code Generation from Shader Graphs
//!
//! Effects Pipeline
//! Generates WGSL and Rust shader code from node-based shader graphs

/// Error types for codegen operations
pub mod error;
/// Rust code generator implementation (scaffolding)
pub mod rust;
/// WGSL code generator implementation
pub mod wgsl;

pub use error::{CodegenError, Result};
pub use wgsl::WGSLCodegen;
