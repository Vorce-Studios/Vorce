# Bevy and Vorce Interoperability Strategy

## Status
Accepted

## Context
Vorce is integrating Bevy as its 3D rendering engine. Currently, the interoperability between Bevy and the main Vorce render pipeline involves a mandatory GPU -> CPU -> GPU roundtrip:
1. Bevy renders to a texture.
2. `frame_readback_system` blocks (`wgpu::PollType::Wait`) and copies the texture data from the GPU to the CPU (`last_frame_data`).
3. Vorce's main render loop fetches this data and uploads it back to the GPU using `queue.write_texture()`.

This causes significant CPU stalls and memory copying overhead every frame.

## Considered Options
1. **Direct Texture Sharing (Zero-Copy):** Share the `wgpu::Device` and texture memory directly between Bevy and Vorce. This is the optimal solution but requires complex synchronization and potentially significant refactoring to ensure both systems share the exact same `wgpu` instance and lifecycle, which is currently tracked in issue #128.
2. **Asynchronous Readback & Upload (Staged Uploads):** Instead of blocking the CPU waiting for the GPU readback, we can allow the readback to complete asynchronously. Once the data is on the CPU, we use a staging buffer (`WgpuFrameUploader`) to upload it back to the GPU without blocking the main render thread.

## Decision
We will proceed with a two-phased approach:
*   **Phase 1 (Immediate): Asynchronous Uploads.** We will implement Option 2 to immediately alleviate the most severe CPU stalls caused by synchronous `queue.write_texture()` calls. We will utilize the existing `WgpuFrameUploader` and ensure it's used consistently across the render path (Bevy handoff, paint cache, etc.). This provides a tangible performance improvement while we address #128.
*   **Phase 2 (Future): Zero-Copy.** We explicitly acknowledge that true zero-copy (Option 1) depends on aligning the `wgpu` instances between Bevy and Vorce (Issue #128). Once #128 is resolved, we will revisit this ADR to implement direct texture sharing, eliminating the CPU roundtrip entirely.

## Consequences
*   **Positive:** Immediate reduction in frame-time spikes and CPU stalls due to asynchronous uploads. More consistent frame rates.
*   **Negative:** We still incur the memory copy overhead (GPU->CPU->GPU) until Phase 2 is implemented. The architecture remains slightly more complex until true zero-copy is achieved.
