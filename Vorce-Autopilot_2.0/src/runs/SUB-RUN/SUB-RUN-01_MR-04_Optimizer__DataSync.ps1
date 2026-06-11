# src/runs/SUB-RUN/SUB-RUN-01_MR-04_Optimizer__DataSync.ps1
# Sammelt Daten für die nachfolgenden Optimizer-Schritte
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-01 DataSync: Sammle Optimizer-Kontextdaten..." -ForegroundColor Cyan

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")

# 1. Lade Memory Store
$memStoreJson = "{}"
try {
    $memStoreJson = Read-MemoryStore | ConvertTo-Json -Depth 15 -Compress
} catch { Write-Warning "[OPTIMIZER] Fehler beim Lesen des MemoryStores." }

# 2. Lade Task Journal
$journalContent = ""
$journalPath = Get-AutopilotTaskJournalPath
if (Test-Path $journalPath) {
    try {
        $journalContent = Get-Content $journalPath -Raw -Encoding UTF8
    } catch { Write-Warning "[OPTIMIZER] Fehler beim Lesen des TaskJournals." }
}

# 3. Lade Autopilot Logs
$logContent = ""
$logFilePath = Join-Path $ScriptDir "var/log/autopilot-live.log"
if (Test-Path $logFilePath) {
    try {
        $logContent = Get-Content $logFilePath -Tail 250 -ErrorAction SilentlyContinue | Out-String
    } catch { Write-Warning "[OPTIMIZER] Fehler beim Lesen der Live-Logs." }
}

# 4. Lade CI/CD Workflows (fuer zukuenftige CI/CD-Optimierungen)
$ciCdContext = ""
$workflowsDir = Join-Path $ScriptDir ".github/workflows"
if (Test-Path $workflowsDir) {
    try {
        $workflowFiles = Get-ChildItem -Path $workflowsDir -Filter "*.yml"
        foreach ($file in $workflowFiles) {
            $ciCdContext += "`n--- $($file.Name) ---`n"
            $ciCdContext += Get-Content $file.FullName -Raw -Encoding UTF8
        }
    } catch { Write-Warning "[OPTIMIZER] Fehler beim Lesen der CI/CD Workflows." }
}

# Speichere die gesammelten Strings im MainState fuer naechste Sub-Runs
$MainState | Add-Member -MemberType NoteProperty -Name "OptMemStoreJson" -Value $memStoreJson -Force
$MainState | Add-Member -MemberType NoteProperty -Name "OptJournalContent" -Value $journalContent -Force
$MainState | Add-Member -MemberType NoteProperty -Name "OptLogContent" -Value $logContent -Force
$MainState | Add-Member -MemberType NoteProperty -Name "OptCiCdContext" -Value $ciCdContext -Force

Write-Host "[OPTIMIZER] Daten synchronisiert (Memory, Journal, Logs, CI/CD)." -ForegroundColor DarkGray
$SubState.status = "completed"
