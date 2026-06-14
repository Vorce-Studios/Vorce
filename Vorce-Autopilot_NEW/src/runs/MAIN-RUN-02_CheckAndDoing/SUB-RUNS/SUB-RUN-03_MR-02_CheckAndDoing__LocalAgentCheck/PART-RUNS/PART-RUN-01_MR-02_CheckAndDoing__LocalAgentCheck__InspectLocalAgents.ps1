# SUB-RUN-03_LocalAgentCheck.ps1 (Vorce 3.0)
# Prüft laufende lokale Agent-Prozesse und deren Status
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

Write-VorceStep -Message "Starte LocalAgentCheck..." -Status "RUN"

# 1. Prüfe laufende lokale Agent-Prozesse
$agentPatterns = @("claude", "gemini", "cline")
$agentProcesses = @{}
$processIssues = @()

foreach ($pattern in $agentPatterns) {
    try {
        $processes = Get-Process -Name $pattern -ErrorAction SilentlyContinue
        if ($processes) {
            $agentProcesses[$pattern] = $processes
            Write-VorceStep -Message "Gefunden $($processes.Count) '$pattern' Prozesse" -Status "INFO"

            foreach ($process in $processes) {
                $health = @{
                    name = $process.ProcessName
                    id = $process.Id
                    cpu = $process.CPU
                    memory = $process.WorkingSet64
                    startTime = if ($process.StartTime) { $process.StartTime.ToString("o") } else { "unknown" }
                    status = "running"
                    exitCode = $null
                    error = $null
                }

                # Prüfe ob Prozess "hanging" ist (CPU > 80% Memory > 4GB seit > 10min)
                if ($process.CPU -gt 80 -and $process.WorkingSet64 -gt 4GB) {
                    $runningTime = (Get-Date) - $process.StartTime
                    if ($runningTime.TotalMinutes -gt 10) {
                        $health.status = "hanging"
                        $health.error = "Hanging process detected (high CPU/Memory)"
                        $processIssues += $health
                    }
                }

                # Speichere Health-Informationen in ParentState
                if (-not $ParentState.agents) {
                    $ParentState | Add-Member -MemberType NoteProperty -Name "agents" -Value @{} -Force
                }
                $ParentState.agents[$process.Id] = $health
            }
        }
    } catch {
        $issue = @{
            name = $pattern
            error = "Process enumeration failed: $($_.Exception.Message)"
            status = "error"
        }
        $processIssues += $issue
        Write-VorceStep -Message "Fehler bei '$pattern' Prozess-Enumeration: $($_.Exception.Message)" -Status "ERROR"
    }
}

# 2. Aktualisiere GlobalState mit Agent-Informationen
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "agent_health") {
    $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name "agent_health" -Value @{} -Force
}
$ConfigBag.GlobalState.agent_health.timestamp = (Get-Date).ToString("o")
$ConfigBag.GlobalState.agent_health.processes = $agentProcesses
$ConfigBag.GlobalState.agent_health.issues = $processIssues

# 3. Prüfe ob lokale Agent-Sessions laufen
$localSessions = $agentProcesses.Count
if ($localSessions -eq 0) {
    Write-VorceStep -Message "Keine lokalen Agent-Sessions gefunden" -Status "INFO"
    return @{ status="no_local_sessions"; processes=@{}; issues=@(); timestamp=(Get-Date).ToString("o") }
}

# 4. Bereite Ergebnis vor
$localAgentResult = @{
    status = "completed"
    totalProcesses = $agentProcesses.Values.Count
    healthyProcesses = ($agentProcesses.Values | Where-Object { $_.Count -gt 0 } | Measure-Object).Count
    issues = $processIssues.Count
    processes = $agentProcesses
    issuesDetails = $processIssues
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "LocalAgentCheck abgeschlossen: $($localAgentResult.healthyProcesses) gesund, $($localAgentResult.issues) Probleme." -Status "OK"
return $localAgentResult