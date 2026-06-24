# Vorce-Orchestrator.ps1 (Vorce 3.0)
# Zentrales Steuerungs-Modul fuer die Run-Hierarchie mit dynamischer Scheduling
[CmdletBinding()]
param(
    [object]$GlobalState,
    [switch]$DryRun,
    [ValidateSet(
        "MAIN-RUN-01_Planning",
        "MAIN-RUN-02_CheckAndDoing",
        "MAIN-RUN-03_Audit",
        "MAIN-RUN-04_Optimizer",
        "MAIN-RUN-05_MemoryOptimization"
    )]
    [string]$ForceMainRun,
    [string]$ResumeRunId
)

$global:VorceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$global:VarDir = Join-Path $global:VorceRoot "var"
$global:SrcDir = Join-Path $global:VorceRoot "src"
$global:LibDir = Join-Path $global:SrcDir "lib"

# Fix Encoding for Windows PowerShell
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# A) Module laden (mit neuen Pfaden via $global:LibDir)
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "utils/ProjectManager.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

if ($null -eq $GlobalState) {
    $GlobalState = Read-VorceGlobalState
}

Write-VorceHeader -Title "ORCHESTRATOR ACTIVE" -Icon "🧠" -Color Cyan

# B) Config und Quota laden
$Config = Get-Content (Join-Path $global:VarDir "config/autopilot-config.json") -Raw | ConvertFrom-Json
$QuotaRegistry = Get-Content (Join-Path $global:VarDir "config/quota-registry.json") -Raw | ConvertFrom-Json
$DashboardStatePath = Join-Path $global:VarDir "db/dashboard-state.json"
$DashboardState = if (Test-Path $DashboardStatePath) {
    Get-Content $DashboardStatePath -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{ run_control = [pscustomobject]@{ main_runs = [pscustomobject]@{} } }
}

# C) ConfigBag bauen (W1)
$ConfigBag = @{
    VorceRoot = $global:VorceRoot;
    VarDir = $global:VarDir;
    LibDir = $global:LibDir
    Config = $Config;
    GlobalState = $GlobalState;
    QuotaRegistry = $QuotaRegistry;
    DryRun = $DryRun;
    Timestamp = (Get-Date).ToString("o")
}

$configuredSubRuns = @($Config.router_rules.PSObject.Properties | ForEach-Object { @($_.Value).Count } | Measure-Object -Sum).Sum
Write-VorceStep -Message "Config geladen: $($Config.repository), $configuredSubRuns konfigurierte Sub-Runs" -Status "INFO"

# D) Scheduling-Logik implementieren (C4)
function Select-NextMainRun {
    param([object]$GlobalState, [object]$DashboardState, [object]$Config, [string]$ForceMainRun)
    $runs = @(
        @{ Name="MAIN-RUN-01_Planning"; IntervalKey="planning_minutes" },
        @{ Name="MAIN-RUN-02_CheckAndDoing"; IntervalKey="check_and_doing_minutes" },
        @{ Name="MAIN-RUN-03_Audit"; IntervalKey="audit_minutes" },
        @{ Name="MAIN-RUN-04_Optimizer"; IntervalKey="optimizer_minutes" },
        @{ Name="MAIN-RUN-05_MemoryOptimization"; IntervalKey="memory_optimization_minutes" }
    )
    if ($ForceMainRun) {
        return @{ Name=$ForceMainRun; OverdueMinutes=0; Forced=$true }
    }

    $now = Get-Date
    $best = $null; $bestOverdue = -1
    foreach ($run in $runs) {
        $control = $DashboardState.run_control.main_runs.($run.Name)
        if ($control -and $control.cancel_next) {
            $control.cancel_next = $false
            $control.skipped_at = $now.ToString("o")
            continue
        }
        $interval = [int]$Config.wake_intervals.($run.IntervalKey)
        $lastRun = $null
        if ($GlobalState.last_runs -and $GlobalState.last_runs.PSObject.Properties.Name -contains $run.Name) {
            $lastRun = [datetime]$GlobalState.last_runs.($run.Name)
        }
        $overdue = if ($null -eq $lastRun) { [int]::MaxValue } else { ($now - $lastRun).TotalMinutes - $interval }
        if ($overdue -gt $bestOverdue) { $best = $run; $bestOverdue = $overdue }
    }
    # Nur ausfuehren wenn mindestens ein Run ueberfaellig ist
    if ($bestOverdue -gt 0) {
        return @{ Name=$best.Name; OverdueMinutes=$bestOverdue }
    } else {
        return $null
    }
}

# Waehle dynamisch den naechsten Main-RUN oder setze einen Checkpoint fort.
$RunsDir = Join-Path $global:SrcDir "runs"
$ResumeState = if ($ResumeRunId) { Get-VorceRunStateById -RunId $ResumeRunId -RunType 'MAIN' } else { $null }
if ($ResumeRunId -and -not $ResumeState) {
    throw "Resume-MAIN-State nicht gefunden: $ResumeRunId"
}
if ($ResumeState -and $ResumeState.status -notin @('waiting_provider', 'running')) {
    throw "Run '$ResumeRunId' kann mit Status '$($ResumeState.status)' nicht fortgesetzt werden."
}
$result = if ($ResumeState) {
    @{ Name = $ResumeState.name; OverdueMinutes = 0; Forced = $true; Resume = $true }
} else {
    Select-NextMainRun -GlobalState $GlobalState -DashboardState $DashboardState -Config $Config -ForceMainRun $ForceMainRun
}
if ($null -eq $result) {
    if (-not $DryRun) { Save-VorceGlobalState -State $GlobalState }
    if (-not $DryRun) { $DashboardState | ConvertTo-Json -Depth 10 | Set-Content $DashboardStatePath -Encoding UTF8 }
    Write-VorceStep -Message "Kein Run ueberfaellig." -Status "INFO"
    return
}

$mainRunName = $result.Name
$bestOverdue = $result.OverdueMinutes

# E) Starte Main-Run
Write-VorceRunStart -RunName $mainRunName -Level Main

$scheduleReason = if ($result.Forced) { "manuell ausgeloest" } elseif ($bestOverdue -eq [int]::MaxValue) { "noch nie ausgefuehrt" } else { "ueberfaellig um $([math]::Round($bestOverdue, 1)) Minuten" }
Write-VorceStep -Message "Waehle $mainRunName ($scheduleReason)" -Status "RUN"

# F) Dynamischen Router-Aufruf (C8)
$MainRunPath = Join-Path $RunsDir $mainRunName
$routerFile = Get-ChildItem -Path $MainRunPath -Filter "*-Router.ps1" | Select-Object -First 1

Write-VorceStep -Message "Lade Sub-Runs von Router..." -Status "INFO"

# Initialisiere einen neuen Main-State oder rehydriere denselben unfertigen Run.
$MainState = if ($ResumeState) {
    $ResumeState
} else {
    Initialize-VorceRunState -RunName $mainRunName -RunType "MAIN"
}
if ($ResumeState) {
    $resumeCount = if ($MainState.resume -and $null -ne $MainState.resume.resume_count) { [int]$MainState.resume.resume_count + 1 } else { 1 }
    $MainState.resume = [pscustomobject]@{
        resume_count = $resumeCount
        last_checkpoint_at = (Get-Date).ToString('o')
        retry_after = $null
        blocked_part_run = $null
        reason = 'process_resume'
    }
    $MainState.retry_after = $null
}
$MainState = Set-VorceStateRunning -State $MainState
$MainState = Save-VorceRunState -State $MainState
$reusedSubRuns = @($MainState.results | Where-Object {
    $_.status -in @('completed', 'reused') -and
    @($_.parts).Count -gt 0 -and
    @($_.parts | Where-Object {
        $_.status -notin @('completed', 'reused') -or
        $_.reusable -ne $true -or
        -not (Test-VorceRunResultArtifact -ResultRef ([string]$_.result_ref))
    }).Count -eq 0
} | ForEach-Object {
    if ($_.sub_run) { $_.sub_run } else { $_.name }
})
$ConfigBag.ReusedSubRuns = $reusedSubRuns
$ConfigBag.ResumeRunId = $ResumeRunId
$SubRuns = @()
if ($routerFile) {
    $SubRuns = @(& $routerFile.FullName -ConfigBag $ConfigBag -MainState $MainState)
} else {
    throw "Kein Router fuer $mainRunName gefunden: $MainRunPath"
}

if (-not $DryRun) { Save-VorceRunState -State $MainState | Out-Null }

# F) Try/Catch um jeden Sub-Run (C9)
Write-VorceDivider -Style "double"
Write-VorceStep -Message "GEPLANTER AUSFUEHRUNGSPLAN:" -Status "INFO"
$planIndex = 0
foreach ($sub in $SubRuns) {
    $planIndex++
    $partHint = if ($sub.parts) { "($($sub.parts.Count) Parts)" } else { "" }
    Write-Host "    $planIndex. $($sub.name) $partHint" -ForegroundColor Gray
}
Write-VorceDivider -Style "double"

$subIndex = 0
$startTime = Get-Date
$waitingProviderResult = $null
foreach ($sub in $SubRuns) {
    $subIndex++
    $subStart = Get-Date
    Write-VorceRunStart -RunName $sub.name -Level Sub -Index $subIndex -Total $SubRuns.Count

    try {
        $subScript = Join-Path $global:VorceRoot $sub.script
        if (Test-Path $subScript) {
            $subResult = & $subScript -ConfigBag $ConfigBag -ParentState $MainState
            $existingName = if ($subResult.sub_run) { $subResult.sub_run } elseif ($subResult.name) { $subResult.name } else { $sub.name }
            $MainState.results = @($MainState.results | Where-Object {
                $candidateName = if ($_.sub_run) { $_.sub_run } else { $_.name }
                $candidateName -ne $existingName
            })
            $MainState.results += $subResult
            foreach ($partState in @($subResult.parts)) {
                $MainState = Update-VorceExecutionGraph -MainState $MainState -RunState $partState
            }
            $MainState = Update-VorceExecutionGraph -MainState $MainState -RunState $subResult
            if ($subResult.status -eq 'waiting_provider') {
                $waitingProviderResult = $subResult
                $blockedPart = @($subResult.parts | Where-Object { $_.status -eq 'waiting_provider' } | Select-Object -First 1)
                $retryAfter = if ($blockedPart.Count) { $blockedPart[0].retry_after } else { (Get-Date).AddMinutes(15).ToString('o') }
                $blockedName = if ($blockedPart.Count) { $blockedPart[0].name } else { $sub.name }
                $MainState = Set-VorceStateWaitingProvider -State $MainState -RetryAfter $retryAfter -BlockedPartRun $blockedName
                if (-not $DryRun) { Save-VorceRunState -State $MainState | Out-Null }
                break
            }
            if ($subResult.status -eq "failed") {
                $errorMsg = "Mindestens ein PART-RUN in $($sub.name) ist fehlgeschlagen."
                throw $errorMsg
            }
            $duration = [math]::Round(((Get-Date) - $subStart).TotalSeconds, 1)
            Write-VorceRunEnd -RunName $sub.name -Level Sub -Status "completed" -DurationMs ($duration * 1000)
        } else {
            throw "Sub-Run Skript nicht gefunden: $subScript"
        }
    } catch {
        $duration = [math]::Round(((Get-Date) - $subStart).TotalSeconds, 1)
        Write-VorceRunEnd -RunName $sub.name -Level Sub -Status "failed" -DurationMs ($duration * 1000)
        $MainState.results += @{ name=$sub.name; status="failed"; error=$_.Exception.Message; timestamp=(Get-Date).ToString("o"); duration_sec=$duration }
    }
    if (-not $DryRun) { Save-VorceRunState -State $MainState | Out-Null }
}

# G) Nach Abschluss last_runs Timestamp aktualisieren
if ($waitingProviderResult) {
    Write-VorceStep -Message "$mainRunName wartet auf einen Provider und wurde als Checkpoint gespeichert." -Status "WARN"
    Write-VorceRunEnd -RunName $mainRunName -Level Main -Status "waiting_provider"
    Write-VorceFooter -Message "$mainRunName wartet auf Provider." -Status "waiting_provider"
    return $MainState
}

if ($null -eq $GlobalState.last_runs) {
    $GlobalState | Add-Member -MemberType NoteProperty -Name "last_runs" -Value @{} -Force
}
$GlobalState.last_runs | Add-Member -MemberType NoteProperty -Name $mainRunName -Value (Get-Date).ToString("o") -Force
if (-not $DryRun) { Save-VorceGlobalState -State $GlobalState }
if (-not $DryRun) { $DashboardState | ConvertTo-Json -Depth 10 | Set-Content $DashboardStatePath -Encoding UTF8 }

# 6. Finale Aggregation und Abschluss
Write-VorceDivider
Write-VorceStep -Message "ZUSAMMENFASSUNG $mainRunName" -Status "INFO"
$header = "  $($('Sub-Run').PadRight(30)) | $($('Status').PadRight(12)) | $($('Dauer').PadRight(10)) | Ergebnis"
Write-Host $header -ForegroundColor Yellow
Write-Host "  $('-' * 75)" -ForegroundColor Gray

foreach ($res in $MainState.results) {
    $statusCol = if ($res.status -eq "completed") { "[ OK  ]" } else { "[ ERR ]" }
    $color = if ($res.status -eq "completed") { "Green" } else { "Red" }
    $duration = if ($null -ne $res.duration_sec) { "$($res.duration_sec)s" } else { "-" }
    $msg = if ($res.status -eq "failed") { $res.error } else { "Erfolgreich" }
    
    $rName = if ($res.name) { $res.name } elseif ($res.sub_run) { $res.sub_run } else { "Unknown" }
    $line = "  $($rName.ToString().PadRight(30)) | $($statusCol.PadRight(12)) | $($duration.PadRight(10)) | $msg"
    Write-Host $line -ForegroundColor $color
}
Write-VorceDivider

Write-VorceStep -Message "Fuehre alle Sub-Run Ergebnisse zusammen (Main-Aggregation)..." -Status "RUN"

$failedResults = @($MainState.results | Where-Object { $_.status -eq "failed" })
$MainState = Set-VorceStateStatus -State $MainState -Status $(if ($failedResults.Count -gt 0) { "failed" } else { "completed" })
if (-not $DryRun) { Save-VorceRunState -State $MainState }

# Falls ein Aggregations-Skript existiert (z.B. MAIN-RUN-01_Planning_Aggregate.ps1)
# & ...

Write-VorceStep -Message "Main-Aggregation fuer $mainRunName abgeschlossen." -Status "OK"

# 7. Finaler Sync
Write-VorceStep -Message "Sichere Global State..." -Status "RUN"
if (-not $DryRun) { Save-VorceGlobalState -State $GlobalState }

$footerStatus = if ($MainState.status -eq "completed") { "completed" } else { "failed" }
Write-VorceRunEnd -RunName $mainRunName -Level Main -Status $footerStatus
Write-VorceFooter -Message "$mainRunName abgeschlossen." -Status $footerStatus
