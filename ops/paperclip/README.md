# Vorce-Studios Paperclip Control Plane

Dieses Verzeichnis enthaelt die versionierten Policies, Instruktionen und
Bootstrap-Artefakte fuer die lokale Paperclip-Company `Vorce-Studios`.

## Ziel

`Vorce-Studios` ist die manuell startbare lokale Control Plane fuer `Vorce`.
Sie plant zuerst, priorisiert GitHub-Issues, routed Arbeit dynamisch an den
aktuellen Tool-Pool und spiegelt die wichtigen Orchestrierungsdaten wieder
nach GitHub.

## Kernpunkte

- GitHub bleibt der fachliche Source-of-Truth
- Paperclip steuert Agenten, Queue, Approval-Flows und Laufzeit
- `paperclip-plugin-github-issues` sorgt fuer bidirektionale Issue-Verlinkung
- Project-V2-Sync zielt auf `Vorce-Studios#1` / `@Vorce Project Manager`
- `paperclip-plugin-telegram` ist fuer AFK-Betrieb vorbereitet
- AFK-Heartbeat und Approval-Routing sind lokal implementiert
- Planning-first ist Standard, nicht optional

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

- `policies/system.psd1`
- `policies/routing.psd1`
- `policies/planning.psd1`
- `policies/sync.psd1`
- `policies/governance.psd1`
- `policies/afk.psd1`

## Vollstaendige Betriebsdoku

Siehe:

- `docs/A3_PROJECT/B3_OPERATIONS/DOC-C5_PAPERCLIP_CONTROL_PLANE.md`
