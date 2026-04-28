# VOR-25: Linux Distribution Format Evaluation

## Objective
Evaluate **AppImage** vs **Flatpak** for the distribution of Vorce on Linux, focusing on performance, latency, hardware access (GPU/NDI/Audio), and ease of maintenance.

## Comparison

| Feature | AppImage | Flatpak |
| :--- | :--- | :--- |
| **Runtime Latency** | **Native Performance.** No sandboxing overhead. | **Very Low.** Minimal overhead from `bubblewrap` isolation. |
| **Hardware Access** | **Direct.** Accesses GPU (Mesa/Vulkan) and Audio (PipeWire/ALSA) directly. | **Sandboxed.** Requires explicit permissions (`--device=dri`, etc.). |
| **Dependencies** | Requires careful bundling of all libs (FFmpeg, etc.). | Uses stable Runtimes (Freedesktop SDK). |
| **Distribution** | Portable single binary. No installation required. | Requires Flatpak daemon and installation. |
| **User Experience** | Download and run. Familiar for "portable" apps. | Integrated app-store experience (Flathub). |

## Analysis for Vorce
Vorce is a high-performance multimedia application (Projection Mapping). The following factors are critical:

1.  **Low Latency:** Projection mapping requires frame-perfect synchronization. Any overhead from syscall filtering or sandboxing is a risk.
2.  **Hardware Interaction:** Vorce relies heavily on `wgpu` (Vulkan/OpenGL) and high-bandwidth IO (NDI, Video Decoders). AppImage provides the path of least resistance for direct hardware interaction.
3.  **Portability:** Professional VJ setups often use specialized, lean Linux distributions. AppImage's "single file" nature makes it easy to deploy on air-gapped or restricted systems without installing a package manager like Flatpak.

## Recommendation: AppImage
**AppImage** is the recommended format for Vorce's professional/high-performance use cases.

### Implementation Strategy (Future)
1.  Utilize `appimage-builder` or a custom script in CI.
2.  Bundle FFmpeg and other core libraries identified in the `.deb` packaging process.
3.  Integration with the existing `CICD-MainFlow_Job03_Release.yml`.

---
*Evaluated by Ben (COO) - April 2026*
