//! Ableton Link integration (placeholder wrapper)
//!
//! This module wires in the `ableton-link-rs` crate so that trigger nodes
//! can rely on Link tempo information without panicking when the service
//! is unavailable. The lightweight wrapper avoids spawning background tasks
//! until explicitly requested by the caller.

use ableton_link_rs::link::{clock::Clock, tempo::Tempo};

use crate::{error::ControlError, Result};

/// Minimal Ableton Link handle
pub struct AbletonLinkHandle {
    _tempo: Tempo,
    _clock: Clock,
}

impl AbletonLinkHandle {
    /// Create a lightweight handle with default tempo.
    ///
    /// The underlying `ableton-link-rs` types are constructed but no async
    /// tasks are spawned here, keeping initialization cheap.
    pub fn new(default_bpm: f64) -> Result<Self> {
        if !(20.0..=300.0).contains(&default_bpm) {
            return Err(ControlError::InvalidParameter(
                "Tempo must be between 20 and 300 BPM".to_string(),
            ));
        }
        Ok(Self { _tempo: Tempo::new(default_bpm), _clock: Clock::default() })
    }

    /// Return the configured default tempo.
    pub fn tempo_bpm(&self) -> f64 {
        self._tempo.bpm()
    }

    /// Update the tempo value locally.
    pub fn set_tempo_bpm(&mut self, bpm: f64) -> Result<()> {
        if !(20.0..=300.0).contains(&bpm) {
            return Err(ControlError::InvalidParameter(
                "Tempo must be between 20 and 300 BPM".to_string(),
            ));
        }
        self._tempo = ableton_link_rs::link::tempo::Tempo::new(bpm);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ableton_link_handle_new_valid() {
        let handle = AbletonLinkHandle::new(120.0).unwrap();
        assert_eq!(handle.tempo_bpm(), 120.0);
    }

    #[test]
    fn test_ableton_link_handle_new_invalid_too_low() {
        let handle = AbletonLinkHandle::new(19.9);
        assert!(handle.is_err());
    }

    #[test]
    fn test_ableton_link_handle_new_invalid_too_high() {
        let handle = AbletonLinkHandle::new(300.1);
        assert!(handle.is_err());
    }

    #[test]
    fn test_ableton_link_handle_set_tempo_valid() {
        let mut handle = AbletonLinkHandle::new(120.0).unwrap();
        handle.set_tempo_bpm(150.0).unwrap();
        assert_eq!(handle.tempo_bpm(), 150.0);
    }

    #[test]
    fn test_ableton_link_handle_set_tempo_invalid_too_low() {
        let mut handle = AbletonLinkHandle::new(120.0).unwrap();
        let result = handle.set_tempo_bpm(19.9);
        assert!(result.is_err());
        assert_eq!(handle.tempo_bpm(), 120.0); // Should not mutate
    }

    #[test]
    fn test_ableton_link_handle_set_tempo_invalid_too_high() {
        let mut handle = AbletonLinkHandle::new(120.0).unwrap();
        let result = handle.set_tempo_bpm(300.1);
        assert!(result.is_err());
        assert_eq!(handle.tempo_bpm(), 120.0); // Should not mutate
    }
}
