<div align="center">  
  <img src="resources/app_icons/Vorce_Logo_HQ-Full-Gray-Background-NoCorner.png" alt="Vorce Logo" width="500">  

**A High-Performance, Professional-Grade Projection Mapping Tool Built with Rust.**  

[![License](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)  
[![Rust](https://img.shields.io/badge/rust-1.94%2B-orange.svg)](https://www.rust-lang.org/)  

[![CI](https://github.com/Vorce-Studios/Vorce/actions/workflows/CICD-DevFlow_Job01_Validation.yml/badge.svg)](<https://git>  
hub.com/Vorce-Studios/Vorce/actions)  
<!-- markdownlint-disable MD013 -->  
[![Build &  
Quality](https://github.com/Vorce-Studios/Vorce/actions/workflows/CICD-DevFlow_Job01_Validation.yml/badge.svg?branch=main  
)](https://github.com/Vorce-Studios/Vorce/actions/workflows/CICD-DevFlow_Job01_Validation.yml)  
[![Security  
 Analysis](https://github.com/Vorce-Studios/Vorce/actions/workflows/CI-02_security-scan.yml/badge.svg)](<https://github.com>  
/Vorce-Studios/Vorce/actions/workflows/CI-02_security-scan.yml)  
[![Stable  
Release](https://github.com/Vorce-Studios/Vorce/actions/workflows/CICD-MainFlow_Job03_Release.yml/badge.svg)](<https://git>  
hub.com/Vorce-Studios/Vorce/actions/workflows/CICD-MainFlow_Job03_Release.yml)  
![OS: Windows | Linux](https://img.shields.io/badge/OS-Windows%20%7C%20Linux-blue.svg)  
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)  
[![Rust: 1.94+](https://img.shields.io/badge/Rust-1.94%2B-orange.svg)](https://www.rust-lang.org/)  
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)  
 <!-- markdownlint-enable MD013 -->  
</div>  

---

## 🌟 Introduction

**Vorce** is a modern, open-source projection mapping software designed for
visual artists, stage designers, and live performers. It combines the
efficiency of Rust with a powerful, real-time node-based workflow and a
highly reactive modulation system.

### ⚡ Professional Rendering Engine

Powered by **WGPU** and the **Bevy Engine**, Vorce delivers low-latency,
hardware-accelerated rendering.

* **Multi-Layer Composition**: Advanced blend modes and hierarchical grouping.
* **3D & Particle Integration**: Native Bevy support for stunning
  volumetric effects and 3D scenes.
* **LUT Color Grading**: Industry-standard `.cube` support for cinematic looks.

### 🔊 Deep Audio Reactivity

Our **AudioAnalyzer V2** tracks 9 frequency bands, RMS volume, and peak
detection in real-time, allowing visuals to dance perfectly to the beat.

### 📐 Precision Projection Mapping

* **Bezier Warping**: Flexible mesh deformation for complex surfaces.
* **Edge Blending**: Seamless multi-projector setups with per-output
  gamma correction.
* **Advanced Masking**: Integrated shape and file-based masking tools.

### 🎛️ Unified Control

Seamlessly integrate with your performance setup via **OSC**, **MIDI**, and
**Ableton Link**. Our built-in **Jules AI assistant** is always ready to help
you extend the software's capabilities.

---

## 🛠️ Technology Stack

| Component | Technology |
| :--- | :--- |
| **Core** | [Rust 🦀](https://www.rust-lang.org/) (High-performance, Thread-safe) |
| **Graphics** | [WGPU](https://wgpu.rs/) (Modern WebGPU-based hardware acceleration) |
| **3D Engine** | [Bevy](https://bevyengine.org/) (Data-driven ECS engine) |
| **Interface** | [egui](https://github.com/emilk/egui) (Blazing fast immediate mode UI) |
| **Video/Audio** | FFmpeg (via `ffmpeg-next`), CPAL (Cross-platform audio) |
| **Protocol** | [Model Context Protocol](https://modelcontextprotocol.io/) (AI integration) |

---

## 🚦 Quick Start

### 1. Requirements

* **Rust**: [Install latest stable version](https://rustup.rs/)
* **FFmpeg**: System-wide installation required for video decoding.
* **NDI (Optional)**: For network video I/O.

### 2. Run from Source

```bash
# Clone the repository
git clone https://github.com/Vorce-Studios/Vorce.git
cd Vorce

# Run the application (Release mode recommended for performance)
cargo run --release
```

### 3. Usage

* Check the [**Quick Start Guide**](docs/A4_USER/B1_MANUAL/DOC-C2_QUICKSTART.md)
  to create your first composition.
* Explore the [**User Manual**](docs/A4_USER/B1_MANUAL/DOC-C0_README.md)
  for detailed control explanations.

---

## 📚 Documentation

Explore our comprehensive guides in the [`docs/`](docs/README.md) directory:

* 📖 [**User Guide**](docs/A4_USER/B1_MANUAL/DOC-C0_README.md): Interface layout, keyboard
  shortcuts, and performance tips.
* 👨‍💻 [**Developer Portal**](docs/A2_DEVELOPMENT/DOC-B0_README.md): Architecture overview,
  coding standards, and build instructions.
* 🗺️ **Project Roadmap**: Current status and upcoming Phase 1.0 release goals are
  tracked via GitHub Project Issues.

---

## 🤝 Contributing

We welcome contributions from visual artists and developers alike! Please read
our [**Contributing Guidelines**](CONTRIBUTING.md) and check our
[**GitHub Issues**](https://github.com/Vorce-Studios/Vorce/issues) for open
tasks.

## 📄 License

Vorce is licensed under **GPL-3.0**. See the [LICENSE](LICENSE) file for more information.

---
<div align="center">
  Created with ❤️ by the Vorce Contributors.
</div>
