use vorce_ffi::FfiError;
use vorce_media::MediaError;

#[test]
fn test_media_error_to_ffi_error() {
    let media_err = MediaError::DecoderError("Failed to decode frame".to_string());

    // Testing the From trait implementation
    let ffi_err: FfiError = media_err.into();

    assert!(matches!(ffi_err, FfiError::MediaDecoderError(_)));
    if let FfiError::MediaDecoderError(msg) = ffi_err {
        assert_eq!(msg, "Failed to decode frame");
    }
}
