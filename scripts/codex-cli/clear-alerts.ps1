# scripts/codex-cli/clear-alerts.ps1
# Signalisiert dem Autopilot-Loop, alle "decisions_pending" (Beta CEO Alerts) zu loeschen

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$FlagPath = Join-Path $ScriptDir "clear-alerts.flag"

# Erstelle die Flag-Datei
"1" | Set-Content -Path $FlagPath -Encoding UTF8
Write-Host "Der Clear-Befehl wurde gesendet. Der Autopilot-Loop wird die Eskalationen in Kuerze loeschen!" -ForegroundColor Green
