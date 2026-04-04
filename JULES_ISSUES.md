# 🎯 Optimized Jules Issue Descriptions

## Issue #129: MF-StMa_Remove-Legacy-Atty-Bincode-From-Dependency-Graph

**Priority:** High (Infrastructure/Security)
**Target:** Workspace Root, `vorce-io`, `vorce-core`

### 📝 Description (#129)

Audit and replace unmaintained or unsound dependencies across the Vorce workspace to improve security and maintainability.

### 🛠️ Tasks (#129)

- [ ] **Replace `atty`**: Replace `atty` v0.2.14 (unmaintained) with the native `std::io::IsTerminal` trait (available since Rust 1.70). This affects `env_logger` integration and any direct CLI terminal checks.
- [ ] **Consolidate `bincode`**: Currently, both v1.3.3 and v2.0.1 exist in the dependency tree.
  - v1.3.3 is unmaintained and susceptible to DoS via malicious inputs.
  - v2.0.1 is the modern version.
  - Consolidate to a single maintained version or replace with a modern alternative like `rkyv` (zero-copy) or `postcard` if the data volume is small.
- [ ] **Dependency Audit**: Run `cargo audit` and `cargo tree` to ensure no transitive dependencies are pulling in these legacy crates.

### ✅ Acceptance Criteria (#129)

- [ ] `atty` is completely removed from the dependency tree.
- [ ] Only one version of `bincode` (or a replacement) remains.
- [ ] `cargo audit` passes without warnings for these crates.

---

## Issue #130: MF-StMa_Zero-Copy-Bevy-Interop-And-Async-Texture-Uploads

**Priority:** Critical (Performance)
**Target:** `vorce-bevy`, `vorce-render`

### 📝 Description (#130)

Optimize the data path between Bevy's ECS-driven scene management and the `vorce-render` compositor. Current implementation may involve redundant copies of texture data when passing frames from Bevy to the main output pipeline.

### 🛠️ Tasks (#130)

- [ ] **Zero-Copy Interop**: Implement a shared `wgpu::Texture` or `wgpu::Buffer` handle mechanism between Bevy's render graph and Vorce's compositor to avoid `memcpy` of frame data.
- [ ] **Async Texture Uploads**: Move texture data uploads to an asynchronous staging buffer pipeline (using `wgpu`'s command buffer or a dedicated upload queue) to prevent blocking the main application loop during high-resolution media playback.
- [ ] **Profiler Integration**: Add tracing spans to measure the latency reduction in the frame handoff.

### ✅ Acceptance Criteria (#130)

- [ ] No explicit `memcpy` of raw pixel data between Bevy and Vorce-Render.
- [ ] Texture uploads do not cause frame drops on the main thread (measured via diagnostics).
- [ ] Performance improvement of >15% in high-load multi-window scenarios.

---

## Issue #131: MF-StMa_Media-Decoder-FFI-Safety-Boundary-Checks

**Priority:** High (Reliability)
**Target:** `vorce-media`

### 📝 Description (#131)

Harden the FFI boundaries in `vorce-media` when interacting with FFmpeg, libmpv, and HAP decoders. Unsafe blocks must be properly audited and wrapped in safe abstractions.

### 🛠️ Tasks (#131)

- [ ] **FFI Audit**: Review all `unsafe` blocks in `crates/vorce-media/src/decoder.rs`, `hap_decoder.rs`, and `mpv_decoder.rs`.
- [ ] **Boundary Hardening**: Implement robust bounds checks for raw pointers and ensure that any data passed from C to Rust (especially frame buffers) is properly owned or has validated lifetimes.
- [ ] **Error Handling**: Replace manual pointer checks with `Result`-based safe wrappers for FFI calls.
- [ ] **Thread Safety**: Validate that async decoder callbacks from FFmpeg/libmpv correctly interact with Rust's thread-safety guarantees (Send/Sync).

### ✅ Acceptance Criteria (#131)

- [ ] All `unsafe` blocks in `vorce-media` are documented with safety justifications.
- [ ] No raw pointer leaks or out-of-bounds access in the media pipeline.
- [ ] Decoder stability: No segmentation faults during malformed file playback tests.
