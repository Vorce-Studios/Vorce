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
        $statePath = Join-Path $PSScriptRoot "../../var/run-states/PART_$($PartName).json"
        $PartState | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding UTF8
    }
    
    return $PartState
}

function Invoke-VorceSubRunParallel {
    param(
        [Parameter(Mandatory)][string]$SubRunName,
        [Parameter(Mandatory)][array]$PartRuns,
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
                param($pName, $pScript, $pLibDir)
                # Libs im Job-Kontext laden
                . (Join-Path $pLibDir "StatusPrinter.ps1")
                . (Join-Path $pLibDir "StateManager.ps1")
                . (Join-Path $pLibDir "RunEngine.ps1")
                
                Invoke-VorcePartRun -PartName $pName -ScriptPath $pScript
            } -ArgumentList $part.name, $part.script, $PSScriptRoot
            
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
    
    $aggregatedData = @{
        sub_run = $SubRunName
        timestamp = (Get-Date).ToString("o")
        parts = $completedResults
    }
    
    # Speichere Sub-Run State vorab
    $statePath = Join-Path $PSScriptRoot "../../var/run-states/SUB_$($SubRunName).json"
    $aggregatedData | ConvertTo-Json -Depth 10 | Set-Content $statePath -Encoding UTF8
    
    # OPTIONAL: Falls ein dediziertes Aggregations-Skript existiert, führe es aus
    # (z.B. SUB-RUN-01_DataSync_Aggregate.ps1)
    
    Write-VorceStep -Message "Sub-Run $SubRunName erfolgreich aggregiert." -Status "OK"
    return $aggregatedData
}

# Ende RunEngine
