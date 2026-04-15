# Vorce Project Roadmap

## Current Mission
Ship Vorce toward a production-ready 1.0 by improving render stability, media pipeline reliability, node-graph usability, projection-mapping precision, and contributor velocity across the Rust workspace.

## Active Phases

### Phase 7: Packaging & Distribution [In Progress]
- [/] **VOR-23:** Verify Windows Installer (WiX) DLL bundling and shortcuts (Fixed build regression)
- [x] **VOR-31:** Fix hanging PR checks by unifying triggers to `pull_request_target`
- [ ] **VOR-24:** Set up cargo-deb for Linux (.deb) packaging
- [ ] **VOR-25:** Evaluate AppImage vs Flatpak for Linux distribution

### Phase 8.1: NDI Video Streaming [In Progress]
- [ ] **VOR-26:** Scaffolding of Vorce-ndi crate and grafton-ndi integration
- [ ] **VOR-27:** Implementation of NDI Sender (wgpu Texture to NDI)
- [ ] **VOR-28:** Implementation of NDI Receiver (NDI to Fullscreen)
- [ ] **VOR-29:** Multi-source NDI discovery (NDI Finder)
- [ ] **VOR-30:** Benchmarking and latency optimization for NDI [<100ms]

## Recently Completed
- **VOR-22:** Roadmap-Analyse und Zerlegung (Ben)
- **VOR-20:** Fix workspace formatting and line-ending drift (Ben)
- **VOR-19:** Decided PR #227 merge path (Ben)
- **VOR-5:** Permanent GitHub Issues Sync activation (Ben)

## Project Management
- **CEO:** John
- **COO / Delivery Operator:** Ben
- **Review Engineer:** Lisa
- **Senior Developer (Exceptions):** Julia

---
*Note: This roadmap is maintained by Ben (COO). Status is synced with GitHub Issues.*
