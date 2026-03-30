# Professional Video I/O Readiness Baseline

**Status:** Current
**Last Update:** 2024-05-24

This document summarizes the actual readiness of the Professional Video I/O Features (NDI, SRT, HAP) in the `main` branch, making the gap between initial planning and actual implementation transparent.

## Goals

1.  Clear delineation of scopes.
2.  Honest classification of maturity (Disabled, Experimental, Gated, Production-Ready).
3.  Documentation of build/runtime/QA paths for QA/Devs.

## Readiness Matrix

| Feature       | Type | Status             | Gating/Reachability                                                                                                   |
| ------------- | ---- | ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **NDI Input** | In   | **[Experimental]** | Present in code (`vorce-io`). UI: Gated behind unsupported warnings.                                                  |
| **NDI Output**| Out  | **[Experimental]** | Present in code (`vorce-io`) as placeholders/sender stubs. UI: Gated behind unsupported warnings.                     |
| **SRT Stream**| Out  | **[Experimental]** | Present in code (`vorce-io`) as pure stub. UI: No representation.                                                     |
| **HAP Player**| In   | **[Experimental]** | Code in `vorce-media` has decoder present, but container-format parsing is a placeholder (FFmpeg integration missing). UI: not fully wired to playback loop. |

## Technical Details & Paths

### NDI (Network Device Interface)

*   **Build Path:** Requires the `ndi` feature in `vorce-io` and dependent crates. By default **not** enabled in the default build.
*   **Runtime Path:**
    *   Input: Uses `grafton_ndi`. Discovery potentially works, but frame polling/upload into the `vorce` texture-pool architecture is incomplete.
    *   Output: `NdiSender` exists as a placeholder.

### SRT (Secure Reliable Transport)

*   **Build Path:** Requires the `stream` feature in `vorce-io`.
*   **Runtime Path:** Pure code-stub skeleton in `crates/vorce-io/src/stream/srt.rs`. No actual buffers, no encoding link.

### HAP Codec (Hardware Accelerated Video)

*   **Build Path:** Code located in `vorce-media` (`hap_decoder.rs`, `hap_player.rs`).
*   **Runtime Path:** Decoders for Snappy and GPU upload exist. The container-parse path (.mov via FFmpeg) is a placeholder.

## Acceptance & Release

None of the mentioned features (NDI, SRT, HAP) are currently acceptance-capable as *Production-Ready*. They are clearly marked in the UI and code as *[Experimental]* or *[Gated]* to avoid production risks.
