# Linux Packaging Evaluation: AppImage vs Flatpak

## Overview

For Vorce, a high-performance VJ tool, the choice of Linux distribution format is critical to ensure low-latency rendering, easy dependency management, and broad compatibility.

## Comparison

| Feature | AppImage | Flatpak |
| :--- | :--- | :--- |
| **User Experience** | Download and run. No installation required. | Requires Flatpak runtime. Good integration with software centers. |
| **Dependencies** | Bundles all dependencies (libc versioning can be an issue). | Uses shared runtimes (e.g., Freedesktop). Easy FFmpeg management. |
| **Performance** | Native execution. No sandboxing overhead. | Sandboxed (minimal but non-zero overhead). |
| **Graphics Access** | Native access to Vulkan/OpenGL drivers. | Handled via Portal/DRM (usually works well with WGPU). |
| **Updates** | Manual or via external tools (AppImageUpdate). | Automatic via Flatpak/Flathub. |
| **Size** | Larger (bundled dependencies). | Smaller (shared runtimes). |

## Recommendation for Vorce

### Short-term: AppImage

AppImage is recommended for the initial beta releases because:

1. It is the easiest "zero-install" path for users.
2. It allows us to bundle specific FFmpeg versions without relying on system or Flatpak runtimes.
3. Performance is prioritized.

### Long-term: Flatpak (Flathub)

Flatpak is recommended for official stable distribution because:

1. It provides a more integrated "store" experience.
2. Sandboxing offers security benefits.
3. The Freedesktop runtime provides high-quality media libraries.

## Implementation Plan

1. **Phase 1: .deb (cargo-deb)**: (In Progress) Initial support for Debian/Ubuntu via traditional packaging.
2. **Phase 2: AppImage**: Implement using `cargo-appimage` or a custom script bundling the `target/release/Vorce` binary and assets.
3. **Phase 3: Flatpak**: Create a manifest for Flathub.
