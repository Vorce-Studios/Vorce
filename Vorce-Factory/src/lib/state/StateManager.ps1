# StateManager.ps1 (Vorce 3.0)
# Saubere Zustandsverwaltung für globale und Run-lokale Daten

function Get-VorceGlobalStatePath {
    return Join-Path $global:VarDir "db/global-state.json"
}

function Read-VorceGlobalState {
    $path = Get-VorceGlobalStatePath
    if (Test-Path $path) {
        $raw = Get-Content $path -Raw
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq "null") {
            # Datei existiert aber enthält ungültige Daten (W5)
            return [pscustomobject]@{
                version = "3.0.0"
                last_run = (Get-Date).ToString("o")
                last_runs = @{}
                active_delegations = @()
                review_queue = @()
                escalated_issues = @()
                stats = @{ runs_completed = 0; errors = 0 }
            }
        }
        return $raw | ConvertFrom-Json
    }
    # Initialer Standard-State
    return [pscustomobject]@{
        version = "3.0.0"
        last_run = (Get-Date).ToString("o")
        last_runs = @{}
        active_delegations = @()
        review_queue = @()
        escalated_issues = @()
        stats = @{ runs_completed = 0; errors = 0 }
    }
}

function Save-VorceGlobalState {
    param([object]$State)
    $path = Get-VorceGlobalStatePath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $State | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding UTF8
}

function Initialize-RunState {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$RunType # MAIN, SUB, PART
    )

    $runId = "run_$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
    $statePath = Join-Path $global:VarDir "run-states/$($RunType)_$($RunName).json"
    $stateDir = Split-Path -Parent $statePath
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

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

function Save-VorceRunState {
    param(
        [Parameter(Mandatory)][object]$State
    )

    $statePath = Join-Path $global:VarDir "run-states/$($State.type)_$($State.name).json"
    $stateDir = Split-Path -Parent $statePath
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 20 | Set-Content $statePath -Encoding UTF8
}

# Ende StateManager
