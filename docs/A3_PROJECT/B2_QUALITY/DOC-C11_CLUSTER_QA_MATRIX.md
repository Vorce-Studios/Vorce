# Cluster QA & Recovery Matrix (Release 1.0)

## Overview
This document defines the QA matrix for Cluster/Multi-Instance setups for Release 1.0. It clearly outlines recovery scenarios, partial failures, reconnect behaviors, and drift management to ensure stable operations or explicit Post-1.0 demarcations.

## 1. QA Matrix: Single-Master / Control-Only
| Feature | Supported in 1.0 | Test Method | Expected Behavior |
| :--- | :---: | :--- | :--- |
| **Single-Master Control** | Yes | Manual / Integration | A single master node can orchestrate playback without distributed rendering conflicts. |
| **Multi-Master Control** | No (Post-1.0) | N/A | Excluded from 1.0 scope to prevent split-brain scenarios. |
| **Control-Only Node** | Yes | Manual | A UI-only instance can connect to a master rendering node and adjust parameters. |

## 2. Failure Scenarios (Reconnect, Timeout, Partial Failure)
| Scenario | Detection Time | Action / Recovery | Impact |
| :--- | :---: | :--- | :--- |
| **Node Disconnect (Network)** | < 2s | Node automatically enters `ORPHANED` state. Master flags node offline. | Playback continues on other nodes. Orphaned node halts or loops safely. |
| **Node Reconnect** | - | Node authenticates, requests current timeline cursor. | Playback resumes in sync after a brief resync buffering phase. |
| **Master Timeout/Crash** | < 5s | All nodes detect heartbeat loss. Enter `SAFE_MODE`. | Cluster stops playback. Manual or external automated restart required (Post-1.0: Leader election). |
| **Partial Asset Missing** | Pre-Flight | Master prevents playback start. UI warns user. | Zero runtime impact, caught during initialization. |

## 3. Drift & Timebase Management
| Drift Type | Acceptable Range | Test/Harness | Mitigation |
| :--- | :---: | :--- | :--- |
| **Audio/Video Sync Drift** | < 1 frame (16ms) | `test_av_sync_drift` (Automated) | Periodic NTP/PTP-based cursor corrections. |
| **Multi-Node Render Drift** | < 2 frames (33ms) | High-Speed Camera (Manual Sign-off) | Master broadcasts frame-sync pulses. |

*Note: Any drift risks exceeding these limits are documented as Known Issues in #653.*

## 4. Smoke Path: Local Multi-Projector Output
If the 1.0 scope requires local multi-projector validation without a network cluster:
- **Scenario:** Single PC outputting to 3+ display outputs via extended desktop or GPU mosaic.
- **Validation:** Ensure smooth tearing-free output across all local outputs.
- **Dependency:** Avoids network drift entirely, serving as the baseline smoke test for spatial mapping before testing network clusters.

## References
- Parent Issue: #654
- Known Issues: #653
- Historical Context: #108, #46, #106
