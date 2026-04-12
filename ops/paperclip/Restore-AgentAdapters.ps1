[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$cid = '2d25257e-2350-4507-bc98-3acd8b0dfec9'
$agents = @(Get-VorceStudiosAgents -CompanyId $cid)
$paths = Get-VorceStudiosPaths
$root = Get-VorceStudiosRoot

# Agent-Map: roleKey -> adapterType + optional model
$adapterMap = [ordered]@{
    'ceo'              = @{ type = 'codex_local';   model = '' }
    'lena_assistant'   = @{ type = 'process';       model = ''; cmd = 'qwen'; args = @('-y', '--sandbox', '--dangerously-skip-permissions', '--print', 'You are Lena, Personal Assistant to the CEO. Read your instructions from the instructionPath.') }
    'chief_of_staff'   = @{ type = 'codex_local';   model = '' }
    'discovery'        = @{ type = 'gemini_local';  model = '' }
    'jules'            = @{ type = 'gemini_local';  model = '' }
    'jules_monitor'    = @{ type = 'process';       model = ''; cmd = 'qwen'; args = @('-y', '--sandbox', '--dangerously-skip-permissions', '--print', 'You are the Jules Session Monitor. Read your instructions from the instructionPath.') }
    'pr_monitor'       = @{ type = 'process';       model = ''; cmd = 'qwen'; args = @('-y', '--sandbox', '--dangerously-skip-permissions', '--print', 'You are the GitHub PR Monitor. Read your instructions from the instructionPath.') }
    'gemini_review'    = @{ type = 'gemini_local';  model = '' }
    'qwen_review'      = @{ type = 'process';       model = ''; cmd = 'qwen'; args = @('-y', '--sandbox', '--dangerously-skip-permissions', '--print', 'You are the Qwen Reviewer. Read your instructions from the instructionPath.') }
    'codex_review'     = @{ type = 'codex_local';   model = '' }
    'ops'              = @{ type = 'gemini_local';  model = '' }
    'atlas'            = @{ type = 'gemini_local';  model = '' }
    'antigravity'      = @{ type = 'gemini_local';  model = '' }
}

$agentScript = Join-Path $root 'scripts\paperclip\Invoke-Vorce-StudiosAgent.ps1'

$updated = 0
foreach ($agent in $agents) {
    $key = ''
    if ($agent.metadata -and $agent.metadata.roleKey) { $key = [string]$agent.metadata.roleKey }
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    $cfg = $adapterMap[$key]
    if ($null -eq $cfg) { Write-Host "SKIP: $($agent.name) (unknown roleKey: $key)" -ForegroundColor Yellow; continue }

    if ($cfg.type -eq 'process') {
        # process adapter pointing to qwen CLI
        $payload = @{
            adapterType = 'process'
            adapterConfig = @{
                command = 'qwen'
                commandArgs = $cfg.args
                cwd = $root
                env = @{}
            }
        }
    } else {
        $payload = @{
            adapterType = $cfg.type
        }
        if (-not [string]::IsNullOrWhiteSpace($cfg.model)) {
            $payload['adapterConfig'] = @{ model = $cfg.model }
        }
    }

    Write-Host "$($agent.name) [$key] -> $($cfg.type)" -NoNewline
    try {
        $result = Invoke-VorceStudiosApi -Method PATCH -Path "/api/agents/$($agent.id)" -Body $payload
        if ($null -ne $result) {
            Write-Host " OK (adapter: $($result.adapterType))" -ForegroundColor Green
            $updated++
        } else {
            Write-Host " KEINE ANTWORT" -ForegroundColor Red
        }
    } catch {
        Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "$updated/$($agents.Count) Agenten aktualisiert." -ForegroundColor Cyan
