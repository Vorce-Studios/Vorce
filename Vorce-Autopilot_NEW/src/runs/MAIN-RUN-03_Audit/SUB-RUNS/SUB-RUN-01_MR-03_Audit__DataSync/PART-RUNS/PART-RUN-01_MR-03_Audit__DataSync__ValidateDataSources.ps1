# SUB-RUN-01_DataSync.ps1 (Vorce 3.0)
# Leichtgewichtiger Sync-Check für Audit-Run
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
. (Join-Path $global:LibDir "integrations/ApiClient.ps1")

Write-VorceStep -Message "Starte Audit-DataSync..." -Status "RUN"

# Leichtgewichtiger Sync-Check
$syncResults = @()

# Prüfe GitHub API Erreichbarkeit
try {
    $repo = $ConfigBag.Config.repository
    $pingResult = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$repo" -Method GET -Headers @{ "Accept" = "application/vnd.github.v3+json" }
    $syncResults += @{ type = "github_api"; status = "ok"; response_time = "fast" }
    Write-VorceStep -Message "GitHub API erreichbar" -Status "OK"
} catch {
    $syncResults += @{ type = "github_api"; status = "error"; message = $_.Exception.Message }
    Write-VorceStep -Message "GitHub API Fehler: $($_.Exception.Message)" -Status "ERROR"
}

# Prüfe ob grundlegende Ordner existieren
$requiredDirs = @("var", "var/db", "var/log", "var/tmp")
foreach ($dir in $requiredDirs) {
    $dirPath = Join-Path $global:VorceRoot $dir
    if (Test-Path $dirPath) {
        $syncResults += @{ type = "directory_$dir"; status = "ok" }
    } else {
        $syncResults += @{ type = "directory_$dir"; status = "missing" }
        Write-VorceStep -Message "Verzeichnis $dir fehlt" -Status "WARN"
    }
}

# Audit Ergebnis
$auditResult = @{
    status = "completed"
    sync_results = $syncResults
    successful_checks = ($syncResults | Where-Object { $_.status -eq "ok" }).Count
    total_checks = $syncResults.Count
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Audit-DataSync abgeschlossen: $($auditResult.successful_checks)/$($auditResult.total_checks) Checks erfolgreich" -Status "OK"
return $auditResult
