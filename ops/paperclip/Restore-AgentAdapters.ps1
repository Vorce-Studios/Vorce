[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
$syncScript = Join-Path $ScriptDir 'Sync-Vorce-StudiosPaperclip.ps1'

if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Sync-Skript nicht gefunden: $syncScript"
}

& $syncScript -SkipPlugins -SkipInstructions -SkipHeartbeats -SkipVictorSkills

if ($LASTEXITCODE -ne 0) {
    throw 'Adapter-Restore ueber Sync-Vorce-StudiosPaperclip.ps1 ist fehlgeschlagen.'
}
