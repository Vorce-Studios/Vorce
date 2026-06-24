# SUB-RUN-03_MR-01_Planning__Strategy.ps1 (Vorce 3.0)
# Koordiniert und aggregiert die Strategy-PART-RUNs.
# In V3: Parallele Verarbeitung aller triagierten Issues
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")

# Lade triagierte Issues aus der Datenbank
$triagedPath = Join-Path $global:VarDir "db/triaged-issues.json"
if (-not (Test-Path $triagedPath)) {
    Write-VorceStep -Message "Keine triaged-issues.json gefunden - Strategy-Phase wird übersprungen." -Status "WARN"
    return @{ status = "no_issues" }
}

try {
    $triagedIssues = Get-Content $triagedPath -Raw | ConvertFrom-Json
    if (-not ($triagedIssues -is [array])) {
        $triagedIssues = @($triagedIssues)
    }
} catch {
    Write-VorceStep -Message "Fehler beim Lesen von triaged-issues.json: $($_.Exception.Message)" -Status "ERROR"
    return @{ status = "error"; message = $_.Exception.Message }
}

# Prüfe ob Issues vorhanden sind
if ($null -eq $triagedIssues -or $triagedIssues.Count -eq 0) {
    Write-VorceStep -Message "Keine relevanten Issues für Strategie-Planung gefunden." -Status "OK"
    return @{ status = "no_issues" }
}

# Erstelle für JEDES Issue einen eigenen Part-Run
$partRuns = @()
foreach ($issue in $triagedIssues) {
    $partRun = @{
        name = "PART-RUN-01_MR-01_Planning__Strategy__CreateProposal_$($issue.number)"
        script = Join-Path $PSScriptRoot "PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1"
        arguments = @{
            IssueNumber = $issue.number
            IssueTitle = $issue.title
            IssueBody = $issue.body
        }
    }
    $partRuns += $partRun
}

Write-VorceStep -Message "Erstelle $($partRuns.Count) parallele Strategy-Proposals für Issues: $($triagedIssues.number -join ', ')" -Status "RUN"

# Nutze parallele Ausführung für bessere Performance
return Invoke-VorceSubRunParallel -SubRunName "SUB-RUN-03_MR-01_Planning__Strategy" -PartRuns $partRuns -ConfigBag $ConfigBag -ParentState $ParentState
