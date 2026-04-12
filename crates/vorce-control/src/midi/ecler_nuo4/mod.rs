//! Ecler NUO 4 DJ Mixer MIDI Controller Profile
//!
//! Professional 4-channel DJ mixer with dedicated MIDI control section.
//! MIDI values from Control 4 Lab export (working.c4l, 25 December 2025).
//!
//! # MIDI Layout
//! - Channel 1-2 (0-1 indexed): Channel 2/3 mixer controls when in MIDI mode
//! - Channel 16 (15 indexed): Dedicated MIDI control area
//! - LAYOUT selector (1-3) × A/B switch = 72 different messages

mod helpers;
mod mappings;
#[cfg(test)]
mod tests;

use crate::midi::profiles::ControllerProfile;

/// Ecler NUO 4 controller sections
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Nuo4Section {
    /// Channel 2 in MIDI mode (MIDI Channel 1)
    Channel2,
    /// Channel 3 in MIDI mode (MIDI Channel 2)
    Channel3,
    /// Dedicated MIDI Control area - center (MIDI Channel 16)
    MidiControl,
    /// Crossfader
    Crossfader,
}

/// Create Ecler NUO 4 controller profile with exact MIDI values from Control 4 Lab
pub fn ecler_nuo4() -> ControllerProfile {
    let mappings = mappings::get_mappings();

    ControllerProfile {
        name: "Ecler NUO 4".to_string(),
        manufacturer: "Ecler".to_string(),
        description: "Professional 4-channel DJ Mixer with dedicated MIDI control section. \
                      89 total mappings: CH2/3 mixer controls + 72 dedicated MIDI controls \
                      (LAYOUT 1-3 × A/B switch)."
            .to_string(),
        mappings,
    }
}
