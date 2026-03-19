//!
//! Socket definitions.
//!

use serde::{Deserialize, Serialize};

/// Direction of a module socket.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum ModuleSocketDirection {
    /// Input socket.
    #[default]
    Input,
    /// Output socket.
    Output,
}

/// A connection point on a node
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ModuleSocket {
    /// Stable schema ID for this socket.
    #[serde(default)]
    pub id: String,
    /// Label for the socket
    pub name: String,
    /// Data type accepted/provided
    pub socket_type: ModuleSocketType,
    /// Whether this socket is an input or output.
    #[serde(default)]
    pub direction: ModuleSocketDirection,
    /// Whether the inspector may map trigger automation onto this input.
    #[serde(default)]
    pub supports_trigger_mapping: bool,
    /// Whether this socket is the primary path for the render chain.
    #[serde(default)]
    pub is_primary: bool,
    /// Whether multiple connections may target this input.
    #[serde(default)]
    pub accepts_multiple_connections: bool,
}

impl ModuleSocket {
    /// Create a new input socket.
    pub fn input(
        id: impl Into<String>,
        name: impl Into<String>,
        socket_type: ModuleSocketType,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            socket_type,
            direction: ModuleSocketDirection::Input,
            supports_trigger_mapping: false,
            is_primary: false,
            accepts_multiple_connections: false,
        }
    }

    /// Create a new input socket that supports trigger mapping.
    pub fn input_mappable(
        id: impl Into<String>,
        name: impl Into<String>,
        socket_type: ModuleSocketType,
    ) -> Self {
        Self {
            supports_trigger_mapping: true,
            ..Self::input(id, name, socket_type)
        }
    }

    /// Create a new output socket.
    pub fn output(
        id: impl Into<String>,
        name: impl Into<String>,
        socket_type: ModuleSocketType,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            socket_type,
            direction: ModuleSocketDirection::Output,
            supports_trigger_mapping: false,
            is_primary: false,
            accepts_multiple_connections: false,
        }
    }

    /// Mark a socket as primary.
    pub fn primary(mut self) -> Self {
        self.is_primary = true;
        self
    }

    /// Allow multiple connections on this socket.
    pub fn multi_input(mut self) -> Self {
        self.accepts_multiple_connections = true;
        self
    }

    /// Check whether a source socket may connect into a target socket.
    pub fn is_compatible_with(&self, target: &Self) -> bool {
        self.direction == ModuleSocketDirection::Output
            && target.direction == ModuleSocketDirection::Input
            && self.socket_type == target.socket_type
    }

    /// Create a standard media input socket.
    pub fn standard_media_in(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::input(id, name, ModuleSocketType::Media)
    }

    /// Create a standard media output socket.
    pub fn standard_media_out(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::output(id, name, ModuleSocketType::Media)
    }

    /// Create a standard trigger input socket (mappable).
    pub fn standard_trigger_in(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::input_mappable(id, name, ModuleSocketType::Trigger)
    }

    /// Create a standard trigger output socket.
    pub fn standard_trigger_out(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::output(id, name, ModuleSocketType::Trigger)
    }

    /// Create a standard layer input socket.
    pub fn standard_layer_in(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::input(id, name, ModuleSocketType::Layer)
    }

    /// Create a standard layer output socket.
    pub fn standard_layer_out(id: impl Into<String>, name: impl Into<String>) -> Self {
        Self::output(id, name, ModuleSocketType::Layer)
    }
}

/// Type of data carried by a connection
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ModuleSocketType {
    /// Event-based trigger node.
    Trigger,
    /// Enumeration variant.
    Media,
    /// Enumeration variant.
    Effect,
    /// A compositing layer within a scene.
    Layer,
    /// Enumeration variant.
    Output,
    /// Enumeration variant.
    Link,
}

impl ModuleSocketType {
    /// Human-readable display name.
    pub fn name(&self) -> &'static str {
        match self {
            ModuleSocketType::Trigger => "Trigger",
            ModuleSocketType::Media => "Media",
            ModuleSocketType::Effect => "Effect",
            ModuleSocketType::Layer => "Layer",
            ModuleSocketType::Output => "Output",
            ModuleSocketType::Link => "Link",
        }
    }
}

/// Blend mode types
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BlendModeType {
    /// Enumeration variant.
    Normal,
    /// Enumeration variant.
    Add,
    /// Enumeration variant.
    Multiply,
    /// Enumeration variant.
    Screen,
    /// Enumeration variant.
    Overlay,
    /// Enumeration variant.
    Difference,
    /// Enumeration variant.
    Exclusion,
}

impl BlendModeType {
    /// Associated function.
    pub fn all() -> &'static [BlendModeType] {
        &[
            BlendModeType::Normal,
            BlendModeType::Add,
            BlendModeType::Multiply,
            BlendModeType::Screen,
            BlendModeType::Overlay,
            BlendModeType::Difference,
            BlendModeType::Exclusion,
        ]
    }

    /// Human-readable display name.
    pub fn name(&self) -> &'static str {
        match self {
            BlendModeType::Normal => "Normal",
            BlendModeType::Add => "Add",
            BlendModeType::Multiply => "Multiply",
            BlendModeType::Screen => "Screen",
            BlendModeType::Overlay => "Overlay",
            BlendModeType::Difference => "Difference",
            BlendModeType::Exclusion => "Exclusion",
        }
    }
}
