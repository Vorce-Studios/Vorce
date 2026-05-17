//! Scene-specific render sub-loops to split the orchestration logic.

/// 2D scene rendering logic.
pub mod scene_2d;

/// Post processing passes like color calibration and edge blending.
pub mod post_processing;

/// UI overlay rendering using egui.
pub mod overlay;
