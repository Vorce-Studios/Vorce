[CmdletBinding()]
param(
    [switch]$PatchProbe
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$companyState = Get-VorceStudiosCompanyState
$companyId = [string]$companyState.company.id
$agents = @(Get-VorceStudiosAgents -CompanyId $companyId)

Write-Host "=== DUPlikate pro roleKey ===" -ForegroundColor Yellow
Write-Host ''

$byKey = @{}
foreach ($a in $agents) {
    $key = ''
    if ($a.metadata -and $a.metadata.roleKey) { $key = [string]$a.metadata.roleKey }
    if (-not $byKey.ContainsKey($key)) { $byKey[$key] = @() }
    $byKey[$key] += $a
}

foreach ($key in ($byKey.Keys | Sort-Object)) {
    $list = $byKey[$key]
    if ($list.Count -eq 1) { continue }

    Write-Host "[$key] $($list.Count) Duplikate:" -ForegroundColor Red
    foreach ($a in $list) {
        Write-Host "  - $($a.name) (id: $($a.id))" -ForegroundColor DarkGray
    }
    Write-Host ''
}

Write-Host "=== Fehlende roleKeys ===" -ForegroundColor Yellow
$desired = @('ceo', 'lena_assistant', 'chief_of_staff', 'discovery', 'jules', 'jules_monitor', 'pr_monitor', 'gemini_review', 'qwen_review', 'codex_review', 'ops', 'atlas', 'antigravity')
foreach ($d in $desired) {
    if (-not $byKey.ContainsKey($d)) {
        Write-Host "  FEHLEND: $d" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "=== API-Test: PATCH auf ersten Agenten ===" -ForegroundColor Yellow
$first = $agents[0]
if (-not $PatchProbe.IsPresent) {
    Write-Host "PATCH-Probe uebersprungen. Mit -PatchProbe aktivieren." -ForegroundColor DarkGray
} else {
    Write-Host "Teste PATCH auf $($first.name) (id: $($first.id)) ohne Nutzdaten-Aenderung..." -NoNewline

    try {
        $result = Invoke-VorceStudiosApi -Method PATCH -Path "/api/agents/$($first.id)" -Body @{
            title = [string]$first.title
        }
        Write-Host " ERFOLG: $($result | ConvertTo-Json -Depth 1 -Compress)" -ForegroundColor Green
    } catch {
        Write-Host " FEHLER ($($_.Exception.Response.StatusCode.Value__)): $($_.Exception.Message)" -ForegroundColor Red
    }
}
