# subi-core

**SubI Core Domain Model and Business Logic.**

`subi-core` is the heart of SubI, containing the fundamental data structures, state management, and business logic that drives the application.
It is designed to be renderer-agnostic and UI-agnostic.

## Features

- **Project Model:** Defines the `Project` structure and hierarchy (Paint, Mapping, Mesh).
- **Layer System:** Manages composition, blending, and transformations of visual layers.
- **State Management:** Centralized `AppState` for application-wide consistency.
- **Audio Analysis:** Real-time audio analysis (FFT, Beat Detection) via `AudioAnalyzerV2`.
- **Effect Pipeline:** Definitions for effects, chains, and shader graphs.
- **Geometry:** Mesh generation, Bezier warping, and keystone correction logic.
- **Control Integration:** Abstractions for MIDI, OSC, and automation binding.

## Modules

- **`layer`**: Layer composition, blend modes, and transform logic.
- **`mapping`**: Project mapping hierarchy management.
- **`mesh`**: Geometry definitions (Vertex, Quad, BezierPatch).
- **`audio`**: Audio analysis and reactive systems.
- **`state`**: Global application state container.
- **`shader_graph`**: Node-based shader generation system.

## Usage

This crate is primarily used by `subi` (the application binary) and `subi-ui` (for data visualization).

```rust
use subi_core::Project;

let project = Project::new("My Mapping Show");
// Configure project...
```
