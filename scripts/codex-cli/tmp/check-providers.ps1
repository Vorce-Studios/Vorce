Set-StrictMode -Version Latest
$j = Get-Content (Join-Path $PSScriptRoot "..\quota-registry.json") -Raw | ConvertFrom-Json

Write-Host "=== Provider Status ===" -ForegroundColor Cyan
$providers = @("jules","gemini_cli","kiro_cli","cline_cli","claude_code","copilot_cli","cursor_agent","codex_orchestrator")
foreach ($p in $providers) {
    $prov = $j.providers.$p
    $status = if ($prov.enabled) { "[ON]" } else { "[OFF]" }
    $color = if ($prov.enabled) { "Green" } else { "DarkGray" }
    Write-Host "  $p $status" -ForegroundColor $color
}
