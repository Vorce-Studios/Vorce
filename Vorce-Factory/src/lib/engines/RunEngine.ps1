# RunEngine.ps1 (Vorce 3.0)
# Modul zur Ausfuehrung von PART-RUNS und SUB-RUNS mit Parallelitaets-Steuerung


# Dot-Source A2A Client
. (Join-Path $PSScriptRoot "../integrations/A2AClient.ps1")


function Get-VorceStringHash {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [Convert]::ToBase64String($sha.ComputeHash($bytes))
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-VorceCanonicalObject {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            if ($key -in @('timestamp', 'started_at', 'completed_at', 'provider', 'attempt_id', 'session_id')) { continue }
            $ordered[$key] = ConvertTo-VorceCanonicalObject -Value $Value[$key]
        }
        return [pscustomobject]$ordered
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-VorceCanonicalObject -Value $_ })
    }
    $ordered = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
        if ($property.Name -in @('timestamp', 'started_at', 'completed_at', 'provider', 'attempt_id', 'session_id')) { continue }
        $ordered[$property.Name] = ConvertTo-VorceCanonicalObject -Value $property.Value
    }
    return [pscustomobject]$ordered
}

function Get-VorceInputFingerprint {
    param([Parameter(Mandatory)][object]$InputObject)
    $canonical = ConvertTo-VorceCanonicalObject -Value $InputObject
    return Get-VorceStringHash -Text ($canonical | ConvertTo-Json -Depth 30 -Compress)
}

function Test-VorceFinalStateObject {
    param([Parameter(Mandatory)][object]$InputObject)

    if ($null -eq $InputObject) {
        return $false
    }

    $requiredProperties = @(
        'schema_version',
        'id',
        'name',
        'type',
        'status'
    )

    $propertyNames = @($InputObject.PSObject.Properties.Name)
    foreach ($propertyName in $requiredProperties) {
        if ($propertyNames -notcontains $propertyName) {
            return $false
        }
    }

    return $true
}

function Convert-VorceJobOutputItem {
    param([Parameter(Mandatory)][object]$InputObject)

    if ($InputObject -is [System.Management.Automation.InformationRecord]) {
        if ($InputObject.MessageData -is [string]) {
            return [string]$InputObject.MessageData
        }

        if ($null -ne $InputObject.MessageData) {
            return [string]$InputObject.MessageData
        }
    }

    if ($InputObject -is [System.Management.Automation.HostInformationMessage]) {
        return [string]$InputObject.Message
    }

    return [string]$InputObject
}

function New-VorceMissingFinalStateResult {
    param([Parameter(Mandatory)][string]$JobName)

    return [pscustomobject]@{
        name = $JobName
        type = 'PART'
        status = 'failed'
        error_class = 'missing_final_state'
        error = 'missing_final_state'
    }
}

function Invoke-VorcePartRun {
    param(
        [Parameter(Mandatory)][string]$PartName,
        [Parameter(Mandatory)][string]$ScriptPath,
        [object]$ParentState = $null,
        [hashtable]$Arguments = @{},
        [string]$InputFingerprint = $null,
        [object[]]$DependencyResultIds = @(),
        [switch]$ForceRecompute,
        [switch]$SkipExecution = $false
    )

    if (-not $InputFingerprint) {
        $businessArguments = [ordered]@{}
        foreach ($key in @($Arguments.Keys | Sort-Object)) {
            if ([string]$key -in @('ConfigBag', 'ParentState')) { continue }
            $businessArguments[[string]$key] = $Arguments[$key]
        }
        $fingerprintInput = [ordered]@{
            part = $PartName
            script = $ScriptPath
            arguments = $businessArguments
            dependency_result_ids = @($DependencyResultIds)
        }
        $InputFingerprint = Get-VorceInputFingerprint -InputObject $fingerprintInput
    }

    $mainRunId = if ($ParentState -and $ParentState.main_run_id) { [string]$ParentState.main_run_id } elseif ($ParentState) { [string]$ParentState.id } else { '' }
    $parentRunId = if ($ParentState) { [string]$ParentState.id } else { $null }
    $reusable = if ($mainRunId -and -not $ForceRecompute) {
        Get-VorceReusableRunResult -MainRunId $mainRunId -RunName $PartName -InputFingerprint $InputFingerprint -DependencyResultIds $DependencyResultIds
    } else { $null }
    if ($reusable) {
        $reusedState = New-VorceRunStateObject -RunName $PartName -RunType 'PART' -MainRunId $mainRunId -ParentRunId $parentRunId -InputFingerprint $InputFingerprint
        $reusedState.dependency_result_ids = @($DependencyResultIds)
        $reusedState.result_id = $reusable.result_id
        $reusedState.result_ref = $reusable.result_ref
        $reusedState.result_summary = $reusable.result_summary
        $reusedState.results = @($reusable.results)
        $reusedState.attempts = @($reusable.attempts)
        $reusedState = Set-VorceStateReused -State $reusedState
        Save-VorceRunState -State $reusedState | Out-Null
        return $reusedState
    }

    $PartState = Initialize-RunState -RunName $PartName -RunType "PART" -MainRunId $mainRunId -ParentRunId $parentRunId -InputFingerprint $InputFingerprint
    $PartState.dependency_result_ids = @($DependencyResultIds)
    $priorAttemptState = Get-VorcePriorRunAttemptState -MainRunId $mainRunId -RunName $PartName -InputFingerprint $InputFingerprint
    if ($priorAttemptState) { $PartState.attempts = @($priorAttemptState.attempts) }
    $PartState = Set-VorceStateRunning -State $PartState
    $global:MainRunId = if ($ParentState -and $ParentState.main_run_id) { $ParentState.main_run_id } elseif ($ParentState) { $ParentState.id } else { $null }
    Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $PartState.id; name = $PartName; status = "started" } -CorrelationId $global:MainRunId
    Save-VorceRunState -State $PartState | Out-Null
    Write-VorceRunStart -RunName $PartName -Level Part
    Write-VorceStep -Message "Fuehre Part-Run aus: $PartName" -Status "RUN"

    try {
        if (-not (Test-Path $ScriptPath)) { throw "Skript nicht gefunden: $ScriptPath" }

        # In V3 nutzen wir isolierte Jobs oder ScriptBlocks fuer Parallelitaet
        if (-not $SkipExecution) {
            $result = & $ScriptPath @Arguments
            if ($null -ne $result) {
                $hasErrorProperty = if ($result -is [System.Collections.IDictionary]) {
                    $result.Contains("error")
                } else {
                    $result.PSObject.Properties.Name -contains "error"
                }
                $hasError = $hasErrorProperty -and -not [string]::IsNullOrWhiteSpace([string]$result.error)
                if ($result.status -eq "failed" -or ($hasError -and $result.status -ne 'waiting_provider')) {
                    $reason = if ($hasError) { [string]$result.error } else { "PART-RUN meldete Status 'failed'." }
                    throw $reason
                }
            }
        }

        if ($result -and $result.status -eq 'waiting_provider') {
            $PartState.attempts = @($PartState.attempts + @($result.attempts) | Group-Object {
                if ($_.attempt_id) { $_.attempt_id } else { "$($_.provider)|$($_.error_class)|$($_.exit_code)" }
            } | ForEach-Object { $_.Group[0] })
            $PartState.error = $result.error
            $PartState.error_class = $result.error_class
            $PartState = Set-VorceStateWaitingProvider -State $PartState -RetryAfter $result.retry_after -BlockedPartRun $PartName
            $PartState.results = @($result)
            Write-VorceRunEnd -RunName $PartName -Level Part -Status "waiting_provider"
            Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $PartState.id; name = $PartName; status = "waiting_provider" } -CorrelationId $global:MainRunId

        } else {
            $PartState = Set-VorceStateStatus -State $PartState -Status "completed"
            if ($result) {
                $PartState.results += $result
                if ($result.PSObject.Properties.Name -contains 'attempts') {
                    $PartState.attempts = @($PartState.attempts + @($result.attempts) | Group-Object {
                        if ($_.attempt_id) { $_.attempt_id } else { "$($_.provider)|$($_.error_class)|$($_.exit_code)" }
                    } | ForEach-Object { $_.Group[0] })
                }
                if ($result.PSObject.Properties.Name -contains 'summary') { $PartState.result_summary = [string]$result.summary }
            }
            $PartState = Save-VorceRunResultArtifact -State $PartState -Result $result
            $PartState.reusable = $true
            Write-VorceStep -Message "Part-Run $PartName abgeschlossen." -Status "OK"
            Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $PartState.id; name = $PartName; status = "completed" } -CorrelationId $global:MainRunId

            Write-VorceRunEnd -RunName $PartName -Level Part -Status "completed"
        }
    } catch {
        $PartState = Set-VorceStateStatus -State $PartState -Status "failed" -Error $_.Exception.Message -ErrorClass "execution_error"
        Write-VorceStep -Message "Fehler in Part-Run ${PartName}: $($_.Exception.Message)" -Status "ERROR"
        Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $PartState.id; name = $PartName; status = "failed" } -CorrelationId $global:MainRunId

        Write-VorceRunEnd -RunName $PartName -Level Part -Status "failed"
    }

    Save-VorceRunState -State $PartState | Out-Null

    return $PartState
}

function Invoke-VorceSubRunParallel {
    param(
        [Parameter(Mandatory)][string]$SubRunName,
        [Parameter(Mandatory)][array]$PartRuns,
        [object]$ParentState = $null,
        [hashtable]$ConfigBag = @{},
        [int]$MaxParallel = 3,
        [scriptblock]$JobFactory = $null
    )

    $subSettings = if ($ConfigBag.Config -and $ConfigBag.Config.run_settings -and $ConfigBag.Config.run_settings.sub_runs) { $ConfigBag.Config.run_settings.sub_runs.($SubRunName) } else { $null }
    if ($subSettings -and $subSettings.max_parallel -gt 0) {
        $MaxParallel = [int]$subSettings.max_parallel
    }
    $PartRuns = @($PartRuns | Where-Object {
        $partSettings = if ($ConfigBag.Config -and $ConfigBag.Config.run_settings -and $ConfigBag.Config.run_settings.part_runs) { $ConfigBag.Config.run_settings.part_runs.($_.name) } else { $null }
        $null -eq $partSettings -or $partSettings.enabled -ne $false
    })

    Write-VorceStep -Message "Starte parallele Ausfuehrung fuer $SubRunName ($($PartRuns.Count) Parts, Max: $MaxParallel)" -Status "RUN"

    $subState = Initialize-RunState -RunName $SubRunName -RunType "SUB" -MainRunId $ParentState.main_run_id -ParentRunId $ParentState.id
    $subState = Set-VorceStateRunning -State $subState
    Save-VorceRunState -State $subState | Out-Null
    Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $subState.id; name = $SubRunName; status = "started" } -CorrelationId $ParentState.main_run_id
    Write-VorceRunStart -RunName $SubRunName -Level Sub

    $activeJobs = @()
    $completedResults = @()
    $queue = [System.Collections.Generic.Queue[object]]::new($PartRuns)
    $spinChars = @("|", "/", "-", "\")
    $spinIdx = 0

    if (-not $JobFactory) {
        $JobFactory = {
            param($part, $pConfigBag, $pParentState, $pLibDir, $pVarDir, $pRoot)
            Start-Job -ScriptBlock {
                param($pName, $pScript, $pLibDir, $pVarDir, $pRoot, $pConfigBag, $pParentState, $pFingerprint, $pDependencies)
                $global:VarDir = $pVarDir
                $global:LibDir = $pLibDir
                $global:VorceRoot = $pRoot
                . (Join-Path $pLibDir "utils/StatusPrinter.ps1")
                . (Join-Path $pLibDir "state/StateManager.ps1")
                . (Join-Path $pLibDir "engines/RunEngine.ps1")
                Invoke-VorcePartRun -PartName $pName -ScriptPath $pScript -ParentState $pParentState -Arguments @{ ConfigBag = $pConfigBag } -InputFingerprint $pFingerprint -DependencyResultIds @($pDependencies)
            } -ArgumentList $part.name, $part.script, $pLibDir, $pVarDir, $pRoot, $pConfigBag, $pParentState, $part.input_fingerprint, @($part.dependency_result_ids) -Name $part.name
        }
    }

    while ($queue.Count -gt 0 -or $activeJobs.Count -gt 0) {
        # 1. Fuelle Jobs auf, bis MaxParallel erreicht ist
        while ($activeJobs.Count -lt $MaxParallel -and $queue.Count -gt 0) {
            $part = $queue.Dequeue()
            Write-VorceStep -Message "Queue -> Job: $($part.name)" -Status "INFO"

            $job = & $JobFactory $part $ConfigBag $subState $global:LibDir $global:VarDir $global:VorceRoot

            $activeJobs += $job
        }

        # 2. Pruefe auf fertige Jobs und sammle Output erst nach Jobende genau einmal
        $stillActive = @()
        foreach ($job in $activeJobs) {
            if ($job.State -eq "Running") {
                $stillActive += $job
                continue
            }

            $jobOutput = @()
            try {
                $jobOutput = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
            } catch {
                $jobOutput = @()
            }

            $finalState = $null
            foreach ($item in $jobOutput) {
                if ($null -eq $item) {
                    continue
                }
                if (Test-VorceFinalStateObject -InputObject $item) {
                    if (-not $finalState) {
                        $finalState = $item
                    }
                    continue
                }

                $rendered = Convert-VorceJobOutputItem -InputObject $item
                if (-not [string]::IsNullOrWhiteSpace($rendered)) {
                    Write-Host "    [$($job.Name)] $rendered" -ForegroundColor Gray
                }
            }

            if ($finalState) {
                $completedResults += $finalState
                $statusIcon = if ($finalState.status -eq "completed") { "OK" } else { "ERROR" }
                Write-VorceStep -Message "Job abgeschlossen: $($job.Name)" -Status $statusIcon
            } else {
                $errorMsg = if ($job.ChildJobs.Count -gt 0 -and $job.ChildJobs[0].JobStateInfo.Reason) { $job.ChildJobs[0].JobStateInfo.Reason.Message } else { "Kein finales State-Objekt empfangen." }
                Write-VorceStep -Message "Job abgeschlossen: $($job.Name) (missing_final_state)" -Status "ERROR"
                $completedResults += [pscustomobject]@{
                    name = $job.Name
                    type = 'PART'
                    status = 'failed'
                    error_class = 'missing_final_state'
                    error = 'missing_final_state'
                    job_error = $errorMsg
                }
            }

            Remove-Job $job -Force
        }
        $activeJobs = $stillActive

        if ($activeJobs.Count -gt 0 -or $queue.Count -gt 0) {
            $spinIdx = ($spinIdx + 1) % $spinChars.Count
            $char = $spinChars[$spinIdx]
            $msg = "  $char [$($activeJobs.Count) aktive Jobs, $($queue.Count) in Warteschlange]      "
            Write-Host -NoNewline "`r$msg"
            Start-Sleep -Milliseconds 250
        }
    }
    Write-Host "`r" # Clear Spinner line

    # 3. Aggregations-Logik (Sub-Run Ebene)
    Write-VorceStep -Message "Starte Aggregations-Phase fuer $SubRunName..." -Status "RUN"
    $failedParts = @($completedResults | Where-Object { $_.status -eq "failed" })
    $waitingParts = @($completedResults | Where-Object { $_.status -eq "waiting_provider" })

    $subState = if ($waitingParts.Count -gt 0) {
        Set-VorceStateWaitingProvider -State $subState -RetryAfter $waitingParts[0].retry_after -BlockedPartRun $waitingParts[0].name
    } else {
        Set-VorceStateStatus -State $subState -Status $(if ($failedParts.Count -gt 0) { "failed" } else { "completed" })
    }
    $subState.results = @($completedResults)
    $subState.parts = @($completedResults)
    if ($subState.status -eq 'completed') {
        $subState = Save-VorceRunResultArtifact -State $subState -Result @($completedResults)
        $subState.reusable = @($completedResults | Where-Object { $_.status -notin @('completed', 'reused') -or $_.reusable -ne $true }).Count -eq 0
    }

    Save-VorceRunState -State $subState | Out-Null
    Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $subState.id; name = $SubRunName; status = $subState.status } -CorrelationId $ParentState.main_run_id
    Write-VorceRunEnd -RunName $SubRunName -Level Sub -Status $subState.status

    if ($failedParts.Count -gt 0) {
        Write-VorceStep -Message "Sub-Run $SubRunName mit $($failedParts.Count) fehlgeschlagenen PART-RUNs aggregiert." -Status "ERROR"
    } else {
        Write-VorceStep -Message "Sub-Run $SubRunName erfolgreich aggregiert." -Status "OK"
    }
    return @{
        id = $subState.id
        main_run_id = $subState.main_run_id
        parent_run_id = $subState.parent_run_id
        name = $SubRunName
        type = 'SUB'
        sub_run = $SubRunName
        status = $subState.status
        started_at = $subState.started_at
        completed_at = $subState.completed_at
        duration_ms = $subState.duration_ms
        timestamp = (Get-Date).ToString("o")
        parts = $completedResults
        result_id = $subState.result_id
        result_ref = $subState.result_ref
        reusable = $subState.reusable
        attempts = @($completedResults | ForEach-Object { @($_.attempts) })
    }
}

function Invoke-VorceSubRunSequential {
    param(
        [Parameter(Mandatory)][string]$SubRunName,
        [Parameter(Mandatory)][array]$PartRuns,
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [Parameter(Mandatory)][object]$ParentState
    )

    $PartRuns = @($PartRuns | Where-Object {
        $partSettings = if ($ConfigBag.Config -and $ConfigBag.Config.run_settings -and $ConfigBag.Config.run_settings.part_runs) { $ConfigBag.Config.run_settings.part_runs.($_.name) } else { $null }
        $null -eq $partSettings -or $partSettings.enabled -ne $false
    })

    Write-VorceStep -Message "Starte sequenzielle Ausfuehrung fuer $SubRunName ($($PartRuns.Count) Parts)" -Status "RUN"

    $subState = Initialize-RunState -RunName $SubRunName -RunType "SUB" -MainRunId $ParentState.main_run_id -ParentRunId $ParentState.id
    $subState = Set-VorceStateRunning -State $subState
    Save-VorceRunState -State $subState | Out-Null
    Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $subState.id; name = $SubRunName; status = "started" } -CorrelationId $ParentState.main_run_id
    Write-VorceRunStart -RunName $SubRunName -Level Sub

    $partStates = @()
    foreach ($part in $PartRuns) {
        $arguments = @{
            ConfigBag = $ConfigBag
            ParentState = $subState
        }
        if ($part.ContainsKey("arguments")) {
            foreach ($key in $part.arguments.Keys) {
                $arguments[$key] = $part.arguments[$key]
            }
        }
        $dependencyIds = if ($part.ContainsKey('dependency_result_ids')) { @($part.dependency_result_ids) } else { @() }
        $fingerprint = if ($part.ContainsKey('input_fingerprint')) { [string]$part.input_fingerprint } else { $null }

        $partStates += Invoke-VorcePartRun `
            -PartName $part.name `
            -ScriptPath $part.script `
            -ParentState $subState `
            -Arguments $arguments `
            -InputFingerprint $fingerprint `
            -DependencyResultIds $dependencyIds
        if ($partStates[-1].status -eq 'waiting_provider') { break }
    }

    $failed = @($partStates | Where-Object { $_.status -eq "failed" })
    $waiting = @($partStates | Where-Object { $_.status -eq "waiting_provider" })
    $subState = if ($waiting.Count -gt 0) {
        Set-VorceStateWaitingProvider -State $subState -RetryAfter $waiting[0].retry_after -BlockedPartRun $waiting[0].name
    } else {
        Set-VorceStateStatus -State $subState -Status $(if ($failed.Count -gt 0) { "failed" } else { "completed" })
    }
    $subState.results = @($partStates)
    $subState.parts = @($partStates)
    if ($subState.status -eq 'completed') {
        $subState = Save-VorceRunResultArtifact -State $subState -Result @($partStates)
        $subState.reusable = @($partStates | Where-Object { $_.status -notin @('completed', 'reused') -or $_.reusable -ne $true }).Count -eq 0
    }

    Save-VorceRunState -State $subState | Out-Null
    Send-VorceA2AMessage -TargetAgent "Dashboard" -MessageType "TaskProgress" -Payload @{ runId = $subState.id; name = $SubRunName; status = $subState.status } -CorrelationId $ParentState.main_run_id
    Write-VorceRunEnd -RunName $SubRunName -Level Sub -Status $subState.status

    return @{
        id = $subState.id
        main_run_id = $subState.main_run_id
        parent_run_id = $subState.parent_run_id
        name = $SubRunName
        type = 'SUB'
        sub_run = $SubRunName
        status = $subState.status
        timestamp = (Get-Date).ToString("o")
        parts = $partStates
        result_id = $subState.result_id
        result_ref = $subState.result_ref
        reusable = $subState.reusable
        attempts = @($partStates | ForEach-Object { @($_.attempts) })
    }
}

# Ende RunEngine
