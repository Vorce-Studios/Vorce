/// Node evaluation and module logic.
pub mod evaluation;
/// Media player orchestration.
pub mod media;
/// NDI synchronization and frame polling.
#[cfg(feature = "ndi")]
pub mod ndi;
/// Specialized node logic (e.g. Bevy synchronization).
pub mod node_logic;
/// Output window management.
pub mod outputs;
