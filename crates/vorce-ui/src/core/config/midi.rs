use serde::{Deserialize, Serialize};
use std::fmt;

/// MIDI element assignment target
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MidiAssignmentTarget {
    /// Assigned to Vorce internal control
    #[serde(alias = "MapFlow")]
    Vorce(String), // Control target ID
    /// Assigned to Streamer.bot function
    StreamerBot(String), // Function name
}

impl fmt::Display for MidiAssignmentTarget {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Vorce(id) => write!(f, "Vorce: {}", id),
            Self::StreamerBot(func) => write!(f, "Streamer.bot: {}", func),
        }
    }
}

/// A single MIDI element assignment
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MidiAssignment {
    /// Element ID from the controller (e.g., "ch2_gain")
    pub element_id: String,
    /// Assignment target
    pub target: MidiAssignmentTarget,
}
