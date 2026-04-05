[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [hashtable]$Context,
    
    [Parameter(Mandatory=$true)]
    [object]$Issue,
    
    [Parameter(Mandatory=$true)]
    [string]$TaskType
)

# Vorce-Studios: Direct Local Binding for Antigravity Swarm
# Dieser Takt eliminiert den Overhead der `gemini` CLI und 
# kommuniziert direkt mit dem Antigravity System Daemon.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AntigravityDaemonPort {
    # Suche in der lokalen Gemini Konfiguration nach dem aktiven IPC/REST Port
    $configPath = Join-Path $env:USERPROFILE '.gemini\antigravity\daemon.json'
    if (Test-Path $configPath) {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($config.port) { return $config.port }
    }
    return 8080 # Default
}

$port = Get-AntigravityDaemonPort
$apiUrl = "http://127.0.0.1:$port/api/swarm/execute"

$payload = @{
    mission_context = @{
        repository = $Context.Repository
        gh_issue = if ($Issue.Metadata.gh_issue) { $Issue.Metadata.gh_issue } else { $null }
        task_type = $TaskType
        risk_class = $Issue.Metadata.risk_class
    }
    objective = $Issue.description
    preset = 'vorce_impl' # Default Swarm Preset
}

$jsonPayload = $payload | ConvertTo-Json -Depth 5

Write-Verbose "Calling Antigravity Daemon Native API at $apiUrl"
try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $jsonPayload -ContentType "application/json" -TimeoutSec 120
    Write-Output "Antigravity Swarm successfully initiated via native binding. Job ID: $($response.job_id)"
    return $response
} catch {
    Write-Warning "Native Antigravity Binding failed. Fallback to CLI will be triggered via Chief of Staff. Error: $_"
    throw
}
