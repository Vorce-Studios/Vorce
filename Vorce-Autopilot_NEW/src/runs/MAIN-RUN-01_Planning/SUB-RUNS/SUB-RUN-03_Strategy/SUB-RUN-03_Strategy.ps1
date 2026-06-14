# SUB-RUN-03_Strategy.ps1 (Vorce 3.0)
# Erzeugt Strategie-Proposals für triagierte Issues
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
$ScriptDir = $PSScriptRoot

# Benötigte Module
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/DeliberationEngine.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")

Write-VorceStep -Message "Starte Strategy/Deliberation..." -Status "RUN"

# 1. Lade triagierte Issues aus var/db/triaged-issues.json
$triagedFile = Join-Path $global:VarDir "db/triaged-issues.json"
if (-not (Test-Path $triagedFile)) {
    Write-VorceStep -Message "Keine triagierten Issues gefunden." -Status "WARN"
    return @{ status="no_triaged_issues"; proposals=@(); count=0 }
}

try {
    $triagedIssues = Get-Content $triagedFile -Raw | ConvertFrom-Json
    if (-not ($triagedIssues -is [array])) {
        $triagedIssues = @($triagedIssues)
    }
} catch {
    Write-VorceStep -Message "Fehler beim Lesen von triaged-issues.json: $($_.Exception.Message)" -Status "ERROR"
    return @{ status="error"; error=$_.Exception.Message; proposals=@(); count=0 }
}

# 2. Für jedes Issue (bis max_issues_per_planning_cycle)
$maxIssues = $ConfigBag.Config.max_issues_per_planning_cycle
$proposalsDir = Join-Path $global:VarDir "db/proposals"
if (-not (Test-Path $proposalsDir)) {
    New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null
}

$proposals = @()
$processedCount = 0

foreach ($issue in $triagedIssues) {
    if ($processedCount -ge $maxIssues) {
        Write-VorceStep -Message "Max Issues pro Cycle ($maxIssues) erreicht." -Status "INFO"
        break
    }

    Write-VorceStep -Message "Erstelle Strategy für Issue #$(if ($issue.number) { $issue.number } else { $issue.id })" -Status "RUN"

    # 2a. Quota prüfen
    $quotaOK = Test-VorceQuota -AgentName "jules"
    if (-not $quotaOK) {
        Write-VorceStep -Message "Jules Quota erschöpft, überspringe Issue." -Status "WARN"
        continue
    }

    # 2b. Invoke-VorceDeliberation aufrufen
    try {
        $deliberationResult = Invoke-VorceDeliberation -Issue $issue -ConfigBag $ConfigBag

        # 2c. Ergebnis als Proposal speichern
        $proposal = @{
            issueId = $issue.id
            issueNumber = $issue.number
            title = $issue.title
            deliberation = $deliberationResult
            timestamp = (Get-Date).ToString("o")
            status = "created"
        }

        $proposalFile = Join-Path $proposalsDir "proposal_$($issue.number ?? $issue.id).json"
        $proposal | ConvertTo-Json -Depth 10 | Set-Content $proposalFile -Encoding UTF8

        $proposals += $proposal
        $processedCount++

        Write-VorceStep -Message "Proposal für Issue #$(if ($issue.number) { $issue.number } else { $issue.id }) erstellt." -Status "OK"
    } catch {
        Write-VorceStep -Message "Fehler bei Deliberation: $($_.Exception.Message)" -Status "ERROR"
    }
}

# 3. State mit Anzahl Proposals zurückgeben
$strategyResult = @{
    status = "completed"
    proposals = $proposals
    count = $proposals.Count
    processedIssues = $processedCount
    maxIssues = $maxIssues
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Strategy abgeschlossen: $($strategyResult.count) Proposals erstellt." -Status "OK"
return $strategyResult
