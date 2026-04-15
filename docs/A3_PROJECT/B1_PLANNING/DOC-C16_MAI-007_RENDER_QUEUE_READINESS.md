# DOC-C16: MAI-007 Render-Queue-Readiness, Parity & Optimization

## 1. Ziel

Dieses Dokument definiert den Scope, die Feature-Parität und die Baseline für die Render-Queue-Readiness (MAI-007). Es trennt klar zwischen Runtime-Render-Parität, Hot-Path-Optimierung, Release-/Interop-Baselines und Output-Verträgen.

## 2. Scope-Trennung und Unterteilung

Um Überlappungen zu vermeiden, ist die Arbeit in folgende disjunkte Bereiche (Sub-Issues) unterteilt:

### 2.1 Render-Parität (Feature-Parität)
- **SI-04_MAI-007**: Render-Queue Preview-Path Unification. Sauberer Vertrag zwischen Output-Rendering und Preview-Rendering.
- **SI-05_MAI-007**: Runtime-Render-Queue Feature-Parity. Parität zwischen Evaluator, Render-Loops und dem sichtbaren UI-Gating.
- **SI-06_MAI-007**: Schema-Driven Inspector Completion.

### 2.2 Hot-Path-Optimierung
- **SI-02_MAI-007**: Render Hot-Path GPU Resource Reuse.
- **SI-03_MAI-007**: Render-Queue Clone- and Allocation-Optimization. Fokus auf GPU-Ressourcen im aktiven Renderpfad.

### 2.3 Release- und Interop-Baselines (Readiness)
- **SI-01_MAI-007**: Professional Video I/O Readiness Baseline. Pro-Video-I/O-Readiness für NDI, SRT und HAP, isoliert für den aktuellen Render- und Delivery-Pfad.
- **SI-07_MAI-007**: Visual Capture Release Smoke Baseline. Definiert den heutigen Screenshot-/Harness-Pfad.

## 3. Explicitly Not in Scope
Folgende Themen sind bewusst ausgeklammert, da sie nicht den direkten Render-Queue-Bezug haben:
- Allgemeine Node-Migration (Vorce#61)
- Multi-Projector-Ownership, Cluster-Control oder Transport-Topologie (Vorce#33, Vorce#17)
- Large-File-Refactorings (Vorce#54)
