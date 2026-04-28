//! Vorce MCP - Model Context Protocol Server
//!
//! This crate implements the MCP server for Vorce, allowing AI agents to control the application.

#![allow(missing_docs)]

pub mod protocol;
pub mod server;
pub mod tools;

use std::path::PathBuf;

pub use protocol::*;
pub use server::McpServer;

// Re-export for convenience
pub use anyhow::Result;

/// Actions internally triggered by the MCP Server to be handled by the main application.
#[derive(Debug, Clone)]
pub enum McpAction {
    // === Project Management ===
    /// Get the full project state as a JSON string.
    GetProjectState(crossbeam_channel::Sender<String>),
    /// Save the project.
    SaveProject(PathBuf),
    /// Load a project.
    LoadProject(PathBuf),

    // === Layer Management ===
    /// Add a new layer.
    AddLayer(String),
    /// Remove a layer by ID.
    RemoveLayer(u64),
    /// Set layer opacity (layer_id, opacity 0.0-1.0)
    SetLayerOpacity(u64, f32),
    /// Set layer visibility (layer_id, visible)
    SetLayerVisibility(u64, bool),
    /// Set layer blend mode (layer_id, blend_mode)
    SetLayerBlendMode(u64, String),

    // === Cue Management ===
    /// Trigger a cue by ID.
    TriggerCue(u64),
    /// Go to the next cue.
    NextCue,
    /// Go to the previous cue.
    PrevCue,

    // === Media Playback ===
    /// Start media playback
    MediaPlay,
    /// Pause media playback
    MediaPause,
    /// Stop media playback
    MediaStop,

    // === Phase 1: Media in Layers ===
    /// Load media into a layer (layer_id, media_path)
    LayerLoadMedia(u64, PathBuf),
    /// Set media playback time (layer_id, time_seconds)
    LayerSetMediaTime(u64, f64),
    /// Set playback speed (layer_id, speed)
    LayerSetPlaybackSpeed(u64, f32),
    /// Set loop mode (layer_id, loop_mode: "none", "loop", "ping-pong")
    LayerSetLoopMode(u64, String),
    /// Set module source path (module_id, part_id, path) - Used for async file picking
    SetModuleSourcePath(u64, u64, PathBuf),
    /// List media library (optional folder filter)
    MediaList(Option<PathBuf>),
}
