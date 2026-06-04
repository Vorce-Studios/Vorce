# Mode-1 Control-Only Acceptance Process

## Overview
This document outlines the acceptance criteria and testing procedure for Mode-1 "Control Only" operation in Vorce.

## Scope
- Master steuert mindestens eine entfernte Vorce-Instanz reproduzierbar.
- Slave fuehrt lokale Inhalte anhand kontrollierter Commands aus.
- Fehlende Assets fuehren zu klaren Fehlern statt undefiniertem Verhalten.
- Lokale Multi-Projector-/Output-Zuordnung des Slave ist abgegrenzt und dokumentiert.

## Test Harness & Procedure
1. Setup Master Instance on main workstation.
2. Setup Slave Instance on rendering node.
3. Master executes `PlaybackStart(timeline_id, timecode)` command.
4. Verify Slave receives the command and begins rendering `timeline_id` at `timecode`.
5. Master executes `PlaybackStop()` command.
6. Verify Slave halts playback.
7. Disconnect network cable on Slave, observe timeout behavior.
8. Verify output mapping: Slave successfully addresses outputs based on local `MultiProjectorConfig` irrespective of Master state.

## Missing Asset Behavior
If an asset is missing on a Slave when playback is commanded, the Slave will halt playback for that specific timeline, log an explicit `MissingAssetError`, and report the error back to the Master via the telemetry channel. Undefined behavior is strictly avoided.

## Acceptance Status
[x] Post-1.0 de-scoped. Dies wird als minimaler Cluster-Pfad end-to-end pruefbar gemacht, jedoch explizit aus Release 1.0 herausgenommen.
