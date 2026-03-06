# MapFlow ROADMAP (No-Loss, MF-ID gesteuert)

Stand: 2026-03-06
Operatives Hauptdokument: `ROADMAP.md`
Sprache: Deutsch

## 1) Legende + MF-ID-Regel

- MF-ID Format: `MF-###-SLUG` (Beispiel: `MF-001-AUDIO-UI-CONSOLIDATION`)
- Pflicht: Branch und PR muessen die MF-ID im Namen tragen.
- Pflichtstatus pro Task:
  - `Dev-Status`: Entwicklungsstand im Code.
  - `QA-Status (User)`: Ergebnis deiner Testlaeufe.
- Statuswerte:
  - `Offen`
  - `In Analyse`
  - `In Umsetzung`
  - `Bereit fuer QA`
  - `Nacharbeit`
  - `Abgeschlossen`

Hinweis zu "Wird das wirklich benoetigt?":
- Keine eigene Sektion mehr.
- Abbildung nur noch ueber `Beschreibung` (Scope), Prioritaet und Status pro Task.

## 2) Aktive Blocker / Prio A-B-C

| Task-ID | Bereich | Typ | Beschreibung | Quellreferenz(en) | Dev-Status | QA-Status (User) | Branch | PR | Letztes Update |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MF-001-AUDIO-UI-CONSOLIDATION | UI/Audio | Bug | Prio A: Doppelte Audio-Analyse entfernen, Floating-Panel abbauen. | SRC-022, SRC-023, SRC-059 | In Analyse | Offen | `MF-001-audio-ui-consolidation` | - | 2026-03-06 |
| MF-002-AUDIO-PIPELINE-RECOVERY | Core/Audio | Bug | Prio A: Audioanalyse funktional wiederherstellen (Input -> Analyzer -> Evaluator -> UI). | SRC-004, SRC-024, SRC-060, SRC-061, SRC-062 | In Analyse | Offen | `MF-002-audio-pipeline-recovery` | - | 2026-03-06 |
| MF-004-CONNECTION-TYPE-SAFETY | Module Canvas | Bug | Prio A: Nur typgleiche Ein-/Ausgaenge verbindbar machen. | SRC-026, SRC-063 | In Analyse | Offen | `MF-004-connection-type-safety` | - | 2026-03-06 |
| MF-005-LAYER-MESH-EDITOR-RESTORE | Inspector/Layer | Bug | Prio A: Grafischen Mesh-Editor im Layer-Inspector sicher verfuegbar machen. | SRC-031, SRC-040 | In Analyse | Offen | `MF-005-layer-mesh-editor-restore` | - | 2026-03-06 |
| MF-007-SETTINGS-GFX-PERF-WIRING | Settings | Bug | Prio A: Grafik/Performance Controls wirksam, persistiert und runtime-wirksam machen. | SRC-027, SRC-065 | In Analyse | Offen | `MF-007-settings-gfx-perf-wiring` | - | 2026-03-06 |
| MF-008-THEME-SWITCHER-INTEGRATION | Settings/UI | Feature | Prio A: Theme-Switcher inkl. Auswahlmenue und Persistenz integrieren. | SRC-028, SRC-044, SRC-066 | In Analyse | Offen | `MF-008-theme-switcher-integration` | - | 2026-03-06 |
| MF-009-HUE-DTLS-OPENSSL-PATH | Control/Hue | Bug | Prio A: DTLS/OpenSSL Fehlerpfad beheben und stabile Hue-Connection herstellen. | SRC-009, SRC-029, SRC-033, SRC-067 | In Analyse | Offen | `MF-009-hue-dtls-openssl-path` | - | 2026-03-06 |
| MF-011-UI-PANEL-CONSISTENCY | UI Layout | Bug | Prio A: Fehlende/falsch platzierte Panels und Funktionsluecken konsistent machen. | SRC-043, SRC-069 | In Analyse | Offen | `MF-011-ui-panel-consistency` | - | 2026-03-06 |
| MF-014-AUTOSAVE-COMPAT | Core/IO | Bug | Prio B: Autosave-Backward-Kompatibilitaet (`master_blackout`) absichern. | SRC-071 | In Analyse | Offen | `MF-014-autosave-compat` | - | 2026-03-06 |
| MF-015-TRACE-CHAIN-HARDENING | Core/Evaluator | Bug | Prio B: `trace_chain` Warnungen reduzieren, Kettenvalidierung verbessern. | SRC-072 | In Analyse | Offen | `MF-015-trace-chain-hardening` | - | 2026-03-06 |
| MF-019-SPOUT-WGPU-UPDATE | Engine | Refactor | Prio B: Spout auf aktuelle wgpu-Version anheben. | SRC-010 | Offen | Offen | `MF-019-spout-wgpu-update` | - | 2026-03-06 |
| MF-020-TIMELINE-KEYFRAME-INTERACTION | UI/Core | Bug | Prio B: Keyframes im Timeline-UI verschieben/loeschen wiederherstellen. | SRC-011 | Offen | Offen | `MF-020-timeline-keyframe-interaction` | - | 2026-03-06 |

## 3) Umsetzungs-Backlog

| Task-ID | Bereich | Typ | Beschreibung | Quellreferenz(en) | Dev-Status | QA-Status (User) | Branch | PR | Letztes Update |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MF-003-INSPECTOR-PREVIEW-ALL-NODES | Inspector | Feature | Optionale Vorschau fuer alle Node-Typen im Inspector. | SRC-025 | Offen | Offen | `MF-003-inspector-preview-all-nodes` | - | 2026-03-06 |
| MF-006-TRIGGER-FEEDBACK-RESTORE | Module Canvas | Bug | Trigger-Feedback visuell wieder belastbar machen. | SRC-041, SRC-064 | In Analyse | Offen | `MF-006-trigger-feedback-restore` | - | 2026-03-06 |
| MF-010-HUE-CONFIG-REUSE | Control/Hue | Bug | Gespeicherte Bridge-Daten robust nutzen (Init + Reconnect + Actions). | SRC-030, SRC-068 | In Analyse | Offen | `MF-010-hue-config-reuse` | - | 2026-03-06 |
| MF-012-ANALOG-METER-OPTION | Audio/UI | Feature | Analoges Level-Meter als waehlbare Option reaktivieren. | SRC-042, SRC-070 | In Analyse | Offen | `MF-012-analog-meter-option` | - | 2026-03-06 |
| MF-013-FFMPEG-BUILDMODE-CLARITY | Media/Build | Bug | FFmpeg-Buildmodus und Fallback-Verhalten eindeutig und testbar machen. | SRC-070 | In Analyse | Offen | `MF-013-ffmpeg-buildmode-clarity` | - | 2026-03-06 |
| MF-016-FEATURE-STATUS-BASELINE | Docs/QA | Feature | Vollstaendige Feature-Status-Uebersicht mit Dev- und User-QA-Status. | SRC-032, SRC-035, SRC-036, SRC-037 | In Umsetzung | Offen | `MF-016-feature-status-baseline` | - | 2026-03-06 |
| MF-017-TEST-MATRIX-ROLL-OUT | QA/Process | Feature | Feste, gruppierte Testmatrix fuer Regression und Freigaben. | SRC-038, SRC-039 | In Umsetzung | Offen | `MF-017-test-matrix-rollout` | - | 2026-03-06 |
| MF-018-SCOPE-PRIORITY-GOVERNANCE | Process | Refactor | Scope-Steuerung statt eigener "Wird das benoetigt?"-Sektion. | SRC-034 | In Umsetzung | Offen | `MF-018-scope-priority-governance` | - | 2026-03-06 |
| MF-021-NDI-DISCOVERY-UI | UI | Feature | NDI-Discovery im Sidebar-Flow integrieren. | SRC-013 | Offen | Offen | `MF-021-ndi-discovery-ui` | - | 2026-03-06 |
| MF-022-SHADER-GRAPH-EXPANSION | Core/UI | Feature | Shader-Graph um weitere Node-Typen erweitern. | SRC-014 | Offen | Offen | `MF-022-shader-graph-expansion` | - | 2026-03-06 |
| MF-023-ERROR-TOAST-NOTIFICATIONS | UI/Core | Feature | Engine-Fehler als Toast-Notifications sichtbar machen. | SRC-016 | Offen | Offen | `MF-023-error-toast-notifications` | - | 2026-03-06 |
| MF-024-HOLD-TO-CONFIRM-UX | UX/Security | Bug | "Hold-to-Confirm" stabilisieren und CI-Failure aufloesen. | SRC-018 | In Analyse | Offen | `MF-024-hold-to-confirm-ux` | #937 | 2026-03-06 |
| MF-025-ROADMAP-GITHUB-SYNC-GATE | Process | Feature | Roadmap-Status nur mit PR/CI-Gate fortschreiben. | SRC-047, SRC-049, SRC-057 | In Umsetzung | Offen | `MF-025-roadmap-github-sync-gate` | - | 2026-03-06 |
| MF-026-TASKID-DISPATCH-AUTO-PR | Process | Feature | Task-ID-only Delegation + AUTO_CREATE_PR als Standardprozess. | SRC-045, SRC-046, SRC-050, SRC-051, SRC-052, SRC-053, SRC-058 | In Umsetzung | Offen | `MF-026-taskid-dispatch-auto-pr` | - | 2026-03-06 |
| MF-027-STATUS-WORKFLOW-STANDARD | Process | Feature | Statusfluss Jules -> Review -> Abnahme -> Abgeschlossen vereinheitlichen. | SRC-054, SRC-055, SRC-056 | In Umsetzung | Offen | `MF-027-status-workflow-standard` | - | 2026-03-06 |
| MF-028-MF-ID-NAMING-COMPLIANCE | Process | Feature | MF-ID Naming Pflicht fuer Branch/PR durchsetzen. | SRC-048 | In Umsetzung | Offen | `MF-028-mf-id-naming-compliance` | - | 2026-03-06 |

## 4) Abnahme-Queue

| Task-ID | Bereich | Typ | Beschreibung | Quellreferenz(en) | Dev-Status | QA-Status (User) | Branch | PR | Letztes Update |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MF-040-SECURITY-934-VALIDATION | Security | Fix | Historischer Security-Fix, finale User-Abnahme dokumentieren. | SRC-017 | Bereit fuer QA | Offen | `MF-040-security-934-validation` | #934 | 2026-03-06 |
| MF-041-CORE-TESTS-933 | Core | Test | Historischer Core-Test-Fix, Regressionstest nachziehen. | SRC-019 | Bereit fuer QA | Offen | `MF-041-core-tests-933` | #933 | 2026-03-06 |
| MF-042-PERF-935 | Core/Perf | Refactor | Historische Performance-Optimierung gegen aktuelle Basis pruefen. | SRC-020 | Bereit fuer QA | Offen | `MF-042-perf-935` | #935 | 2026-03-06 |
| MF-043-UI-POLISH-936 | UI | Polish | Historischer UI-Polish gegen aktuelle Panel-Realitaet gegenpruefen. | SRC-021 | Bereit fuer QA | Offen | `MF-043-ui-polish-936` | #936 | 2026-03-06 |

## 5) Erledigt-Archiv

| Task-ID | Bereich | Typ | Beschreibung | Quellreferenz(en) | Dev-Status | QA-Status (User) | Branch | PR | Letztes Update |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MF-029-ARCHIVE-RESCUE-DELIVERABLES | Legacy/Rescue | Sammelpunkt | Historisch als erledigt markierte Rescue-Lieferungen (technisch erneut validieren ueber MF-016/MF-017). | SRC-001, SRC-002, SRC-003, SRC-005, SRC-006, SRC-007, SRC-008, SRC-012, SRC-015 | Abgeschlossen | Offen | - | - | 2026-03-06 |

## 6) Migrations-Mapping (No-Loss-Tabelle)

| Quellpunkt | Quelle | Neue MF-Task-ID | Status | Hinweis |
| --- | --- | --- | --- | --- |
| SRC-001 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-002 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-003 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-004 | ROADMAP_alt | MF-002-AUDIO-PIPELINE-RECOVERY | Gemappt | Regression gegen Alt-Status |
| SRC-005 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-006 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-007 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-008 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-009 | ROADMAP_alt | MF-009-HUE-DTLS-OPENSSL-PATH | Gemappt | Offener Blocker |
| SRC-010 | ROADMAP_alt | MF-019-SPOUT-WGPU-UPDATE | Gemappt | Offener Blocker |
| SRC-011 | ROADMAP_alt | MF-020-TIMELINE-KEYFRAME-INTERACTION | Gemappt | Offener Blocker |
| SRC-012 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-013 | ROADMAP_alt | MF-021-NDI-DISCOVERY-UI | Gemappt | Geplant |
| SRC-014 | ROADMAP_alt | MF-022-SHADER-GRAPH-EXPANSION | Gemappt | Geplant |
| SRC-015 | ROADMAP_alt | MF-029-ARCHIVE-RESCUE-DELIVERABLES | Gemappt | Historisch erledigt |
| SRC-016 | ROADMAP_alt | MF-023-ERROR-TOAST-NOTIFICATIONS | Gemappt | Offen |
| SRC-017 | ROADMAP_alt | MF-040-SECURITY-934-VALIDATION | Gemappt | Abnahme notwendig |
| SRC-018 | ROADMAP_alt | MF-024-HOLD-TO-CONFIRM-UX | Gemappt | CI-Failure offen |
| SRC-019 | ROADMAP_alt | MF-041-CORE-TESTS-933 | Gemappt | Abnahme notwendig |
| SRC-020 | ROADMAP_alt | MF-042-PERF-935 | Gemappt | Abnahme notwendig |
| SRC-021 | ROADMAP_alt | MF-043-UI-POLISH-936 | Gemappt | Abnahme notwendig |
| SRC-022 | User_2026-03-06 | MF-001-AUDIO-UI-CONSOLIDATION | Gemappt | Doppelte Anzeige |
| SRC-023 | User_2026-03-06 | MF-001-AUDIO-UI-CONSOLIDATION | Gemappt | Floating-Panel entfernen |
| SRC-024 | User_2026-03-06 | MF-002-AUDIO-PIPELINE-RECOVERY | Gemappt | Funktion fehlt |
| SRC-025 | User_2026-03-06 | MF-003-INSPECTOR-PREVIEW-ALL-NODES | Gemappt | Featureanforderung |
| SRC-026 | User_2026-03-06 | MF-004-CONNECTION-TYPE-SAFETY | Gemappt | Typsicherheit |
| SRC-027 | User_2026-03-06 | MF-007-SETTINGS-GFX-PERF-WIRING | Gemappt | Settings unwirksam |
| SRC-028 | User_2026-03-06 | MF-008-THEME-SWITCHER-INTEGRATION | Gemappt | Theme-Menue fehlt |
| SRC-029 | User_2026-03-06 | MF-009-HUE-DTLS-OPENSSL-PATH | Gemappt | Fehlermeldung fixen |
| SRC-030 | User_2026-03-06 | MF-010-HUE-CONFIG-REUSE | Gemappt | Persistente Bridge-Daten |
| SRC-031 | User_2026-03-06 | MF-005-LAYER-MESH-EDITOR-RESTORE | Gemappt | Inspector-Layer |
| SRC-032 | User_2026-03-06 | MF-016-FEATURE-STATUS-BASELINE | Gemappt | Doppelstatus Pflicht |
| SRC-033 | User_2026-03-06 | MF-009-HUE-DTLS-OPENSSL-PATH | Gemappt | Fehler erneut genannt |
| SRC-034 | User_2026-03-06 | MF-018-SCOPE-PRIORITY-GOVERNANCE | Gemappt | Sektion entfernt, Scope-Feld |
| SRC-035 | User_2026-03-06 | MF-016-FEATURE-STATUS-BASELINE | Gemappt | Unvollstaendige Uebersicht |
| SRC-036 | User_2026-03-06 | MF-016-FEATURE-STATUS-BASELINE | Gemappt | Falsche Haken |
| SRC-037 | User_2026-03-06 | MF-016-FEATURE-STATUS-BASELINE | Gemappt | Vollstaendige Featureliste |
| SRC-038 | User_2026-03-06 | MF-017-TEST-MATRIX-ROLL-OUT | Gemappt | Logische Gruppierung |
| SRC-039 | User_2026-03-06 | MF-017-TEST-MATRIX-ROLL-OUT | Gemappt | Festes Pruefszenario |
| SRC-040 | User_2026-03-06 | MF-005-LAYER-MESH-EDITOR-RESTORE | Gemappt | Duplikat als Referenz erhalten |
| SRC-041 | User_2026-03-06 | MF-006-TRIGGER-FEEDBACK-RESTORE | Gemappt | Trigger-Feedback fehlt |
| SRC-042 | User_2026-03-06 | MF-012-ANALOG-METER-OPTION | Gemappt | Analog-Meter fehlt |
| SRC-043 | User_2026-03-06 | MF-011-UI-PANEL-CONSISTENCY | Gemappt | Panel-Probleme |
| SRC-044 | User_2026-03-06 | MF-008-THEME-SWITCHER-INTEGRATION | Gemappt | Theme-Umschaltung fehlt |
| SRC-045 | walkthrough.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | Task-ID Delegation |
| SRC-046 | walkthrough.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | AUTO_CREATE_PR Pflicht |
| SRC-047 | walkthrough.md | MF-025-ROADMAP-GITHUB-SYNC-GATE | Gemappt | Roadmap/GitHub Sync |
| SRC-048 | walkthrough.md | MF-028-MF-ID-NAMING-COMPLIANCE | Gemappt | Branch/PR Prefix |
| SRC-049 | walkthrough.md | MF-025-ROADMAP-GITHUB-SYNC-GATE | Gemappt | PR-Gate vor Abnahme |
| SRC-050 | walkthrough.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | Architektur-Tagging |
| SRC-051 | roadmap_proposal.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | TASK_ID Auswahl |
| SRC-052 | roadmap_proposal.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | Context-Lookup |
| SRC-053 | roadmap_proposal.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | Jules Startmodus |
| SRC-054 | roadmap_proposal.md | MF-027-STATUS-WORKFLOW-STANDARD | Gemappt | Statusfluss |
| SRC-055 | roadmap_proposal.md | MF-027-STATUS-WORKFLOW-STANDARD | Gemappt | Roadmap-Schema |
| SRC-056 | roadmap_proposal.md | MF-027-STATUS-WORKFLOW-STANDARD | Gemappt | Statusschluessel |
| SRC-057 | roadmap_proposal.md | MF-025-ROADMAP-GITHUB-SYNC-GATE | Gemappt | Historien-Log |
| SRC-058 | roadmap_proposal.md | MF-026-TASKID-DISPATCH-AUTO-PR | Gemappt | Token-Effizienz |
| SRC-059 | Codeanalyse_2026-03-06 | MF-001-AUDIO-UI-CONSOLIDATION | Gemappt | Doppelte Renderpfade |
| SRC-060 | Codeanalyse_2026-03-06 | MF-002-AUDIO-PIPELINE-RECOVERY | Gemappt | Fehlende Action-Handler |
| SRC-061 | Codeanalyse_2026-03-06 | MF-002-AUDIO-PIPELINE-RECOVERY | Gemappt | Backend nicht verdrahtet |
| SRC-062 | Codeanalyse_2026-03-06 | MF-002-AUDIO-PIPELINE-RECOVERY | Gemappt | Evaluator Audio-Update fehlt |
| SRC-063 | Codeanalyse_2026-03-06 | MF-004-CONNECTION-TYPE-SAFETY | Gemappt | Drop ohne Typ-Check |
| SRC-064 | Codeanalyse_2026-03-06 | MF-006-TRIGGER-FEEDBACK-RESTORE | Gemappt | Trigger-Werte nicht befuellt |
| SRC-065 | Codeanalyse_2026-03-06 | MF-007-SETTINGS-GFX-PERF-WIRING | Gemappt | Dummy-Settings |
| SRC-066 | Codeanalyse_2026-03-06 | MF-008-THEME-SWITCHER-INTEGRATION | Gemappt | Theme-System unverdrahtet |
| SRC-067 | Codeanalyse_2026-03-06 | MF-009-HUE-DTLS-OPENSSL-PATH | Gemappt | DTLS Stub |
| SRC-068 | Codeanalyse_2026-03-06 | MF-010-HUE-CONFIG-REUSE | Gemappt | Config-Ladepfad vorhanden, haerten |
| SRC-069 | Codeanalyse_2026-03-06 | MF-011-UI-PANEL-CONSISTENCY | Gemappt | Panel-Flags inkonsistent |
| SRC-070 | Loganalyse_2026-03-06 | MF-013-FFMPEG-BUILDMODE-CLARITY | Gemappt | FFmpeg Warnungen |
| SRC-071 | Loganalyse_2026-03-06 | MF-014-AUTOSAVE-COMPAT | Gemappt | `master_blackout` fehlend |
| SRC-072 | Loganalyse_2026-03-06 | MF-015-TRACE-CHAIN-HARDENING | Gemappt | `trace_chain` Warnungen |

## 7) Vollstaendigkeitscheck (Pflicht)

| Pruefung | Ergebnis |
| --- | --- |
| Anzahl Quellpunkte | 72 |
| Anzahl gemappter Punkte | 72 |
| Zeilen ohne MF-ID | 0 |
| MF-ID ohne Quellpunkt | 0 |
| Verlustfreie Deduplizierung | Erfuellt (Duplikate als eigene SRC-Zeilen erhalten) |

