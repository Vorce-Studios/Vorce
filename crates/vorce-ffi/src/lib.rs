//! Vorce FFI - Foreign Function Interface Bridge
//!
//! This crate provides FFI bindings to external SDKs including:
//! - NDI (Network Device Interface)
//! - DeckLink SDI
//! - Spout (Windows)
//! - Syphon (macOS)
//!
//! NOTE: This is a placeholder for Phase 0.
//! Full implementation will be completed in Phase 5.

use thiserror::Error;

use vorce_media::MediaError;

/// FFI errors
#[derive(Error, Debug)]
pub enum FfiError {
    #[error("NDI error: {0}")]
    /// Error: NDI error.
    NdiError(String),

    #[error("DeckLink error: {0}")]
    /// Error: DeckLink error.
    DeckLinkError(String),

    #[error("Spout error: {0}")]
    /// Error: Spout error.
    SpoutError(String),

    #[error("Syphon error: {0}")]
    /// Error: Syphon error.
    SyphonError(String),

    #[error("Media decoder error: {0}")]
    /// Error: Media decoder error.
    MediaDecoderError(String),

    #[error("Null pointer provided")]
    /// Error: Null pointer provided.
    NullPointer,

    #[error("Invalid buffer size or out of bounds")]
    /// Error: Invalid buffer size or out of bounds.
    InvalidBuffer,
}

/// FFI Error codes returned to C clients
#[repr(i32)]
#[derive(Debug, PartialEq, Eq)]
pub enum FfiResultCode {
    Ok = 0,
    NullPointer = -1,
    InvalidBuffer = -2,
    UnknownError = -99,
}

impl From<FfiError> for FfiResultCode {
    fn from(err: FfiError) -> Self {
        match err {
            FfiError::NullPointer => FfiResultCode::NullPointer,
            FfiError::InvalidBuffer => FfiResultCode::InvalidBuffer,
            _ => FfiResultCode::UnknownError,
        }
    }
}

impl From<MediaError> for FfiError {
    fn from(err: MediaError) -> Self {
        match err {
            MediaError::DecoderError(msg) => FfiError::MediaDecoderError(msg),
            _ => FfiError::MediaDecoderError(err.to_string()),
        }
    }
}

/// Result type for FFI operations
pub type Result<T> = std::result::Result<T, FfiError>;

/// C-ABI plugin interface (placeholder)
#[repr(C)]
pub struct PluginApi {
    /// Version number for API or plugin compatibility.
    pub version: u32,
}

impl Default for PluginApi {
    fn default() -> Self {
        Self::new()
    }
}

impl PluginApi {
    /// The current architectural version of the API or plugin.
    pub const VERSION: u32 = 1;

    /// Creates a new, uninitialized instance with default settings.
    pub fn new() -> Self {
        Self { version: Self::VERSION }
    }
}

/// Retrieves the plugin version. Returns an error if the handle is null.
///
/// # Safety
/// `api` and `out_version` must be valid, non-null pointers. `api` must point to a valid `PluginApi`.
#[no_mangle]
pub unsafe extern "C" fn vorce_plugin_get_version(
    api: *const PluginApi,
    out_version: *mut u32,
) -> FfiResultCode {
    if api.is_null() || out_version.is_null() {
        return FfiResultCode::NullPointer;
    }

    unsafe {
        *out_version = (*api).version;
    }

    FfiResultCode::Ok
}

/// Validates a buffer passed from C to Rust.
///
/// # Safety
/// `api` must be a valid pointer to a `PluginApi`. `buffer` must point to valid memory of at least `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn vorce_plugin_read_buffer(
    api: *const PluginApi,
    buffer: *const u8,
    len: usize,
) -> FfiResultCode {
    if api.is_null() || buffer.is_null() {
        return FfiResultCode::NullPointer;
    }

    // Example safety check: reject unrealistically huge buffers or 0 length
    if len == 0 || len > 1024 * 1024 * 100 {
        return FfiResultCode::InvalidBuffer;
    }

    // Safely construct a slice (without panicking, since bounds/null checked)
    let _slice = unsafe { std::slice::from_raw_parts(buffer, len) };

    FfiResultCode::Ok
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plugin_api() {
        let api = PluginApi::new();
        assert_eq!(api.version, PluginApi::VERSION);
    }

    #[test]
    fn test_ffi_null_handles() {
        let mut version: u32 = 0;
        let api = PluginApi::new();

        assert_eq!(
            unsafe { vorce_plugin_get_version(std::ptr::null(), &mut version) },
            FfiResultCode::NullPointer
        );

        assert_eq!(
            unsafe { vorce_plugin_get_version(&api, std::ptr::null_mut()) },
            FfiResultCode::NullPointer
        );

        let valid_buffer: [u8; 4] = [1, 2, 3, 4];
        assert_eq!(
            unsafe {
                vorce_plugin_read_buffer(
                    std::ptr::null(),
                    valid_buffer.as_ptr(),
                    valid_buffer.len(),
                )
            },
            FfiResultCode::NullPointer
        );

        assert_eq!(
            unsafe { vorce_plugin_read_buffer(&api, std::ptr::null(), valid_buffer.len()) },
            FfiResultCode::NullPointer
        );
    }

    #[test]
    fn test_ffi_invalid_buffer() {
        let api = PluginApi::new();
        let valid_buffer: [u8; 4] = [1, 2, 3, 4];

        // 0 length buffer
        assert_eq!(
            unsafe { vorce_plugin_read_buffer(&api, valid_buffer.as_ptr(), 0) },
            FfiResultCode::InvalidBuffer
        );

        // Out of bounds huge length buffer
        assert_eq!(
            unsafe { vorce_plugin_read_buffer(&api, valid_buffer.as_ptr(), 1024 * 1024 * 200) },
            FfiResultCode::InvalidBuffer
        );
    }
}
