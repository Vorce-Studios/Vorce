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

function Get-VorceStateStringHash {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))
    } finally {
        $sha.Dispose()
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

    $obj = [pscustomobject]@{
        schema_version = 2
        id = "run_$((Get-Date).ToString('yyyyMMdd_HHmmss'))_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        main_run_id = if ($RunType -eq 'MAIN') { $null } else { $MainRunId }
        parent_run_id = if ($RunType -eq 'MAIN') { $null } else { $ParentRunId }
        name = $RunName
        type = $RunType
        status = 'initialized'
        started_at = (Get-Date).ToString('o')
        completed_at = $null
        duration_ms = $null
        input_fingerprint = $InputFingerprint
        metadata = [ordered]@{}
        results = @()
        resume = $null
        execution_graph = $null
        attempts = @()
        dependency_result_ids = @()
        result_ref = $null
        result_id = $null
        result_summary = $null
        reusable = $false
        idempotency_key = $null
        error = $null
        error_class = $null
        retry_after = $null
        parts = @()
    }

    if ($RunType -eq 'MAIN') {
        $obj.main_run_id = $obj.id
    }

    return $obj
}

function Initialize-VorceRunState {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$RunType,
        [string]$MainRunId,
        [string]$ParentRunId,
        [string]$InputFingerprint
    )

    $state = New-VorceRunStateObject -RunName $RunName -RunType $RunType -MainRunId $MainRunId -ParentRunId $ParentRunId -InputFingerprint $InputFingerprint
    Save-VorceRunState -State $state | Out-Null
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
    $safeName = $State.name -replace '[\\/:*?"<>|]', '_'
    $historyDir = Join-Path (Join-Path (Get-VorceRunHistoryDir) $State.type) $safeName
    return Join-Path $historyDir ("{0}.json" -f $State.id)
}

function Save-VorceRunState {
    param([Parameter(Mandatory)][object]$State)

    if (-not $State.schema_version) {
        $State | Add-Member -MemberType NoteProperty -Name schema_version -Value 2 -Force
    }
    if (-not $State.metadata) {
        $State | Add-Member -MemberType NoteProperty -Name metadata -Value @{} -Force
    }

    if ($State.type -eq 'MAIN' -and -not $State.main_run_id) {
        $State.main_run_id = $State.id
    }

    $allowedProperties = @(
        'schema_version', 'id', 'main_run_id', 'parent_run_id', 'name', 'type',
        'status', 'started_at', 'completed_at', 'duration_ms', 'input_fingerprint',
        'metadata', 'results', 'resume', 'execution_graph', 'attempts',
        'dependency_result_ids', 'result_ref', 'result_id', 'result_summary',
        'reusable', 'idempotency_key', 'error', 'error_class', 'retry_after', 'parts'
    )

    $finalized = [pscustomobject]@{}
    foreach ($prop in $allowedProperties) {
        $propValue = if ($State.PSObject.Properties.Name -contains $prop) { $State.$prop } else { $null }
        if ($prop -in @('attempts', 'dependency_result_ids') -and $null -ne $propValue -and -not ($propValue -is [array])) {
            $propValue = @($propValue)
        }
        if ($prop -eq 'parts' -and $null -ne $propValue -and -not ($propValue -is [array])) {
            $propValue = @($propValue)
        }
        $finalized | Add-Member -MemberType NoteProperty -Name $prop -Value $propValue -Force
    }

    $historyPath = Get-VorceRunHistoryPath -State $finalized
    Ensure-VorceParentDirectory -Path $historyPath

    $isFinal = $finalized.status -in @('completed', 'failed', 'skipped', 'reused')
    $historyExists = Test-Path -LiteralPath $historyPath
    $serializedState = $finalized | ConvertTo-Json -Depth 20

    if ($historyExists) {
        $existingHistory = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json
        $existingIsFinal = $existingHistory.status -in @('completed', 'failed', 'skipped', 'reused')
        if ($existingIsFinal) {
            $existingSerialized = $existingHistory | ConvertTo-Json -Depth 20
            if ($existingSerialized -ne $serializedState) {
                throw "Finaler Run-State '$($finalized.id)' darf nicht widerspruechlich ueberschrieben werden."
            }
        }
    }

    if (-not $historyExists -or -not $existingIsFinal) {
        $historyTemp = "$historyPath.tmp"
        $serializedState | Set-Content -LiteralPath $historyTemp -Encoding UTF8
        Move-Item -LiteralPath $historyTemp -Destination $historyPath -Force
    }

    $statePath = Get-VorceRunStatePath -State $finalized
    Ensure-VorceParentDirectory -Path $statePath
    $tempPath = "$statePath.tmp"
    $serializedState | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $statePath -Force

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
        foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            try {
                $candidate = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                if ($candidate.main_run_id -ne $MainRunId) { continue }
                if ($candidate.name -ne $RunName) { continue }
                if ($candidate.input_fingerprint -ne $InputFingerprint) { continue }
                if ($candidate.status -notin @('completed', 'reused')) { continue }
                if ($candidate.reusable -ne $true) { continue }
                $candidateDependencies = @($candidate.dependency_result_ids | ForEach-Object { [string]$_ } | Sort-Object)
                $expectedDependencies = @($DependencyResultIds | ForEach-Object { [string]$_ } | Sort-Object)
                if (($candidateDependencies -join '|') -ne ($expectedDependencies -join '|')) { continue }
                if ([string]::IsNullOrWhiteSpace([string]$candidate.result_ref)) { continue }
                $resultPath = if ([System.IO.Path]::IsPathRooted([string]$candidate.result_ref)) {
                    [string]$candidate.result_ref
                } else {
                    Join-Path $global:VarDir ([string]$candidate.result_ref)
                }
                if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { continue }
                return $candidate
            } catch {
            }
        }
    }

    return $null
}

function Get-VorceRunStateById {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$RunType = 'MAIN'
    )

    $root = Join-Path (Get-VorceRunHistoryDir) $RunType
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $file = Get-ChildItem -LiteralPath $root -Recurse -Filter "$RunId.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $file) { return $null }
    try {
        return Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-VorcePriorRunAttemptState {
    param(
        [Parameter(Mandatory)][string]$MainRunId,
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$InputFingerprint
    )

    $root = Join-Path (Get-VorceRunHistoryDir) 'PART'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $states = foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($state.main_run_id -eq $MainRunId -and
                $state.name -eq $RunName -and
                $state.input_fingerprint -eq $InputFingerprint -and
                $state.status -in @('waiting_provider', 'failed')) {
                $state
            }
        } catch {
        }
    }
    return @($states | Sort-Object {
        if ($_.completed_at) { [datetime]$_.completed_at } else { [datetime]$_.started_at }
    } -Descending) | Select-Object -First 1
}

function Get-VorceResumableMainRun {
    param(
        [datetime]$Now = (Get-Date),
        [switch]$IgnoreRetryAfter
    )

    $root = Join-Path (Get-VorceRunHistoryDir) 'MAIN'
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $candidates = foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($state.status -notin @('waiting_provider', 'running')) { continue }
            if ($state.metadata -and $state.metadata.manual_pause -eq $true) { continue }
            if (-not $IgnoreRetryAfter -and $state.retry_after) {
                try {
                    if ([datetime]$state.retry_after -gt $Now) { continue }
                } catch {}
            }
            $state
        } catch {
        }
    }
    return @($candidates | Sort-Object {
        if ($_.resume -and $_.resume.last_checkpoint_at) { [datetime]$_.resume.last_checkpoint_at } else { [datetime]$_.started_at }
    }) | Select-Object -First 1
}

function Save-VorceRunResultArtifact {
    param(
        [Parameter(Mandatory)][object]$State,
        [AllowNull()][object]$Result
    )

    if (-not $State.result_id) {
        $State.result_id = "result_$([guid]::NewGuid().ToString('N'))"
    }
    $safeName = ([string]$State.name) -replace '[\\/:*?"<>|]', '_'
    $relativePath = "run-results/$($State.main_run_id)/$safeName/$($State.result_id).json"
    $artifactPath = Join-Path $global:VarDir $relativePath
    Ensure-VorceParentDirectory -Path $artifactPath
    $payload = [ordered]@{
        schema_version = 1
        result_id = $State.result_id
        main_run_id = $State.main_run_id
        run_id = $State.id
        run_name = $State.name
        created_at = (Get-Date).ToString('o')
        result = $Result
    }
    $tempPath = "$artifactPath.tmp"
    $payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $artifactPath -Force
    $State.result_ref = $relativePath.Replace('\', '/')
    return $State
}

function Read-VorceRunResultArtifact {
    param([Parameter(Mandatory)][string]$ResultRef)
    $path = if ([System.IO.Path]::IsPathRooted($ResultRef)) { $ResultRef } else { Join-Path $global:VarDir $ResultRef }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Test-VorceRunResultArtifact {
    param([AllowNull()][string]$ResultRef)

    if ([string]::IsNullOrWhiteSpace($ResultRef)) { return $false }
    $path = if ([System.IO.Path]::IsPathRooted($ResultRef)) {
        $ResultRef
    } else {
        Join-Path $global:VarDir $ResultRef
    }
    return Test-Path -LiteralPath $path -PathType Leaf
}

function Invoke-VorceIdempotentAction {
    param(
        [Parameter(Mandatory)][string]$IdempotencyKey,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $hash = Get-VorceStateStringHash -Text $IdempotencyKey
    $safeHash = $hash -replace '[/+=]', '_'
    $path = Join-Path $global:VarDir "idempotency/$safeHash.json"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    $result = & $Action
    Ensure-VorceParentDirectory -Path $path
    $record = [pscustomobject]@{
        idempotency_key = $IdempotencyKey
        created_at = (Get-Date).ToString('o')
        result = $result
    }
    $tempPath = "$path.tmp"
    $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $path -Force
    return $record
}

function Update-VorceExecutionGraph {
    param(
        [Parameter(Mandatory)][object]$MainState,
        [Parameter(Mandatory)][object]$RunState
    )

    $graph = @($MainState.execution_graph)
    $entry = [pscustomobject]@{
        run_name = $RunState.name
        type = $RunState.type
        status = $RunState.status
        input_fingerprint = $RunState.input_fingerprint
        dependency_result_ids = @($RunState.dependency_result_ids)
        result_ref = $RunState.result_ref
        result_id = $RunState.result_id
        reusable = [bool]$RunState.reusable
        attempts = @($RunState.attempts)
    }
    $graph = @($graph | Where-Object { -not ($_.run_name -eq $entry.run_name -and $_.type -eq $entry.type) })
    $MainState.execution_graph = @($graph + $entry)
    return $MainState
}

function Get-VorceRunDescendants {
    param([Parameter(Mandatory)][object]$State)

    $items = New-Object System.Collections.ArrayList
    function Add-VorceRunNode {
        param([object]$Node)
        if ($null -eq $Node) { return }
        $null = $items.Add($Node)
        foreach ($propertyName in @('results', 'parts')) {
            if ($Node.PSObject.Properties.Name -contains $propertyName) {
                foreach ($child in @($Node.$propertyName)) {
                    Add-VorceRunNode -Node $child
                }
            }
        }
    }
    Add-VorceRunNode -Node $State
    return @($items)
}

function Get-VorceRunMetrics {
    param([Parameter(Mandatory)][object]$State)

    $nodes = @(Get-VorceRunDescendants -State $State)
    $attempts = New-Object System.Collections.ArrayList
    $attemptKeys = @{}
    $fallbacks = 0

    foreach ($node in $nodes) {
        $nodeAttempts = if ($node.PSObject.Properties.Name -contains 'attempts') { @($node.attempts) } else { @() }
        if ($nodeAttempts.Count -gt 1) {
            $fallbacks += $nodeAttempts.Count - 1
        }
        foreach ($attempt in $nodeAttempts) {
            if ($null -eq $attempt) { continue }
            $key = if ($attempt.attempt_id) {
                [string]$attempt.attempt_id
            } else {
                "{0}|{1}|{2}|{3}" -f $attempt.provider, $attempt.model, $attempt.started_at, $attempt.exit_code
            }
            if (-not $attemptKeys.ContainsKey($key)) {
                $attemptKeys[$key] = $true
                $null = $attempts.Add($attempt)
            }
        }
    }

    $cost = 0.0
    $inputTokens = 0L
    $outputTokens = 0L
    foreach ($attempt in $attempts) {
        if ($attempt.PSObject.Properties.Name -contains 'estimated_cost_usd' -and $null -ne $attempt.estimated_cost_usd) {
            $cost += [double]$attempt.estimated_cost_usd
        } elseif ($attempt.usage -and $null -ne $attempt.usage.estimated_cost_usd) {
            $cost += [double]$attempt.usage.estimated_cost_usd
        } elseif ($attempt.PSObject.Properties.Name -contains 'cost_usd' -and $null -ne $attempt.cost_usd) {
            $cost += [double]$attempt.cost_usd
        }

        if ($attempt.PSObject.Properties.Name -contains 'input_tokens' -and $null -ne $attempt.input_tokens) {
            $inputTokens += [long]$attempt.input_tokens
        } elseif ($attempt.usage -and $null -ne $attempt.usage.input_tokens) {
            $inputTokens += [long]$attempt.usage.input_tokens
        }
        if ($attempt.PSObject.Properties.Name -contains 'output_tokens' -and $null -ne $attempt.output_tokens) {
            $outputTokens += [long]$attempt.output_tokens
        } elseif ($attempt.usage -and $null -ne $attempt.usage.output_tokens) {
            $outputTokens += [long]$attempt.usage.output_tokens
        }
    }

    $errorClasses = @(
        @($nodes | ForEach-Object {
            $hasAttempts = $_.PSObject.Properties.Name -contains 'attempts' -and @($_.attempts).Count -gt 0
            if (-not $hasAttempts -and $_.error_class) { [string]$_.error_class }
        }) +
        @($attempts | ForEach-Object { if ($_.error_class) { [string]$_.error_class } })
    )
    $noWorkCount = @($nodes | Where-Object {
        $_.status -eq 'no_work' -or
        $_.outcome -eq 'no_work' -or
        $_.result_status -eq 'no_work' -or
        ($_.metadata -and $_.metadata.outcome -eq 'no_work')
    }).Count

    $resumeCount = 0
    if ($State.PSObject.Properties.Name -contains 'resume_count' -and $null -ne $State.resume_count) {
        $resumeCount = [int]$State.resume_count
    } elseif ($State.resume -and $null -ne $State.resume.resume_count) {
        $resumeCount = [int]$State.resume.resume_count
    } elseif ($State.metadata -and $null -ne $State.metadata.resume_count) {
        $resumeCount = [int]$State.metadata.resume_count
    }

    return [pscustomobject]@{
        provider_attempts = $attempts.Count
        fallbacks = $fallbacks
        timeout_errors = @($errorClasses | Where-Object { $_ -eq 'timeout' }).Count
        rate_limit_errors = @($errorClasses | Where-Object { $_ -in @('rate_limited', 'quota_exhausted') }).Count
        auth_errors = @($errorClasses | Where-Object { $_ -eq 'auth_missing' }).Count
        estimated_cost_usd = [math]::Round($cost, 6)
        input_tokens = $inputTokens
        output_tokens = $outputTokens
        resume_count = $resumeCount
        no_work = $noWorkCount
    }
}

function Get-VorcePrimaryRunError {
    param([Parameter(Mandatory)][object]$State)

    if ($State.error) { return [string]$State.error }
    foreach ($node in @(Get-VorceRunDescendants -State $State)) {
        if ($node.status -eq 'failed' -and $node.error) {
            return [string]$node.error
        }
    }
    return $null
}

function Get-VorceRunResultSummary {
    param([Parameter(Mandatory)][object]$State)

    $summary = $null
    if ($State.metadata -and $State.metadata.result_summary) {
        $summary = [string]$State.metadata.result_summary
    } elseif ($State.result_summary) {
        $summary = [string]$State.result_summary
    } else {
        $metrics = Get-VorceRunMetrics -State $State
        $summary = "Sub-Runs: $(@($State.results).Count), Attempts: $($metrics.provider_attempts), Fallbacks: $($metrics.fallbacks), Reused: $(@(Get-VorceRunDescendants -State $State | Where-Object { $_.status -eq 'reused' }).Count)"
    }
    if ($summary.Length -gt 160) {
        return $summary.Substring(0, 157) + '...'
    }
    return $summary
}

function Get-VorceRunSummary {
    param([int]$Limit = 10)

    $Limit = [math]::Max(1, [math]::Min(100, $Limit))
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
    $ordered = @($states | Sort-Object {
        if ($_.completed_at) { [datetime]$_.completed_at } else { [datetime]$_.started_at }
    } -Descending)

    $summary.recent_runs = @(
        foreach ($state in @($ordered | Select-Object -First $Limit)) {
            $metrics = Get-VorceRunMetrics -State $state
            $subRuns = @($state.results)
            $parts = @($subRuns | ForEach-Object { @($_.parts) })
            [pscustomobject]@{
                run_id = $state.id
                main_run = $state.name
                status = $state.status
                started_at = $state.started_at
                completed_at = $state.completed_at
                duration_ms = $state.duration_ms
                sub_runs = [pscustomobject]@{
                    completed = @($subRuns | Where-Object { $_.status -eq 'completed' }).Count
                    failed = @($subRuns | Where-Object { $_.status -eq 'failed' }).Count
                    skipped = @($subRuns | Where-Object { $_.status -eq 'skipped' }).Count
                    reused = @($subRuns | Where-Object { $_.status -eq 'reused' }).Count
                }
                part_runs = [pscustomobject]@{
                    completed = @($parts | Where-Object { $_.status -eq 'completed' }).Count
                    failed = @($parts | Where-Object { $_.status -eq 'failed' }).Count
                    skipped = @($parts | Where-Object { $_.status -eq 'skipped' }).Count
                    reused = @($parts | Where-Object { $_.status -eq 'reused' }).Count
                }
                provider_attempts = $metrics.provider_attempts
                fallbacks = $metrics.fallbacks
                estimated_cost_usd = $metrics.estimated_cost_usd
                input_tokens = $metrics.input_tokens
                output_tokens = $metrics.output_tokens
                resume_count = $metrics.resume_count
                no_work = $metrics.no_work
                result_summary = Get-VorceRunResultSummary -State $state
                primary_error = Get-VorcePrimaryRunError -State $state
            }
        }
    )

    foreach ($window in @(
        @{ Name = 'stats_24h'; Cutoff = (Get-Date).AddHours(-24) },
        @{ Name = 'stats_7d'; Cutoff = (Get-Date).AddDays(-7) }
    )) {
        $selected = @($ordered | Where-Object {
            $timestamp = if ($_.completed_at) { $_.completed_at } else { $_.started_at }
            $timestamp -and ([datetime]$timestamp) -ge $window.Cutoff
        })
        $durations = @($selected | ForEach-Object {
            if ($null -ne $_.duration_ms) { [long]$_.duration_ms }
        } | Where-Object { $_ -ge 0 } | Sort-Object)
        $subRuns = @($selected | ForEach-Object { @($_.results) })
        $parts = @($subRuns | ForEach-Object { @($_.parts) })
        $metrics = @($selected | ForEach-Object { Get-VorceRunMetrics -State $_ })
        $p95Index = if ($durations.Count) { [math]::Min($durations.Count - 1, [math]::Ceiling($durations.Count * 0.95) - 1) } else { -1 }
        $completedCount = @($selected | Where-Object { $_.status -eq 'completed' }).Count
        $summary.($window.Name) = [ordered]@{
            runs_started = $selected.Count
            runs_completed = $completedCount
            runs_failed = @($selected | Where-Object { $_.status -eq 'failed' }).Count
            runs_waiting_provider = @($selected | Where-Object { $_.status -eq 'waiting_provider' }).Count
            success_rate = if ($selected.Count) { $completedCount / $selected.Count } else { 0 }
            avg_duration_ms = if ($durations.Count) { [math]::Round(($durations | Measure-Object -Average).Average) } else { 0 }
            p95_duration_ms = if ($p95Index -ge 0) { $durations[$p95Index] } else { 0 }
            sub_runs_completed = @($subRuns | Where-Object { $_.status -eq 'completed' }).Count
            sub_runs_failed = @($subRuns | Where-Object { $_.status -eq 'failed' }).Count
            sub_runs_skipped = @($subRuns | Where-Object { $_.status -eq 'skipped' }).Count
            sub_runs_reused = @($subRuns | Where-Object { $_.status -eq 'reused' }).Count
            part_runs_completed = @($parts | Where-Object { $_.status -eq 'completed' }).Count
            part_runs_failed = @($parts | Where-Object { $_.status -eq 'failed' }).Count
            part_runs_skipped = @($parts | Where-Object { $_.status -eq 'skipped' }).Count
            part_runs_reused = @($parts | Where-Object { $_.status -eq 'reused' }).Count
            provider_attempts = ($metrics | Measure-Object provider_attempts -Sum).Sum
            fallbacks = ($metrics | Measure-Object fallbacks -Sum).Sum
            timeout_errors = ($metrics | Measure-Object timeout_errors -Sum).Sum
            rate_limit_errors = ($metrics | Measure-Object rate_limit_errors -Sum).Sum
            auth_errors = ($metrics | Measure-Object auth_errors -Sum).Sum
            estimated_cost_usd = [math]::Round(($metrics | Measure-Object estimated_cost_usd -Sum).Sum, 6)
            input_tokens = ($metrics | Measure-Object input_tokens -Sum).Sum
            output_tokens = ($metrics | Measure-Object output_tokens -Sum).Sum
            resume_count = ($metrics | Measure-Object resume_count -Sum).Sum
            no_work = ($metrics | Measure-Object no_work -Sum).Sum
        }
    }

    return [pscustomobject]$summary
}

function Set-VorceStateStatus {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][ValidateSet('running', 'completed', 'failed', 'skipped', 'waiting_provider', 'reused')][string]$Status,
        [string]$Error,
        [string]$ErrorClass
    )

    $State.status = $Status
    if ($Status -eq 'running' -and -not $State.started_at) {
        $State.started_at = (Get-Date).ToString('o')
    }
    $State.completed_at = if ($Status -in @('completed', 'failed', 'skipped', 'reused')) { (Get-Date).ToString('o') } else { $State.completed_at }

    if ($State.started_at -and $State.completed_at) {
        $State.duration_ms = [int]((New-TimeSpan -Start ([datetime]$State.started_at) -End ([datetime]$State.completed_at)).TotalMilliseconds)
    }

    if ($Error) {
        $State.error = $Error
        $State.error_class = $ErrorClass
    } elseif ($Status -notin @('failed', 'waiting_provider')) {
        $State.error = $null
        $State.error_class = $null
    }

    return $State
}

function Add-VorceStateProperty {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][string]$PropertyName,
        [object]$Value
    )
    if ($State.PSObject.Properties.Name -contains $PropertyName) {
        $State.$PropertyName = $Value
    } else {
        $State | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $Value -Force
    }
    return $State
}

function Set-VorceStateRunning {
    param([Parameter(Mandatory)][object]$State)
    $State = Set-VorceStateStatus -State $State -Status 'running'
    $State
}

function Set-VorceStateCompleted {
    param([Parameter(Mandatory)][object]$State)
    $State = Set-VorceStateStatus -State $State -Status 'completed'
    $State
}

function Set-VorceStateFailed {
    param(
        [Parameter(Mandatory)][object]$State,
        [string]$Error,
        [string]$ErrorClass = 'execution_error'
    )
    $State = Set-VorceStateStatus -State $State -Status 'failed' -Error $Error -ErrorClass $ErrorClass
    $State
}

function Set-VorceStateSkipped {
    param(
        [Parameter(Mandatory)][object]$State,
        [string]$Reason = 'skipped'
    )
    $State = Set-VorceStateStatus -State $State -Status 'skipped'
    $State.metadata['skip_reason'] = $Reason
    $State
}

function Set-VorceStateWaitingProvider {
    param(
        [Parameter(Mandatory)][object]$State,
        [Alias('RetryAfterSeconds')][object]$RetryAfter = 60,
        [string]$BlockedPartRun,
        [string]$Reason = 'provider_chain_exhausted'
    )
    $State = Set-VorceStateStatus -State $State -Status 'waiting_provider'
    $retryAt = if ($RetryAfter -is [int] -or $RetryAfter -is [long]) {
        (Get-Date).AddSeconds([int]$RetryAfter).ToString('o')
    } else {
        [string]$RetryAfter
    }
    $State.retry_after = $retryAt
    $resumeCount = if ($State.resume -and $null -ne $State.resume.resume_count) { [int]$State.resume.resume_count } else { 0 }
    $State.resume = [pscustomobject]@{
        resume_count = $resumeCount
        last_checkpoint_at = (Get-Date).ToString('o')
        retry_after = $retryAt
        blocked_part_run = $BlockedPartRun
        reason = $Reason
    }
    $State
}

function Set-VorceStateReused {
    param([Parameter(Mandatory)][object]$State)
    $State = Set-VorceStateStatus -State $State -Status 'reused'
    $State.reusable = $true
    $State
}

function Confirm-VorceStateSchema2 {
    param(
        [Parameter(Mandatory)][object]$State
    )

    return $null -ne $State.schema_version -and $State.schema_version -eq 2
}

# ─── Predicate-Helper (nahtloser Status-Check) ──────────────────────────────────

function Test-VorceStateIsCompleted {
    <#
    .SYNOPSIS
        Prueft, ob der State den Status 'completed' hat.
        Null-sicher: $null wird als nicht-completed gewertet.
    #>
    param(
        [AllowNull()]
        [object]$State
    )
    return $null -ne $State -and $null -ne $State.status -and $State.status -eq 'completed'
}

function Test-VorceStateIsFailed {
    <#
    .SYNOPSIS
        Prueft, ob der State den Status 'failed' hat.
        Null-sicher: $null wird als nicht-failed gewertet.
    #>
    param(
        [AllowNull()]
        [object]$State
    )
    return $null -ne $State -and $null -ne $State.status -and $State.status -eq 'failed'
}

function Test-VorceStateIsSkipped {
    <#
    .SYNOPSIS
        Prueft, ob der State den Status 'skipped' hat.
        Null-sicher: $null wird als nicht-skipped gewertet.
    #>
    param(
        [AllowNull()]
        [object]$State
    )
    return $null -ne $State -and $null -ne $State.status -and $State.status -eq 'skipped'
}

function Test-VorceStateIsWaitingProvider {
    <#
    .SYNOPSIS
        Prueft, ob der State den Status 'waiting_provider' hat.
        Null-sicher: $null wird als nicht-waiting_provider gewertet.
    #>
    param(
        [AllowNull()]
        [object]$State
    )
    return $null -ne $State -and $null -ne $State.status -and $State.status -eq 'waiting_provider'
}

# ─── Null-sicherer run_settings-Zugriff ────────────────────────────────────────

function Get-VorceRunSetting {
    <#
    .SYNOPSIS
        Greift null-sicher auf run_settings zu.
        ConfigBag.Config.run_settings kann null, fehlen oder teilweise definiert sein.
    .PARAMETER ConfigBag
        Der ConfigBag (muss Config enthalten).
    .PARAMETER SubRunName
        Name des Sub-Runs (optional).
    .PARAMETER PartRunName
        Name des Part-Runs (optional).
    .PARAMETER Key
        Der abzufragende Schluessel (z.B. 'enabled', 'timeout').
    .PARAMETER Default
        Rueckgabewert, wenn der Schluessel nicht existiert (Default: $null).
    .EXAMPLE
        Get-VorceRunSetting -ConfigBag $bag -SubRunName 'DataSync' -Key 'timeout' -Default 300
    #>
    param(
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [string]$SubRunName,
        [string]$PartRunName,
        [Parameter(Mandatory)][string]$Key,
        [object]$Default = $null
    )

    $config = if ($ConfigBag.ContainsKey('Config')) { $ConfigBag['Config'] } else { $null }
    if ($null -eq $config) { return $Default }

    $runSettings = $null
    try {
        $runSettings = $config.PSObject.Properties['run_settings']
        if ($null -eq $runSettings) { return $Default }
        $runSettings = $runSettings.Value
    } catch { return $Default }
    if ($null -eq $runSettings) { return $Default }

    if ($SubRunName) {
        $subRuns = $null
        try {
            $subRunsProp = $runSettings.PSObject.Properties['sub_runs']
            if ($null -eq $subRunsProp) { return $Default }
            $subRuns = $subRunsProp.Value
        } catch { return $Default }
        if ($null -eq $subRuns) { return $Default }

        if ($PartRunName) {
            $partRuns = $null
            try {
                $partRunsProp = $subRuns.PSObject.Properties[$SubRunName]
                if ($null -eq $partRunsProp) { return $Default }
                $partRuns = $partRunsProp.Value
            } catch { return $Default }
            if ($null -eq $partRuns) { return $Default }

            $partSettings = $null
            try {
                $partRunsSettingsProp = $partRuns.PSObject.Properties['part_runs']
                if ($null -eq $partRunsSettingsProp) { return $Default }
                $partRunsSettings = $partRunsSettingsProp.Value
            } catch { return $Default }
            if ($null -eq $partRunsSettings) { return $Default }

            try {
                $partSetting = $partRunsSettings.PSObject.Properties[$PartRunName]
                if ($null -eq $partSetting) { return $Default }
                $partSettingValue = $partSetting.Value
                $keyProp = $partSettingValue.PSObject.Properties[$Key]
                if ($null -eq $keyProp) { return $Default }
                return $keyProp.Value
            } catch { return $Default }
        } else {
            try {
                $subSetting = $subRuns.PSObject.Properties[$SubRunName]
                if ($null -eq $subSetting) { return $Default }
                $subSettingValue = $subSetting.Value
                $keyProp = $subSettingValue.PSObject.Properties[$Key]
                if ($null -eq $keyProp) { return $Default }
                return $keyProp.Value
            } catch { return $Default }
        }
    }

    try {
        $rootSettings = $runSettings.PSObject.Properties[$Key]
        if ($null -eq $rootSettings) { return $Default }
        return $rootSettings.Value
    } catch { return $Default }
}
