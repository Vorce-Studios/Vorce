## Verlinktes Issue

Fixes #105

## Goal

Ein belastbares Modell fuer Instanz-Topologie, Rollen, Session-Konfiguration und Output-Zuordnung definieren, auf dem alle Cluster-Modi aufbauen.

## Changes Made

- Added `cluster.rs` module defining data structures for `InstanceConfig`, `InstanceRole`, `OutputAssignment`, and `ClusterConfig`.
- Exposed these new types in the public API via `crates/vorce-core/src/lib.rs`.
- Integrated `ClusterConfig` into the top-level `AppState` within `crates/vorce-core/src/state.rs`.
- Made sure the new field handles serialization safely using `#[serde(default)]` and `#[serde(skip)]`.
- Followed clean code principles by relying on derived traits (e.g. `#[derive(Default)]` with `#[default]` for the enum variant).
