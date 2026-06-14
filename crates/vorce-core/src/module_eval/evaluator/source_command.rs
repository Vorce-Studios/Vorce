/// Command for a source node
#[derive(Debug, Clone)]
pub enum SourceCommand {
    /// Play media from a local path.
    PlayMedia {
        /// Path to the media file.
        path: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Play media from the shared library.
    PlaySharedMedia {
        /// Unique identifier for the shared media.
        id: String,
        /// Path to the media file.
        path: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Render a shader with the given parameters.
    PlayShader {
        /// Name of the shader.
        name: String,
        /// List of (parameter name, value) tuples.
        params: Vec<(String, f32)>,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Receive frames from an NDI source.
    NdiInput {
        /// Name of the NDI source.
        source_name: Option<String>,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Receive frames from a live video device.
    LiveInput {
        /// ID of the capture device.
        device_id: u32,
        /// Current trigger value.
        trigger_value: f32,
    },
    #[cfg(target_os = "windows")]
    /// Receive frames from a Spout sender (Windows only).
    SpoutInput {
        /// Name of the Spout sender.
        sender_name: String,
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Input from the Bevy game engine.
    BevyInput {
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Render a 3D model via Bevy.
    Bevy3DModel {
        /// Path to the 3D model.
        path: String,
        /// Position in 3D space.
        position: [f32; 3],
        /// Rotation in degrees.
        rotation: [f32; 3],
        /// Scale factor.
        scale: [f32; 3],
        /// Current trigger value.
        trigger_value: f32,
    },
    /// Control Philips Hue smart lights.
    HueOutput {
        /// Brightness level (0.0 - 1.0).
        brightness: f32,
        /// Hue value (0.0 - 1.0, optional).
        hue: Option<f32>,
        /// Saturation level (0.0 - 1.0, optional).
        saturation: Option<f32>,
        /// Strobe speed (0.0 - 1.0, optional).
        strobe: Option<f32>,
        /// List of light IDs to control.
        ids: Option<Vec<String>>,
    },
}
