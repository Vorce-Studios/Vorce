# SUB-RUN-06_Housekeeping.ps1 (Vorce 3.0)
# Bereinigt abgeschlossene Delegierungen, räumt tmp/ auf und aktualisiert Statistiken
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")

Write-VorceStep -Message "Starte Housekeeping..." -Status "RUN"

# 1. Bereinige abgeschlossene Delegierungen aus active_delegations
if ($ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
    $originalCount = $ConfigBag.GlobalState.active_delegations.Count
    $completedDelegations = @($ConfigBag.GlobalState.active_delegations | Where-Object {
        $_.status -eq "completed" -or $_.status -eq "merged" -or $_.status -eq "closed"
    })
    $remainingDelegations = @($ConfigBag.GlobalState.active_delegations | Where-Object {
        $_.status -ne "completed" -and $_.status -ne "merged" -and $_.status -ne "closed"
    })

    if ($completedDelegations.Count -gt 0) {
        Write-VorceStep -Message "Bereinige $($completedDelegations.Count) abgeschlossene Delegierungen" -Status "INFO"

        # Speichere Bereinigungsinformationen
        $cleanupReport = @{
            timestamp = (Get-Date).ToString("o")
            removed_delegations = @($completedDelegations | ForEach-Object {
                @{
                    issueNumber = $_.issueNumber
                    title = $_.title
                    status = $_.status
                    completedAt = $_.completedAt
                }
            })
        }

        # Speichere Cleanup-Report
        $cleanupDir = Join-Path $global:VarDir "db/completed_delegations"
        if (-not (Test-Path $cleanupDir)) {
            New-Item -ItemType Directory -Path $cleanupDir -Force | Out-Null
        }
        $cleanupReportFile = Join-Path $cleanupDir "cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $cleanupReport | ConvertTo-Json -Depth 10 | Set-Content $cleanupReportFile -Encoding UTF8

        # Aktualisiere active_delegations
        $ConfigBag.GlobalState.active_delegations = $remainingDelegations
        Write-VorceStep -Message "Aktualisiere active_delegations: $originalCount → $($remainingDelegations.Count)" -Status "OK"
    }
}

# 2. Räume var/tmp/ auf (Dateien älter als 24h)
$tmpDir = Join-Path $global:VarDir "tmp"
if (Test-Path $tmpDir) {
    Write-VorceStep -Message "Bereinige var/tmp/ (Dateien älter als 24h)" -Status "INFO"

    $cutoffTime = (Get-Date).AddHours(-24)
    $oldFiles = Get-ChildItem -Path $tmpDir -File | Where-Object { $_.CreationTime -lt $cutoffTime }

    if ($oldFiles.Count -gt 0) {
        foreach ($file in $oldFiles) {
            try {
                Remove-Item $file.FullName -Force
                Write-VorceStep -Message "Gelöscht: $($file.Name)" -Status "INFO"
            } catch {
                Write-VorceStep -Message "Konnte $($file.Name) nicht löschen: $($_.Exception.Message)" -Status "WARN"
            }
        }
    } else {
        Write-VorceStep -Message "Keine alten Dateien in var/tmp/" -Status "INFO"
    }
}

# 3. Aktualisiere Statistiken in global-state.json
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "stats") {
    $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name "stats" -Value @{
        total_runs = 0
        successful_runs = 0
        failed_runs = 0
        total_issues_processed = 0
        total_delegations_created = 0
        last_housekeeping = (Get-Date).ToString("o")
    }
}

# Aktualisiere Statistiken
$ConfigBag.GlobalState.stats.last_housekeeping = (Get-Date).ToString("o")
$ConfigBag.GlobalState.stats.total_runs++

# Aktualisiere andere Statistiken basierend auf aktivitäten
if ($ParentState.reviews) {
    $ConfigBag.GlobalState.stats.total_reviews_dispatched += $ParentState.reviews.Count
}

if ($ParentState.agents) {
    $unhealthyAgents = @($ParentState.agents.Values | Where-Object { $_.status -ne "running" })
    if ($unhealthyAgents.Count -gt 0) {
        $ConfigBag.GlobalState.stats.unhealthy_agent_sessions += $unhealthyAgents.Count
    }
}

# 4. Räume abgelaufene Session Locks auf
$lockDir = Join-Path $global:VarDir "tmp/session.lock"
if (Test-Path $lockDir) {
    $oldLocks = Get-ChildItem -Path $lockDir -File | Where-Object {
        ($_.CreationTime -lt $cutoffTime) -or ($_.Name -like "*.lock")
    }

    if ($oldLocks.Count -gt 0) {
        foreach ($lock in $oldLocks) {
            try {
                Remove-Item $lock.FullName -Force
                Write-VorceStep -Message "Gelöscht: Session Lock $($lock.Name)" -Status "INFO"
            } catch {
                Write-VorceStep -Message "Konnte Session Lock $($lock.Name) nicht löschen: $($_.Exception.Message)" -Status "WARN"
            }
        }
    }
}

# 5. Speichere aktualisierten GlobalState
Save-VorceGlobalState -State $ConfigBag.GlobalState

# 6. Gib State mit Bereinigungsinformationen zurück
$housekeepingResult = @{
    status = "completed"
    cleaned_delegations = $completedDelegations.Count
    tmp_files_cleaned = $oldFiles.Count
    session_locks_cleaned = $oldLocks.Count
    stats_updated = $true
    next_housekeeping = (Get-Date).AddHours(24).ToString("o")
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Housekeeping abgeschlossen: $($housekeepingResult.cleaned_delegations) Delegierungen, $($housekeepingResult.tmp_files_cleaned) tmp-Files bereinigt." -Status "OK"
return $housekeepingResult