# SUB-RUN-01_MR-05_MemoryOptimization__MemoryMaintenance.ps1 (Vorce 3.0)
# Vorce-Factory Memories prüfen/bereinigen/optimieren für Token-Effizienz
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

Write-VorceStep -Message "Starte Memory-Maintenance..." -Status "RUN"

# Erstelle Memory-Maintenance Ordner
$maintenanceDir = Join-Path $global:VarDir "memory-maintenance"
if (-not (Test-Path $maintenanceDir)) {
    New-Item -ItemType Directory -Path $maintenanceDir -Force | Out-Null
}

# 1. Lade Vorce-Factory Memories
$memoryPath = Join-Path $global:VarDir "db/autopilot-memories.json"
if (Test-Path $memoryPath) {
    try {
        $memoryStore = Get-Content $memoryPath -Raw | ConvertFrom-Json
        $memories = if ($memoryStore.PSObject.Properties.Name -contains "memories") { @($memoryStore.memories) } else { @($memoryStore) }
    } catch {
        $memories = @()
        Write-VorceStep -Message "Fehler beim Laden von Vorce-Factory Memories: $($_.Exception.Message)" -Status "ERROR"
    }
} else {
    $memories = @()
    Write-VorceStep -Message "Keine Vorce-Factory Memories gefunden" -Status "INFO"
}

# 2. Analysiere Memory-Nutzung
$memoryAnalysis = @{
    analysis_timestamp = (Get-Date).ToString("o")
    total_memories = $memories.Count
    memory_by_type = @{}
    memory_by_priority = @{}
    memory_by_age = @{
        recent = @() # < 24h
        medium = @() # 24h - 7d
        old = @()    # > 7d
    }
    memory_by_source = @{}
    orphaned_memories = @()
    unused_memories = @()
    low_quality_memories = @()
}

# Kategorisiere Memories
$cutoff24h = (Get-Date).AddHours(-24)
$cutoff7d = (Get-Date).AddDays(-7)

foreach ($memory in $memories) {
    # Nach Typ gruppieren
    $type = $(if ($null -ne $memory.type) { $memory.type } else { "unknown" })
    if (-not $memoryAnalysis.memory_by_type[$type]) {
        $memoryAnalysis.memory_by_type[$type] = @()
    }
    $memoryAnalysis.memory_by_type[$type] += $memory

    # Nach Priorität gruppieren
    $priority = $(if ($null -ne $memory.priority) { $memory.priority } else { "medium" })
    if (-not $memoryAnalysis.memory_by_priority[$priority]) {
        $memoryAnalysis.memory_by_priority[$priority] = @()
    }
    $memoryAnalysis.memory_by_priority[$priority] += $memory

    # Nach Alter gruppieren
    $createdDate = if ($memory.created_at) { [datetime]$memory.created_at } else { [datetime]::MinValue }
    if ($createdDate -gt $cutoff24h) {
        $memoryAnalysis.memory_by_age.recent += $memory
    } elseif ($createdDate -gt $cutoff7d) {
        $memoryAnalysis.memory_by_age.medium += $memory
    } else {
        $memoryAnalysis.memory_by_age.old += $memory
    }

    # Nach Quelle gruppieren
    $source = $(if ($null -ne $memory.source) { $memory.source } else { "unknown" })
    if (-not $memoryAnalysis.memory_by_source[$source]) {
        $memoryAnalysis.memory_by_source[$source] = @()
    }
    $memoryAnalysis.memory_by_source[$source] += $memory

    # Finde verwaiste Memories (keine Zuordnung zu aktiven Prozessen)
    $isOrphaned = $false
    if ($memory.source -match "dashboard_alert_ignore" -and $memory.created_at) {
        $age = (Get-Date) - [datetime]$memory.created_at
        if ($age.TotalDays -gt 30) {
            $memoryAnalysis.orphaned_memories += $memory
            $isOrphaned = $true
        }
    }

    # Finde ungenutzte Memories (keine Referenz in aktiven Delegierungen)
    $isUnused = $false
    if (-not $isOrphaned -and $memory.text -and ($memory.text.Length -gt 500) -and ($memory.priority -eq "low")) {
        $isUnused = $true
        $memoryAnalysis.unused_memories += $memory
    }

    # Finde niedrige Qualität Memories
    $isLowQuality = $false
    if ($memory.text -and ($memory.text.Length -lt 50) -and ($memory.priority -ne "critical")) {
        $isLowQuality = $true
        $memoryAnalysis.low_quality_memories += $memory
    }
}

# 3. Bereinigungsstrategie
$cleanupStrategy = @{
    memories_to_remove = @()
    memories_to_archive = @()
    memories_to_optimize = @()
    cleanup_summary = @{}
}

# Entferne verwaiste Memories
$cleanupStrategy.memories_to_remove += $memoryAnalysis.orphaned_memories
$cleanupStrategy.cleanup_summary.orphaned_removed = $memoryAnalysis.orphaned_memories.Count

# Entferne ungenutzte, alte Memories
$oldUnusedMemories = $memoryAnalysis.unused_memories | Where-Object {
    if ($_.created_at) {
        ([datetime]$_.created_at) -lt $cutoff7d
    }
}
$cleanupStrategy.memories_to_remove += $oldUnusedMemories
$cleanupStrategy.cleanup_summary.unused_removed = $oldUnusedMemories.Count

# Archive niedrige Qualität Memories
$cleanupStrategy.memories_to_archive += $memoryAnalysis.low_quality_memories | Select-Object -First 10
$cleanupStrategy.cleanup_summary.low_quality_archived = ($memoryAnalysis.low_quality_memories | Select-Object -First 10).Count

# Optimiere Memory-Größe
$largeMemories = $memories | Where-Object {
    $_.text -and ($_.text.Length -gt 1000) -and ($_.priority -ne "critical")
}
$cleanupStrategy.memories_to_optimize += $largeMemories
$cleanupStrategy.cleanup_summary.large_memories_optimized = $largeMemories.Count

# 4. Führe Bereinigung durch
$updatedMemories = @($memories)

# Entferne markierte Memories
foreach ($memoryToRemove in $cleanupStrategy.memories_to_remove) {
    $updatedMemories = $updatedMemories | Where-Object { $_.id -ne $memoryToRemove.id }
}

# Archive Memories in separater Datei
if ($cleanupStrategy.memories_to_archive.Count -gt 0) {
    $archivePath = Join-Path $maintenanceDir "memory_archive_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $cleanupStrategy.memories_to_archive | ConvertTo-Json -Depth 5 | Set-Content $archivePath -Encoding UTF8
}

# Optimiere große Memories (Textzusammenfassung)
foreach ($memoryToOptimize in $cleanupStrategy.memories_to_optimize) {
    if ($memoryToOptimize.text.Length -gt 1000) {
        $memoryToOptimize.optimized_summary = $memoryToOptimize.text.Substring(0, 500) + "... [gekürzt aus Effizienzgründen]"
        $memoryToOptimize | Add-Member -MemberType NoteProperty -Name "optimized_at" -Value (Get-Date).ToString("o") -Force
    }
}

# 5. Bereinigte Memories speichern
[pscustomobject]@{ schema_version = 1; memories = @($updatedMemories) } |
    ConvertTo-Json -Depth 10 |
    Set-Content $memoryPath -Encoding UTF8

# 6. Erstelle Memory-Maintenance Bericht
$maintenanceReport = @{
    maintenance_timestamp = (Get-Date).ToString("o")
    analysis_results = $memoryAnalysis
    cleanup_strategy = $cleanupStrategy
    maintenance_actions = @()
    memory_efficiency_improvement = 0
    token_savings_estimated = 0
}

# Dokumentiere Aktionen
$maintenanceReport.cleanup_strategy.cleanup_summary.removed_total = $cleanupStrategy.memories_to_remove.Count
$maintenanceReport.cleanup_strategy.cleanup_summary.archived_total = $cleanupStrategy.memories_to_archive.Count
$maintenanceReport.cleanup_strategy.cleanup_summary.optimized_total = $cleanupStrategy.memories_to_optimize.Count

# Schätze Token-Einsparungen
$originalTokens = $memories | ForEach-Object { if ($_.text) { $_.text.Length } else { 0 } } | Measure-Object -Sum
$updatedTokens = $updatedMemories | ForEach-Object { if ($_.text) { $_.text.Length } else { 0 } } | Measure-Object -Sum

$maintenanceReport.memory_efficiency_improvement = if ($originalTokens.Sum -gt 0) { [math]::Round(($originalTokens.Sum - $updatedTokens.Sum) / $originalTokens.Sum * 100, 2) } else { 0 }
$maintenanceReport.token_savings_estimated = $originalTokens.Sum - $updatedTokens.Sum

$maintenanceReport.maintenance_actions += @{
    action = "cleanup_orphaned"
    count = $cleanupStrategy.memories_to_remove.Count
    description = "Entfernte verwaiste Memories (>30 Tage alt)"
}

$maintenanceReport.maintenance_actions += @{
    action = "archive_low_quality"
    count = $cleanupStrategy.memories_to_archive.Count
    description = "Archivierte niedrige Qualität Memories"
}

$maintenanceReport.maintenance_actions += @{
    action = "optimize_large_memories"
    count = $cleanupStrategy.memories_to_optimize.Count
    description = "Optimierte große Memories durch Zusammenfassung"
}

# 7. Speichere Maintenance-Bericht
$maintenanceReportFile = Join-Path $maintenanceDir "maintenance_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$maintenanceReport | ConvertTo-Json -Depth 10 | Set-Content $maintenanceReportFile -Encoding UTF8

# 8. Aktualisiere ParentState
if (-not $ParentState.memory_maintenance) {
    $ParentState | Add-Member -MemberType NoteProperty -Name "memory_maintenance" -Value @{} -Force
}
$ParentState.memory_maintenance = $maintenanceReport

$memoryMaintenanceResult = @{
    status = "completed"
    original_memory_count = $memories.Count
    cleaned_memory_count = $updatedMemories.Count
    memories_removed = $cleanupStrategy.memories_to_remove.Count
    memories_archived = $cleanupStrategy.memories_to_archive.Count
    memories_optimized = $cleanupStrategy.memories_to_optimize.Count
    token_savings_estimated = $maintenanceReport.token_savings_estimated
    efficiency_improvement_percent = $maintenanceReport.memory_efficiency_improvement
    maintenance_report = $maintenanceReportFile
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Memory-Maintenance abgeschlossen: $($memoryMaintenanceResult.memories_removed) entfernt, $($memoryMaintenanceResult.memories_optimized) optimiert, $($memoryMaintenanceResult.token_savings_estimated) Tokens eingespart" -Status "OK"
return $memoryMaintenanceResult
