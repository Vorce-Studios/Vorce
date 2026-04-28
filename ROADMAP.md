# Vorce Project Roadmap

## Current Mission
Ship Vorce toward a production-ready 1.0 by improving render stability, media pipeline reliability, node-graph usability, projection-mapping precision, and contributor velocity across the Rust workspace.

## Active Phases

### Phase 7: Packaging & Distribution [In Progress]
- [x] **VOR-23:** Verify Windows Installer (WiX) DLL bundling and shortcuts (Added NDI Player shortcut)
- [x] **VOR-24:** Set up cargo-deb for Linux (.deb) packaging (Ben)
- [x] **VOR-25:** Evaluate AppImage vs Flatpak for Linux distribution (Ben - Recommended: AppImage)

### Phase 8.1: NDI Video Streaming [Delivered — code on main]

- [x] **VOR-26:** Scaffolding of Vorce-ndi crate and grafton-ndi integration
- [x] **VOR-27:** Implementation of NDI Sender (wgpu Texture to NDI) (code merged to main via cleanup wave; PR #307 closed unmerged)
- [x] **VOR-28:** Implementation of NDI Receiver (NDI to Fullscreen) (code merged to main via cleanup wave; PR #307 closed unmerged)
- [x] **VOR-29:** Multi-source NDI discovery (NDI Finder) (code merged to main via cleanup wave; PR #307 closed unmerged)
- [x] **VOR-30:** Benchmarking and latency optimization for NDI [<100ms] (PR #336, #339)
- [x] **VOR-32:** Ben: Drive Phase 8.1 NDI Delivery (code on main; PR #307 closed unmerged)

### Phase 9: Repository Health & CI Stabilization [In Progress]
- [x] **VOR-33:** Consolidated 14 pending PRs into unified integration branch
- [x] **VOR-34:** Resolved complex merge conflicts in AssetManager and Outputs
- [x] **VOR-35:** Re-applied Path Traversal security fixes (PR #331)
- [x] **VOR-36:** Hardened FFI against DoS by removing unsafe unwraps (PR #333)
- [x] **VOR-37:** Resolved merge conflicts and NDI build errors in PR #343 and #345
- [x] **VOR-38:** Fixed startup crash caused by redundant AtmospherePlugin in Bevy integration
- [x] **VOR-40:** Resolved critical repository merge blockers, fixed Bevy compatibility, and restored NDI build health (Antigravity)

## Recently Completed
- **VOR-39:** Merged 9 Dependabot PRs (#374-#382) and resolved CI validation blockers (Antigravity)
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
