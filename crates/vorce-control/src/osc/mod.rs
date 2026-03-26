//! OSC (Open Sound Control) system
//!
//! This module provides OSC server and client functionality for remote control of Vorce.
//!
//! ## OSC Address Space
//!
//! ```text
//! /Vorce/layer/{id}/opacity       [f32: 0.0-1.0]
//! /Vorce/layer/{id}/position      [f32, f32: x, y]
//! /Vorce/layer/{id}/rotation      [f32: degrees]
//! /Vorce/layer/{id}/scale         [f32: scale]
//! /Vorce/layer/{id}/visibility    [bool]
//! /Vorce/paint/{id}/parameter/{name}  [varies]
//! /Vorce/effect/{id}/parameter/{name} [varies]
//! /Vorce/playback/speed           [f32: speed multiplier]
//! /Vorce/playback/position        [f32: 0.0-1.0]
//! /Vorce/output/{id}/brightness   [f32: 0.0-1.0]
//! ```
//!
//! ## Example Usage
//!
//! ```rust,no_run
//! use vorce_control::osc::{OscServer, OscClient};
//! use vorce_control::{ControlTarget, ControlValue};
//!
//! # #[cfg(feature = "osc")]
//! # fn main() -> vorce_control::Result<()> {
//! // Create server
//! let server = OscServer::new(8000)?;
//!
//! // Create client for sending state updates
//! let client = OscClient::new("192.168.1.100:8001")?;
//!
//! // Poll for packets
//! while let Some(_packet) = server.poll_packet() {
//!     // Handle the OSC packet (Message or Bundle)
//!     println!("Received OSC packet");
//! }
//! # Ok(())
//! # }
//! # #[cfg(not(feature = "osc"))]
//! # fn main() {}
//! ```

pub mod address;
pub mod client;
pub mod mapping;
pub mod server;
pub mod types;

pub use address::{control_target_to_address, parse_osc_address};
pub use client::OscClient;
pub use mapping::OscMapping;
pub use server::OscServer;

#[cfg(feature = "osc")]
pub use types::{control_value_to_osc, osc_to_control_value, osc_to_vec2, osc_to_vec3};
