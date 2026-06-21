# StateManager.ps1 (Vorce 3.0)
# Konsistente Run-State-Verwaltung mit Latest- und History-Dateien.

function Get-VorceGlobalStatePath {
    return Join-Path $global:VarDir 'db/global-state.json'
}

function Get-VorceRunStatesDir {
    return Join-Path $global:VarDir 'run-states'
}

function Get-VorceRunHistoryDir {
    return Join-Path $global:VarDir 'run-history'
}

function Ensure-VorceParentDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
}

function New-VorceRunStateObject {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$RunType,
        [string]$MainRunId,
        [string]$ParentRunId,
        [string]$InputFingerprint
    )

    return [pscustomobject]@{
        schema_version = 2
        id = "run_$((Get-Date).ToString('yyyyMMdd_HHmmss'))_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        main_run_id = $MainRunId
        parent_run_id = $ParentRunId
        name = $RunName
        type = $RunType
        status = 'initialized'
        started_at = (Get-Date).ToString('o')
        completed_at = $null
        duration_ms = $null
        input_fingerprint = $InputFingerprint
        metadata = [ordered]@{}
        results = @()
    }
}

function Initialize-RunState {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$RunType,
        [string]$MainRunId,
        [string]$ParentRunId,
        [string]$InputFingerprint
    )

    $state = New-VorceRunStateObject -RunName $RunName -RunType $RunType -MainRunId $MainRunId -ParentRunId $ParentRunId -InputFingerprint $InputFingerprint
    Save-VorceRunState -State $state
    return $state
}

function Read-VorceGlobalState {
    $path = Get-VorceGlobalStatePath
    if (-not (Test-Path $path)) {
        return [pscustomobject]@{
            version = '3.0.0'
            last_run = (Get-Date).ToString('o')
            last_runs = @{}
            active_delegations = @()
            review_queue = @()
            escalated_issues = @()
            stats = @{ runs_completed = 0; errors = 0 }
        }
    }

    $raw = Get-Content $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq 'null') {
        return [pscustomobject]@{
            version = '3.0.0'
            last_run = (Get-Date).ToString('o')
            last_runs = @{}
            active_delegations = @()
            review_queue = @()
            escalated_issues = @()
            stats = @{ runs_completed = 0; errors = 0 }
        }
    }

    return $raw | ConvertFrom-Json
}

function Save-VorceGlobalState {
    param([Parameter(Mandatory)][object]$State)
    $path = Get-VorceGlobalStatePath
    Ensure-VorceParentDirectory -Path $path
    $tempPath = "$path.tmp"
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $path -Force
}

function Get-VorceRunStatePath {
    param([Parameter(Mandatory)][object]$State)
    return Join-Path (Get-VorceRunStatesDir) ("{0}_{1}.json" -f $State.type, $State.name)
}

function Get-VorceRunHistoryPath {
    param([Parameter(Mandatory)][object]$State)
    $historyDir = Join-Path (Get-VorceRunHistoryDir) $State.type
    $safeName = $State.name -replace '[\\/:*?"<>|]', '_'
    return Join-Path $historyDir ("{0}_{1}.json" -f $safeName, $State.id)
}

function Save-VorceRunState {
    param([Parameter(Mandatory)][object]$State)

    if (-not $State.schema_version) {
        $State | Add-Member -MemberType NoteProperty -Name schema_version -Value 2 -Force
    }
    if (-not $State.metadata) {
        $State | Add-Member -MemberType NoteProperty -Name metadata -Value @{} -Force
    }

    $statePath = Get-VorceRunStatePath -State $State
    Ensure-VorceParentDirectory -Path $statePath

    $finalized = [pscustomobject]@{
        schema_version = $State.schema_version
        id = $State.id
        main_run_id = $State.main_run_id
        parent_run_id = $State.parent_run_id
        name = $State.name
        type = $State.type
        status = $State.status
        started_at = $State.started_at
        completed_at = $State.completed_at
        duration_ms = $State.duration_ms
        input_fingerprint = $State.input_fingerprint
        metadata = $State.metadata
        results = @($State.results)
    }

    $tempPath = "$statePath.tmp"
    $finalized | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force

    $historyPath = Get-VorceRunHistoryPath -State $finalized
    Ensure-VorceParentDirectory -Path $historyPath
    $historyTemp = "$historyPath.tmp"
    $finalized | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $historyTemp -Encoding UTF8
    Move-Item -LiteralPath $historyTemp -Destination $historyPath -Force

    return $finalized
}

function Get-VorceRunStateCandidates {
    param([Parameter(Mandatory)][string]$RunName)

    $runStatesDir = Get-VorceRunStatesDir
    if (-not (Test-Path $runStatesDir)) { return @() }
    return Get-ChildItem -LiteralPath $runStatesDir -Filter "*_$RunName.json" -File -ErrorAction SilentlyContinue
}

function Get-VorceLatestRunState {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [string]$RunType
    )

    $candidates = @(Get-VorceRunStateCandidates -RunName $RunName)
    if ($RunType) {
        $candidates = @($candidates | Where-Object { $_.BaseName -like "$RunType`_*" })
    }
    if (-not $candidates.Count) { return $null }

    $states = foreach ($candidate in $candidates) {
        try {
            $json = Get-Content -LiteralPath $candidate.FullName -Raw
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $state = $json | ConvertFrom-Json
                $state | Add-Member -MemberType NoteProperty -Name source_file -Value $candidate.Name -Force
                $state
            }
        } catch {
        }
    }

    $states = @($states)
    if (-not $states.Count) { return $null }
    return $states | Sort-Object {
        if ($_.completed_at) { [datetime]$_.completed_at } else { [datetime]$_.started_at }
    } -Descending | Select-Object -First 1
}

function Get-VorceReusableRunResult {
    param(
        [Parameter(Mandatory)][string]$MainRunId,
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$InputFingerprint,
        [object[]]$DependencyResultIds = @()
    )

    $historyDir = Get-VorceRunHistoryDir
    if (-not (Test-Path $historyDir)) { return $null }

    $searchRoots = @(
        (Join-Path $historyDir 'PART'),
        (Join-Path $historyDir 'SUB')
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            try {
                $candidate = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                if ($candidate.main_run_id -ne $MainRunId) { continue }
                if ($candidate.name -ne $RunName) { continue }
                if ($candidate.input_fingerprint -ne $InputFingerprint) { continue }
                if ($candidate.status -ne 'completed') { continue }
                return $candidate
            } catch {
            }
        }
    }

    return $null
}

function Get-VorceRunSummary {
    param([int]$Limit = 10)

    $historyDir = Get-VorceRunHistoryDir
    $summary = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        recent_runs = @()
        stats_24h = [ordered]@{}
        stats_7d = [ordered]@{}
    }

    if (-not (Test-Path $historyDir)) {
        return [pscustomobject]$summary
    }

    $states = Get-ChildItem -LiteralPath $historyDir -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $state = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $state | Add-Member -MemberType NoteProperty -Name source_file -Value $_.Name -Force
            $state
        } catch {
        }
    }

    $states = @($states | Where-Object { $_ -and $_.type -eq 'MAIN' })
    $ordered = $states | Sort-Object {
        if ($_.completed_at) { [datetime]$_.completed_at } else { [datetime]$_.started_at }
    } -Descending | Select-Object -First $Limit

    $summary.recent_runs = @(
        foreach ($state in $ordered) {
            [pscustomobject]@{
                run_id = $state.id
                main_run = $state.name
                status = $state.status
                started_at = $state.started_at
                completed_at = $state.completed_at
                duration_ms = $state.duration_ms
                sub_runs = [pscustomobject]@{
                    completed = @($state.results | Where-Object { $_.status -eq 'completed' }).Count
                    failed = @($state.results | Where-Object { $_.status -eq 'failed' }).Count
                    skipped = @($state.results | Where-Object { $_.status -eq 'skipped' }).Count
                    reused = @($state.results | Where-Object { $_.status -eq 'reused' }).Count
                }
                part_runs = [pscustomobject]@{
                    completed = 0
                    failed = 0
                    skipped = 0
                    reused = 0
                }
                provider_attempts = 0
                fallbacks = 0
                estimated_cost_usd = 0
                input_tokens = 0
                output_tokens = 0
                result_summary = if ($state.results) { "Sub-Runs: $(@($state.results).Count)" } else { 'Keine Ergebnisse' }
                primary_error = $null
            }
        }
    )

    return [pscustomobject]$summary
}
