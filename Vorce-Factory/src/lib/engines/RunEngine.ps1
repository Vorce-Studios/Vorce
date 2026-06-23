# RunEngine.ps1 (Vorce 3.0)
# Modul zur Ausfuehrung von PART-RUNS und SUB-RUNS mit Parallelitaets-Steuerung

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
        [string]$InputFingerprint = $null
    )

    if (-not $InputFingerprint) {
        $fingerprintInput = [ordered]@{
            part = $PartName
            script = $ScriptPath
            parent = if ($ParentState) { $ParentState.id } else { '' }
            arguments = $Arguments
        }
        $InputFingerprint = Get-VorceStringHash -Text (($fingerprintInput | ConvertTo-Json -Depth 10 -Compress))
    }

    $mainRunId = if ($ParentState -and $ParentState.main_run_id) { [string]$ParentState.main_run_id } else { '' }
    $parentRunId = if ($ParentState) { [string]$ParentState.id } else { $null }
    $reusable = if ($mainRunId) { Get-VorceReusableRunResult -MainRunId $mainRunId -RunName $PartName -InputFingerprint $InputFingerprint } else { $null }
    if ($reusable) {
        return [pscustomobject]@{
            schema_version = 2
            id = $reusable.id
            main_run_id = $reusable.main_run_id
            parent_run_id = $reusable.parent_run_id
            name = $PartName
            type = 'PART'
            status = 'reused'
            started_at = $reusable.started_at
            completed_at = $reusable.completed_at
            duration_ms = $reusable.duration_ms
            input_fingerprint = $InputFingerprint
            metadata = $reusable.metadata
            results = @($reusable.results)
            reusable = $true
        }
    }

    $PartState = Initialize-RunState -RunName $PartName -RunType "PART" -MainRunId $mainRunId -ParentRunId $parentRunId -InputFingerprint $InputFingerprint
    Write-VorceRunStart -RunName $PartName -Level Part
    Write-VorceStep -Message "Fuehre Part-Run aus: $PartName" -Status "RUN"

    try {
        if (-not (Test-Path $ScriptPath)) { throw "Skript nicht gefunden: $ScriptPath" }

        # In V3 nutzen wir isolierte Jobs oder ScriptBlocks fuer Parallelitaet
        $result = & $ScriptPath @Arguments
        if ($null -ne $result) {
            $hasErrorProperty = if ($result -is [System.Collections.IDictionary]) {
                $result.Contains("error")
            } else {
                $result.PSObject.Properties.Name -contains "error"
            }
            $hasError = $hasErrorProperty -and -not [string]::IsNullOrWhiteSpace([string]$result.error)
            if ($result.status -eq "failed" -or $hasError) {
                $reason = if ($hasError) { [string]$result.error } else { "PART-RUN meldete Status 'failed'." }
                throw $reason
            }
        }
        
        $PartState.status = "completed"
        $PartState.results += $result
        Write-VorceStep -Message "Part-Run $PartName abgeschlossen." -Status "OK"
        Write-VorceRunEnd -RunName $PartName -Level Part -Status "completed"
    } catch {
        $PartState.status = "failed"
        $PartState.metadata["error"] = $_.Exception.Message
        Write-VorceStep -Message "Fehler in Part-Run ${PartName}: $($_.Exception.Message)" -Status "ERROR"
        Write-VorceRunEnd -RunName $PartName -Level Part -Status "failed"
    } finally {
        $PartState.completed_at = (Get-Date).ToString("o")
        if ($PartState.started_at -and $PartState.completed_at) {
            $PartState.duration_ms = [int]((New-TimeSpan -Start ([datetime]$PartState.started_at) -End ([datetime]$PartState.completed_at)).TotalMilliseconds)
        }
        # Speichern des Part-States
        $statePath = Join-Path $global:VarDir "run-states/PART_$($PartName).json"
        Ensure-VorceParentDirectory -Path $statePath
        $PartState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
        Save-VorceRunState -State $PartState | Out-Null
    }
    
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
    
    $subSettings = $ConfigBag.Config.run_settings.sub_runs.($SubRunName)
    if ($subSettings -and $subSettings.max_parallel -gt 0) {
        $MaxParallel = [int]$subSettings.max_parallel
    }
    $PartRuns = @($PartRuns | Where-Object {
        $partSettings = $ConfigBag.Config.run_settings.part_runs.($_.name)
        $null -eq $partSettings -or $partSettings.enabled -ne $false
    })

    Write-VorceStep -Message "Starte parallele Ausfuehrung fuer $SubRunName ($($PartRuns.Count) Parts, Max: $MaxParallel)" -Status "RUN"
    
    $activeJobs = @()
    $completedResults = @()
    $queue = [System.Collections.Generic.Queue[object]]::new($PartRuns)
    $spinChars = @("|", "/", "-", "\")
    $spinIdx = 0

    if (-not $JobFactory) {
        $JobFactory = {
            param($part, $pConfigBag, $pParentState, $pLibDir, $pVarDir, $pRoot)
            Start-Job -ScriptBlock {
                param($pName, $pScript, $pLibDir, $pVarDir, $pRoot, $pConfigBag, $pParentState)
                $global:VarDir = $pVarDir
                $global:LibDir = $pLibDir
                $global:VorceRoot = $pRoot
                . (Join-Path $pLibDir "utils/StatusPrinter.ps1")
                . (Join-Path $pLibDir "state/StateManager.ps1")
                . (Join-Path $pLibDir "engines/RunEngine.ps1")
                Invoke-VorcePartRun -PartName $pName -ScriptPath $pScript -ParentState $pParentState -Arguments @{ ConfigBag = $pConfigBag }
            } -ArgumentList $part.name, $part.script, $pLibDir, $pVarDir, $pRoot, $pConfigBag, $pParentState -Name $part.name
        }
    }

    while ($queue.Count -gt 0 -or $activeJobs.Count -gt 0) {
        # 1. Fuelle Jobs auf, bis MaxParallel erreicht ist
        while ($activeJobs.Count -lt $MaxParallel -and $queue.Count -gt 0) {
            $part = $queue.Dequeue()
            Write-VorceStep -Message "Queue -> Job: $($part.name)" -Status "INFO"

            $job = & $JobFactory $part $ConfigBag $ParentState $global:LibDir $global:VarDir $global:VorceRoot

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

    $aggregatedData = @{
        sub_run = $SubRunName
        status = if ($failedParts.Count -gt 0) { "failed" } else { "completed" }
        timestamp = (Get-Date).ToString("o")
        parts = $completedResults
    }
    
    # Speichere Sub-Run State vorab
    $statePath = Join-Path $global:VarDir "run-states/SUB_$($SubRunName).json"
    Ensure-VorceParentDirectory -Path $statePath
    $aggregatedData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Save-VorceRunState -State ([pscustomobject]@{
        schema_version = 2
        id = [guid]::NewGuid().ToString('N')
        main_run_id = if ($ParentState -and $ParentState.main_run_id) { $ParentState.main_run_id } elseif ($ParentState) { $ParentState.id } else { $null }
        parent_run_id = if ($ParentState) { $ParentState.id } else { $null }
        name = $SubRunName
        type = 'SUB'
        status = $aggregatedData.status
        started_at = if ($ParentState -and $ParentState.started_at) { $ParentState.started_at } else { (Get-Date).ToString("o") }
        completed_at = (Get-Date).ToString("o")
        duration_ms = $null
        input_fingerprint = $null
        metadata = @{}
        results = @($completedResults)
    }) | Out-Null
    
    # OPTIONAL: Falls ein dediziertes Aggregations-Skript existiert, fuehre es aus
    # (z.B. SUB-RUN-01_DataSync_Aggregate.ps1)
    
    if ($failedParts.Count -gt 0) {
        Write-VorceStep -Message "Sub-Run $SubRunName mit $($failedParts.Count) fehlgeschlagenen PART-RUNs aggregiert." -Status "ERROR"
    } else {
        Write-VorceStep -Message "Sub-Run $SubRunName erfolgreich aggregiert." -Status "OK"
    }
    return $aggregatedData
}

function Invoke-VorceSubRunSequential {
    param(
        [Parameter(Mandatory)][string]$SubRunName,
        [Parameter(Mandatory)][array]$PartRuns,
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [Parameter(Mandatory)][object]$ParentState
    )

    $PartRuns = @($PartRuns | Where-Object {
        $partSettings = $ConfigBag.Config.run_settings.part_runs.($_.name)
        $null -eq $partSettings -or $partSettings.enabled -ne $false
    })

    Write-VorceStep -Message "Starte sequenzielle Ausfuehrung fuer $SubRunName ($($PartRuns.Count) Parts)" -Status "RUN"
    $partStates = @()

    foreach ($part in $PartRuns) {
        $arguments = @{
            ConfigBag = $ConfigBag
            ParentState = $ParentState
        }
        if ($part.ContainsKey("arguments")) {
            foreach ($key in $part.arguments.Keys) {
                $arguments[$key] = $part.arguments[$key]
            }
        }

        $partStates += Invoke-VorcePartRun `
            -PartName $part.name `
            -ScriptPath $part.script `
            -ParentState $ParentState `
            -Arguments $arguments
    }

    $failed = @($partStates | Where-Object { $_.status -eq "failed" })
    $aggregatedData = @{
        sub_run = $SubRunName
        status = if ($failed.Count -gt 0) { "failed" } else { "completed" }
        timestamp = (Get-Date).ToString("o")
        parts = $partStates
    }

    $statePath = Join-Path $global:VarDir "run-states/SUB_$($SubRunName).json"
    Ensure-VorceParentDirectory -Path $statePath
    $aggregatedData | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Save-VorceRunState -State ([pscustomobject]@{
        schema_version = 2
        id = [guid]::NewGuid().ToString('N')
        main_run_id = if ($ParentState -and $ParentState.main_run_id) { $ParentState.main_run_id } elseif ($ParentState) { $ParentState.id } else { $null }
        parent_run_id = if ($ParentState) { $ParentState.id } else { $null }
        name = $SubRunName
        type = 'SUB'
        status = $aggregatedData.status
        started_at = if ($ParentState -and $ParentState.started_at) { $ParentState.started_at } else { (Get-Date).ToString("o") }
        completed_at = (Get-Date).ToString("o")
        duration_ms = $null
        input_fingerprint = $null
        metadata = @{}
        results = @($partStates)
    }) | Out-Null
    return $aggregatedData
}

# Ende RunEngine
