# DOC-C6: Cluster Topology & Instance Roles

## Overview
To support distributed rendering and Multi-PC execution, Vorce utilizes a centralized cluster topology model. This model defines which instances are active in a show, their respective roles, and how physical outputs are mapped across the network.

This document describes the foundational data structures introduced to address issue `#105`.

## Data Model

The core session and cluster definitions live in `crates/vorce-core/src/cluster.rs`.

### 1. Instance Identity
Every Vorce node running within a cluster is assigned a unique `InstanceId` (UUID). This identity separates logical output configuration from the physical machines executing the render tasks.

### 2. Instance Roles (`InstanceRole`)
To dictate control flow and synchronization, each instance assumes exactly one role during a session:

*   **`Standalone`**: Default operation mode. No network clustering is active. The local machine handles all logic, UI, and output rendering.
*   **`Master`**: The primary control node. It dictates the show state, handles project loading/saving, evaluates logic (timeline, automation), and broadcasts sync data to other nodes. Usually possesses a UI.
*   **`Slave`**: A render-only or UI-assisted node that receives state commands from the `Master`. It delegates most logic execution and focuses on rendering specific designated outputs.
*   **`HeadlessOutput`**: A streamlined variant of `Slave` running without any UI or editor components, purely dedicated to maximizing rendering performance for its assigned outputs.
*   **`MultiMasterPeer`**: (Future expansion) Used in collaborative modes where multiple machines can mutate the show state simultaneously.

### 3. Local Output Ownership
A core challenge of distributed rendering is determining *which* outputs (e.g., projectors, LED walls) are rendered by *which* physical PC.
Each `InstanceConfig` contains a `local_outputs: Vec<OutputId>` list.

This maps directly to the global `OutputManager` (from `Vorce-Studios/Vorce#33`). While the master project file contains *all* outputs, an individual instance will only invoke physical window lifecycles and render pipelines for the `OutputId`s explicitly assigned to it in its `local_outputs` list.

### 4. Cluster Session Configuration (`ClusterSessionConfig`)
The entire cluster layout is encapsulated in `ClusterSessionConfig` (stored within `AppState`).
It contains:
*   `enabled: bool` - Toggle switch for cluster logic.
*   `local_instance_id: InstanceId` - Identifier telling the current executable *which* node it represents in the cluster.
*   `instances: Vec<InstanceConfig>` - The full topology map of the show.

## Integration with AppState
The `ClusterSessionConfig` is stored in the root `AppState` as an `Arc<ClusterSessionConfig>`. This ensures it participates seamlessly in the undo/redo framework and is saved properly within the project file.

## Boundaries and Out of Scope
This data model strictly defines *topology*. The following aspects are built *on top* of this model but are tracked in separate issues:
*   Control Plane & Transport protocol implementation (`Vorce-Studios/Vorce#46`)
*   Deep physical window assignment logic (`Vorce-Studios/Vorce#47`)
