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
        Ok(Self {
            _tempo: Tempo::new(default_bpm),
            _clock: Clock::default(),
        })
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
        self._tempo.value = bpm;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_valid_tempo() {
        let handle = AbletonLinkHandle::new(120.0);
        assert!(handle.is_ok());
        let handle = handle.unwrap();
        assert_eq!(handle.tempo_bpm(), 120.0);
    }

    #[test]
    fn test_new_invalid_tempo_low() {
        let handle = AbletonLinkHandle::new(19.9);
        assert!(handle.is_err());
        match handle {
            Err(e) => match e {
                ControlError::InvalidParameter(msg) => {
                    assert_eq!(msg, "Tempo must be between 20 and 300 BPM");
                }
                _ => panic!("Expected InvalidParameter error"),
            },
            Ok(_) => panic!("Expected error"),
        }
    }

    #[test]
    fn test_new_invalid_tempo_high() {
        let handle = AbletonLinkHandle::new(300.1);
        assert!(handle.is_err());
        match handle {
            Err(e) => match e {
                ControlError::InvalidParameter(msg) => {
                    assert_eq!(msg, "Tempo must be between 20 and 300 BPM");
                }
                _ => panic!("Expected InvalidParameter error"),
            },
            Ok(_) => panic!("Expected error"),
        }
    }
}
