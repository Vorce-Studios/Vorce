//! Oscillator Distortion Renderer
//!
//! Implements Kuramoto-based coupled oscillator simulation for dynamic distortion effects

pub(crate) mod init;
pub(crate) mod params;
pub(crate) mod pipelines;
pub(crate) mod render;
pub(crate) mod resources;
pub(crate) mod sim;
pub(crate) mod state;
pub(crate) mod vertex;

pub use state::OscillatorRenderer;
