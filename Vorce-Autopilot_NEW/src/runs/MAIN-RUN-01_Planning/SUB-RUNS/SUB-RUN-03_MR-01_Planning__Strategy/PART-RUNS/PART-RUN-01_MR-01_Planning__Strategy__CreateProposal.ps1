# PART-RUN-01_CreateProposal.ps1 (Vorce 3.0)
# Erzeugt einen Strategy Proposal für ein triagiertes Issue
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
. (Join-Path $global:VorceRoot "src/lib/utils/StatusPrinter.ps1")
. (Join-Path $global:VorceRoot "src/lib/utils/PromptManager.ps1")
. (Join-Path $global:VorceRoot "src/lib/integrations/AgentRunner.ps1")
. (Join-Path $global:VorceRoot "src/lib/engines/DeliberationEngine.ps1")

# NACHHER: Ersetze alle hardkodierten Werte durch Config-Lesungen
$repo = $ConfigBag.Config.repository
$proposalsDir = Join-Path $global:VarDir "db/proposals"

# Lade triagierte Issues
$triagedPath = Join-Path $global:VarDir "db/triaged-issues.json"
if (-not (Test-Path $triagedPath)) { return @{ error = "No triaged issues" } }

try {
    $triaged = Get-Content $triagedPath -Raw | ConvertFrom-Json
    if (-not ($triaged -is [array])) {
        $triaged = @($triaged)
    }
} catch {
    return @{ error = "Failed to read triaged issues: $($_.Exception.Message)" }
}

# PRÜFE: sicherstellen dass $triaged ein Array ist und nicht leer
if ($null -eq $triaged -or $triaged.Count -eq 0) {
    Write-VorceStep -Message "Keine relevanten Issues für Planung gefunden." -Status "OK"
    return @{ status = "no_issues" }
}

# 0. Bestimme Target Issue (verwende erstes Issue in der Liste)
$targetIssue = $triaged[0]
Write-VorceStep -Message "Plane Strategie für Issue #$($targetIssue.number): $($targetIssue.title)" -Status "RUN"

if ($ConfigBag.DryRun) {
    Write-VorceStep -Message "DryRun: Deliberation für Issue #$($targetIssue.number) wird nicht ausgeführt." -Status "INFO"
    return @{
        issue_number = $targetIssue.number
        status = "dry_run"
        timestamp = (Get-Date).ToString("o")
    }
}

# 1. Vorbereiten der Variablen für den Basis-Prompt
$BaseVariables = @{
    Repository = $repo
    dashboardInstructions = "Verwende das Dashboard zur Visualisierung."
    TaskJournalPath = "var/log/journal.md"
    SessionLockPath = "var/tmp/session.lock"
}

# 2. Lade den Basis-Prompt (Planungssitzung)
$contextPrompt = Get-VorcePrompt -PromptId "planning_session" -Variables $BaseVariables

# 3. Erweitere Variablen für die Deliberation
$Variables = @{
    contextPrompt = $contextPrompt
    IssueNumber   = $targetIssue.number
    IssueTitle    = $targetIssue.title
    IssueBody     = $targetIssue.body
}

$Result = Invoke-VorceDeliberation `
    -MainRun "MAIN-RUN-01_Planning" `
    -SubRun "Strategy" `
    -TaskName "Planning Proposal #$($targetIssue.number)" `
    -Variables $Variables

if ($null -ne $Result) {
    # Speichere Proposal als JSON (nicht als MD)
    if (-not (Test-Path $proposalsDir)) {
        New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null
    }

    $proposal = @{
        issueId = $targetIssue.id
        issueNumber = $targetIssue.number
        title = $targetIssue.title
        body = $targetIssue.body
        deliberation = $Result
        timestamp = (Get-Date).ToString("o")
        status = "created"
    }

    $proposalFile = Join-Path $proposalsDir "proposal_$($targetIssue.number ?? $targetIssue.id).json"
    $proposal | ConvertTo-Json -Depth 10 | Set-Content $proposalFile -Encoding UTF8

    return @{
        issue_number = $targetIssue.number
        status = "proposal_created"
        timestamp = (Get-Date).ToString("o")
        proposal_file = $proposalFile
    }
}

return @{ error = "Deliberation failed" }
