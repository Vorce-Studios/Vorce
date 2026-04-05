# Vorce-Studios Paperclip Control Plane

Dieses Verzeichnis enthaelt die versionierten Policies, Instruktionen und
Bootstrap-Artefakte fuer die lokale Paperclip-Company `Vorce-Studios`.

## Ziel

`Vorce-Studios` ist die manuell startbare lokale Control Plane fuer `Vorce`.
Sie plant zuerst, priorisiert GitHub-Issues, routed Arbeit dynamisch an den
aktuellen Tool-Pool und spiegelt die wichtigen Orchestrierungsdaten wieder
nach GitHub.

## Firmen-Mission

> Vorce als zuverlaessige, performante VJ-Software an die Community ausliefern.

## Strategische Ziele

- **G1 Stabilitaet und Qualitaet** (critical) — Bugs fixen, Tests, CI/CD
- **G2 Feature-Completion v1.0** (high) — Audio, Render, Media, UI
- **G3 Developer Experience** (medium) — Build-Zeiten, Docs, Onboarding
- **G4 Community und Release** (medium) — Release-Pipeline, Changelog, Feedback

## Kernpunkte

- GitHub bleibt der fachliche Source-of-Truth
- Paperclip steuert Agenten, Queue, Approval-Flows und Laufzeit
- `paperclip-plugin-github-issues` sorgt fuer bidirektionale Issue-Verlinkung
- Project-V2-Sync zielt auf `Vorce-Studios#1` / `@Vorce Project Manager`
- `paperclip-plugin-telegram` ist fuer AFK-Betrieb vorbereitet
- AFK-Heartbeat und Approval-Routing sind lokal implementiert
- Planning-first ist Standard, nicht optional
- Antigravity Builder fuer parallele Multi-Agent-Missionen via antigravity-swarm
- Skill-basiertes Routing unterstuetzt spezialisierte Aufgabenverteilung

## Wichtige Einstiege

- `scripts/paperclip/Initialize-Vorce-Studios.ps1`
- `scripts/paperclip/Start-Vorce-Studios.ps1`
- `scripts/paperclip/Stop-Vorce-Studios.ps1`
- `scripts/paperclip/Get-Vorce-StudiosHealth.ps1`
- `scripts/paperclip/Invoke-Vorce-StudiosPlanningSweep.ps1`
- `scripts/paperclip/Sync-Vorce-StudiosGitHubState.ps1`
- `scripts/paperclip/Set-Vorce-StudiosTelegramConfig.ps1`
- `scripts/paperclip/Enable-Vorce-StudiosAfkMode.ps1`

## Policies

- `policies/system.psd1` — Firmenstruktur, Ports, Intervalle
- `policies/routing.psd1` — Executor-Auswahl, Fallback-Chains, Rollen
- `policies/planning.psd1` — Priorisierung, Scoring, Goal-Alignment
- `policies/sync.psd1` — GitHub-Sync, Labels, Project-V2-Felder
- `policies/governance.psd1` — Human-Gates, Merge-Regeln
- `policies/afk.psd1` — AFK-Modus, Telegram-Heartbeat
- `policies/risk.psd1` — High-Risk-Pfade, Review-Keywords, Fast-Lane
- `policies/goals.psd1` — Firmen-Mission und strategische Ziele
- `policies/skills.psd1` — Skills mit Agent-Zuordnung
- `policies/processes.psd1` — Workflow-Definitionen und Auto-Trigger

## Agenten-Instruktionen

- `instructions/ceo.md` — Victor (CEO / Chief Architect)
- `instructions/lena-assistant.md` — Lena (Personal Assistant)
- `instructions/chief-of-staff.md` — Liam (Chief of Staff / Capacity Router)
- `instructions/discovery-scout.md` — Noah (Discovery Scout)
- `instructions/jules-builder.md` — Jules (Builder)
- `instructions/jules-session-monitor.md` — Jules (Session Monitor)
- `instructions/github-pr-monitor.md` — Olivia (GitHub PR Monitor)
- `instructions/antigravity-builder.md` — Aria (Antigravity Builder)
- `instructions/gemini-reviewer.md` — Mia (Gemini Reviewer)
- `instructions/qwen-reviewer.md` — Elias (Qwen Reviewer)
- `instructions/codex-reviewer.md` — Caleb (Codex Reviewer)
- `instructions/ops-steward.md` — Sophia (Ops / Merge Steward)
- `instructions/atlas-context.md` — Atlas (Context Agent)

## Templates

- `templates/capacity-ledger.seed.psd1` — Tool-Verfuegbarkeit
- `templates/vorce-swarm-preset.yaml` — Antigravity Swarm Presets fuer Vorce

## Vollstaendige Betriebsdoku

Siehe:

- `docs/A3_PROJECT/B3_OPERATIONS/DOC-C5_PAPERCLIP_CONTROL_PLANE.md`

