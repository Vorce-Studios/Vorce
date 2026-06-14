# RunEngine.ps1 (Vorce 3.0)
# Modul zur Ausführung von PART-RUNS und SUB-RUNS mit Parallelitäts-Steuerung

function Invoke-VorcePartRun {
    param(
        [Parameter(Mandatory)][string]$PartName,
        [Parameter(Mandatory)][string]$ScriptPath,
        [object]$ParentState = $null,
        [hashtable]$Arguments = @{}
    )
    
    $PartState = Initialize-RunState -RunName $PartName -RunType "PART"
    Write-VorceStep -Message "Führe Part-Run aus: $PartName" -Status "RUN"
    
    try {
        if (-not (Test-Path $ScriptPath)) { throw "Skript nicht gefunden: $ScriptPath" }
        
        # In V3 nutzen wir isolierte Jobs oder ScriptBlocks für Parallelität
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
    } catch {
        $PartState.status = "failed"
        $PartState.metadata["error"] = $_.Exception.Message
        Write-VorceStep -Message "Fehler in Part-Run ${PartName}: $($_.Exception.Message)" -Status "ERROR"
    } finally {
        $PartState.completed_at = (Get-Date).ToString("o")
        # Speichern des Part-States
        $statePath = Join-Path $global:VarDir "run-states/PART_$($PartName).json"
        $PartState | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding UTF8
    }
    
    return $PartState
}

function Invoke-VorceSubRunParallel {
    param(
        [Parameter(Mandatory)][string]$SubRunName,
        [Parameter(Mandatory)][array]$PartRuns,
        [hashtable]$ConfigBag = @{},
        [int]$MaxParallel = 3
    )
    
    Write-VorceStep -Message "Starte parallele Ausführung für $SubRunName ($($PartRuns.Count) Parts, Max: $MaxParallel)" -Status "RUN"
    
    $activeJobs = @()
    $completedResults = @()
    $queue = [System.Collections.Generic.Queue[object]]::new($PartRuns)
    
    while ($queue.Count -gt 0 -or $activeJobs.Count -gt 0) {
        # 1. Fülle Jobs auf, bis MaxParallel erreicht ist
        while ($activeJobs.Count -lt $MaxParallel -and $queue.Count -gt 0) {
            $part = $queue.Dequeue()
            Write-VorceStep -Message "Queue -> Job: $($part.name)" -Status "INFO"
            
            # Starte den Part-Run in einem Hintergrund-Job
            $job = Start-Job -ScriptBlock {
                param($pName, $pScript, $pLibDir, $pVarDir, $pRoot, $pConfigBag)
                # Globale Variablen im Job-Kontext setzen
                $global:VarDir = $pVarDir
                $global:LibDir = $pLibDir
                $global:VorceRoot = $pRoot
                # Libs im Job-Kontext laden
                . (Join-Path $pLibDir "utils/StatusPrinter.ps1")
                . (Join-Path $pLibDir "state/StateManager.ps1")
                . (Join-Path $pLibDir "engines/RunEngine.ps1")
                Invoke-VorcePartRun -PartName $pName -ScriptPath $pScript -Arguments @{ ConfigBag = $pConfigBag }
            } -ArgumentList $part.name, $part.script, $global:LibDir, $global:VarDir, $global:VorceRoot, $ConfigBag
            
            $activeJobs += $job
        }
        
        # 2. Prüfe auf fertige Jobs
        $stillActive = @()
        foreach ($job in $activeJobs) {
            if ($job.State -ne "Running") {
                $jobResult = Receive-Job -Job $job -Wait -ErrorAction SilentlyContinue
                $completedResults += $jobResult
                Remove-Job $job -Force
                Write-VorceStep -Message "Job abgeschlossen: $($job.Name)" -Status "OK"
            } else {
                $stillActive += $job
            }
        }
        $activeJobs = $stillActive
        
        if ($activeJobs.Count -gt 0 -or $queue.Count -gt 0) { Start-Sleep -Milliseconds 500 }
    }
    
    # 3. Aggregations-Logik (Sub-Run Ebene)
    Write-VorceStep -Message "Starte Aggregations-Phase für $SubRunName..." -Status "RUN"
    $failedParts = @($completedResults | Where-Object { $_.status -eq "failed" })

    $aggregatedData = @{
        sub_run = $SubRunName
        status = if ($failedParts.Count -gt 0) { "failed" } else { "completed" }
        timestamp = (Get-Date).ToString("o")
        parts = $completedResults
    }
    
    # Speichere Sub-Run State vorab
    $statePath = Join-Path $global:VarDir "run-states/SUB_$($SubRunName).json"
    $aggregatedData | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding UTF8
    
    # OPTIONAL: Falls ein dediziertes Aggregations-Skript existiert, führe es aus
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

    Write-VorceStep -Message "Starte sequenzielle Ausführung für $SubRunName ($($PartRuns.Count) Parts)" -Status "RUN"
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
    $aggregatedData | ConvertTo-Json -Depth 20 | Set-Content $statePath -Encoding UTF8
    return $aggregatedData
}

# Ende RunEngine
