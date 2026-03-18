/// Main evaluator implementation.
pub mod evaluator;
/// Parameter and trigger value smoothing.
pub mod smoothing;
/// Module graph traversal logic.
pub mod traversal;
/// Trigger node evaluation logic.
pub mod triggers;
/// Shared data structures and types for evaluation.
pub mod types;

pub use evaluator::ModuleEvaluator;
pub use types::*;
