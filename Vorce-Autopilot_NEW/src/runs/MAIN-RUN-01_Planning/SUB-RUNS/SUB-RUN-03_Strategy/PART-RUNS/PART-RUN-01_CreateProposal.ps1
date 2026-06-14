# PART-RUN-04_CreateProposal.ps1 (Vorce 3.0)
[CmdletBinding()]
param()

$global:VorceRoot = Join-Path $PSScriptRoot "../../../.."
$ScriptDir = $PSScriptRoot
$VarDir = Join-Path $global:VorceRoot "var"

. (Join-Path $global:VorceRoot "src/lib/utils/StatusPrinter.ps1")
. (Join-Path $global:VorceRoot "src/lib/utils/PromptManager.ps1")
. (Join-Path $global:VorceRoot "src/lib/integrations/AgentRunner.ps1")
. (Join-Path $global:VorceRoot "src/lib/engines/DeliberationEngine.ps1")

# Lade triagierte Issues
$triagedPath = Join-Path $VarDir "db/triaged-issues.json"
if (-not (Test-Path $triagedPath)) { return @{ error = "No triaged issues" } }
$triaged = Get-Content $triagedPath -Raw | ConvertFrom-Json

if ($triaged.Count -eq 0) {
    Write-VorceStep -Message "Keine relevanten Issues für Planung gefunden." -Status "OK"
    return @{ status = "idle" }
}

# 0. Bestimme Target Issue
$targetIssue = $triaged[0]
Write-VorceStep -Message "Plane Strategie für Issue #$($targetIssue.number): $($targetIssue.title)" -Status "RUN"

# 1. Vorbereiten der Variablen für den Basis-Prompt
$BaseVariables = @{
    Repository = "Vorce-Studios/Vorce"
    dashboardInstructions = "Verwende das Dashboard zur Visualisierung."
    TaskJournalPath = "var/log/journal.md"
    SessionLockPath = "var/tmp/session.lock"
}

# 2. Lade den Basis-Prompt (Planungssitzung)
$contextPrompt = Get-VorcePrompt -MainRun "MAIN-RUN-01_Planning" -SubRun "Strategy" -PartRun "planning_session" -Variables $BaseVariables

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
    # Speichere Proposal
    $proposalDir = Join-Path $VarDir "db/proposals"
    if (-not (Test-Path $proposalDir)) { New-Item -ItemType Directory -Path $proposalDir -Force | Out-Null }
    $Result | Set-Content (Join-Path $proposalDir "proposal_$($targetIssue.number).md") -Encoding UTF8
    
    return @{ 
        issue_number = $targetIssue.number
        status = "proposal_created"
        timestamp = (Get-Date).ToString("o") 
    }
}

return @{ error = "Deliberation failed" }
