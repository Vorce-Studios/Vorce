# StateManager.ps1 (Vorce 3.0)
# Saubere Zustandsverwaltung für globale und Run-lokale Daten

function Get-VorceGlobalStatePath {
    return Join-Path $PSScriptRoot "../../var/db/global-state.json"
}

function Read-VorceGlobalState {
    $path = Get-VorceGlobalStatePath
    if (Test-Path $path) {
        return Get-Content $path -Raw | ConvertFrom-Json
    }
    # Initialer Standard-State
    return [pscustomobject]@{
        version = "3.0.0"
        last_run = (Get-Date).ToString("o")
        stats = @{ runs_completed = 0; errors = 0 }
    }
}

function Save-VorceGlobalState {
    param([object]$State)
    $path = Get-VorceGlobalStatePath
    $State | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
}

function Initialize-RunState {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$RunType # MAIN, SUB, PART
    )
    
    $runId = "run_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
    $statePath = Join-Path $PSScriptRoot "../../var/run-states/$($RunType)_$($RunName).json"
    
    $state = [pscustomobject]@{
        id = $runId
        name = $RunName
        type = $RunType
        status = "initialized"
        started_at = (Get-Date).ToString("o")
        completed_at = $null
        metadata = @{}
        results = @()
    }
    
    $state | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding UTF8
    return $state
}

# Ende StateManager
