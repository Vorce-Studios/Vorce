# PART-RUN-01_CreateProposal.ps1 (Vorce 3.0)
# Erzeugt einen Strategy Proposal fuer ein triagiertes Issue.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

function Get-VorceCreateProposalValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-VorceCreateProposalSafeSegment {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $safe = $Value -replace '[^A-Za-z0-9._-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) { return $Fallback }
    return $safe
}

function Save-VorceDeliberationCheckpoint {
    param(
        [Parameter(Mandatory)][hashtable]$RunContext,
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Issue
    )

    $mainSegment = Get-VorceCreateProposalSafeSegment -Value ([string]$RunContext.main_run_id) -Fallback 'main'
    $partSegment = Get-VorceCreateProposalSafeSegment -Value ([string]$RunContext.part_run_id) -Fallback 'part'
    $relativePath = "run-checkpoints/$mainSegment/$partSegment/deliberation.json"
    $path = Join-Path $global:VarDir $relativePath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $checkpoint = [ordered]@{
        schema_version = 1
        status = 'waiting_provider'
        error_class = $Result.error_class
        retry_after = $Result.retry_after
        run_context = $RunContext
        issue_number = $Issue.number
        phases = @($Result.phases)
        attempts = @($Result.attempts)
        artifact_refs = @($Result.artifact_refs)
        updated_at = (Get-Date).ToString('o')
    }
    $tempPath = "$path.tmp"
    $checkpoint | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tempPath -Encoding UTF8
    Move-Item -LiteralPath $tempPath -Destination $path -Force
    return $relativePath
}

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:VorceRoot 'src/lib/utils/StatusPrinter.ps1')
. (Join-Path $global:VorceRoot 'src/lib/utils/PromptManager.ps1')
if (-not (Get-Command Invoke-VorceAgentWithFallback -ErrorAction SilentlyContinue)) {
    . (Join-Path $global:VorceRoot 'src/lib/integrations/AgentRunner.ps1')
}
. (Join-Path $global:VorceRoot 'src/lib/engines/DeliberationEngine.ps1')

$repo = $ConfigBag.Config.repository
$proposalsDir = Join-Path $global:VarDir 'db/proposals'
$arguments = Get-VorceCreateProposalValue -Object $ConfigBag -Name 'Arguments'
$issueNumber = Get-VorceCreateProposalValue -Object $arguments -Name 'IssueNumber'
$issueTitle = Get-VorceCreateProposalValue -Object $arguments -Name 'IssueTitle'
$providedContext = Get-VorceCreateProposalValue -Object $ConfigBag -Name 'RunContext'
$partRunName = [string](Get-VorceCreateProposalValue -Object $providedContext -Name 'part_run_name')

if ([string]::IsNullOrWhiteSpace($partRunName) -and $global:VorceStatusRunContexts) {
    foreach ($entry in $global:VorceStatusRunContexts.GetEnumerator()) {
        if ([string]$entry.Key -notlike 'part|part-run-01_mr-01_planning__strategy__createproposal_*') {
            continue
        }
        $contexts = @($entry.Value)
        if ($contexts.Count -gt 0) {
            $partRunName = [string](Get-VorceCreateProposalValue -Object $contexts[-1] -Name 'run_name')
            break
        }
    }
}
if (-not $issueNumber -and $partRunName -match '__CreateProposal_(\d+)$') {
    $issueNumber = [int]$Matches[1]
}

$triagedPath = Join-Path $global:VarDir 'db/triaged-issues.json'
if (-not (Test-Path -LiteralPath $triagedPath)) {
    return @{ status = 'failed'; error_class = 'missing_input'; error = 'No triaged issues' }
}

try {
    $triaged = @(Get-Content -LiteralPath $triagedPath -Raw -Encoding UTF8 | ConvertFrom-Json)
} catch {
    return @{
        status = 'failed'
        error_class = 'invalid_input'
        error = "Failed to read triaged issues: $($_.Exception.Message)"
    }
}

if ($triaged.Count -eq 0) {
    Write-VorceStep -Message 'Keine relevanten Issues fuer Planung gefunden.' -Status 'OK'
    return @{ status = 'no_issues' }
}

if ($issueNumber) {
    $targetIssue = $triaged | Where-Object { $_.number -eq $issueNumber } | Select-Object -First 1
    Write-VorceStep -Message "Plane Strategie fuer spezifisches Issue #$issueNumber`: $issueTitle" -Status 'RUN'
} else {
    $targetIssue = $triaged[0]
    Write-VorceStep -Message "Plane Strategie fuer Issue #$($targetIssue.number): $($targetIssue.title)" -Status 'RUN'
}

if ($null -eq $targetIssue) {
    Write-VorceStep -Message "Kein Issue mit Nummer $issueNumber gefunden." -Status 'ERROR'
    return @{
        status = 'failed'
        error_class = 'issue_not_found'
        error = "Issue #$issueNumber nicht gefunden"
    }
}

if ($ConfigBag.DryRun) {
    Write-VorceStep -Message "DryRun: Deliberation fuer Issue #$($targetIssue.number) wird nicht ausgefuehrt." -Status 'INFO'
    return @{
        issue_number = $targetIssue.number
        status = 'dry_run'
        timestamp = (Get-Date).ToString('o')
    }
}

if ([string]::IsNullOrWhiteSpace($partRunName)) {
    $partRunName = "PART-RUN-01_MR-01_Planning__Strategy__CreateProposal_$($targetIssue.number)"
}
$mainRunId = Get-VorceCreateProposalValue -Object $providedContext -Name 'main_run_id'
$subRunId = Get-VorceCreateProposalValue -Object $providedContext -Name 'sub_run_id'
$partRunId = Get-VorceCreateProposalValue -Object $providedContext -Name 'part_run_id'

if ([string]::IsNullOrWhiteSpace([string]$mainRunId)) {
    $mainRunId = Get-VorceCreateProposalValue -Object $ParentState -Name 'main_run_id'
}
if ([string]::IsNullOrWhiteSpace([string]$subRunId)) {
    if ((Get-VorceCreateProposalValue -Object $ParentState -Name 'type') -eq 'SUB') {
        $subRunId = Get-VorceCreateProposalValue -Object $ParentState -Name 'id'
    } elseif ((Get-VorceCreateProposalValue -Object $ParentState -Name 'type') -eq 'PART') {
        $subRunId = Get-VorceCreateProposalValue -Object $ParentState -Name 'parent_run_id'
    }
}
if ([string]::IsNullOrWhiteSpace([string]$partRunId) -and
    (Get-VorceCreateProposalValue -Object $ParentState -Name 'type') -eq 'PART') {
    $partRunId = Get-VorceCreateProposalValue -Object $ParentState -Name 'id'
}

if ([string]::IsNullOrWhiteSpace([string]$partRunId)) {
    $partStatePath = Join-Path $global:VarDir "run-states/PART_$partRunName.json"
    if (Test-Path -LiteralPath $partStatePath) {
        try {
            $partState = Get-Content -LiteralPath $partStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($partState.type -eq 'PART' -and
                $partState.name -eq $partRunName -and
                $partState.main_run_id -eq $mainRunId -and
                $partState.parent_run_id -eq $subRunId) {
                $partRunId = $partState.id
            }
        } catch {
            # Der explizite Kontextfehler unten bleibt die einzige Fehlerquelle.
        }
    }
}

$missingContext = @()
if ([string]::IsNullOrWhiteSpace([string]$mainRunId)) { $missingContext += 'main_run_id' }
if ([string]::IsNullOrWhiteSpace([string]$subRunId)) { $missingContext += 'sub_run_id' }
if ([string]::IsNullOrWhiteSpace([string]$partRunId)) { $missingContext += 'part_run_id' }
if ($missingContext.Count -gt 0) {
    return @{
        status = 'failed'
        error_class = 'invalid_run_context'
        error = "Echter Run-Kontext fehlt: $($missingContext -join ', ')."
    }
}

$runContext = @{
    main_run_id = [string]$mainRunId
    sub_run_id = [string]$subRunId
    part_run_id = [string]$partRunId
    part_run_name = $partRunName
    working_directory = $global:VorceRoot
}
foreach ($name in @('session_id', 'correlation_id', 'chain_cycle')) {
    $value = Get-VorceCreateProposalValue -Object $providedContext -Name $name
    if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        $runContext[$name] = $value
    }
}

$baseVariables = @{ Repository = $repo }
$contextPrompt = Get-VorcePrompt -PromptId 'planning_session' -Variables $baseVariables

$relevantCode = ''
$codeSnippetsDir = Join-Path $global:VarDir 'db/code-snippets'
$issueSnippetFile = Join-Path $codeSnippetsDir "issue_$($targetIssue.number)_code.json"
if (Test-Path -LiteralPath $issueSnippetFile) {
    try {
        $codeSnippets = Get-Content -LiteralPath $issueSnippetFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($codeSnippets.related_code) {
            $relevantCode = $codeSnippets.related_code
            Write-VorceStep -Message "Geladene relevante Code-Snippets fuer Issue #$($targetIssue.number)" -Status 'INFO'
        }
    } catch {
        Write-VorceStep -Message "Fehler beim Laden von Code-Snippets: $($_.Exception.Message)" -Status 'WARN'
    }
}

$variables = @{
    contextPrompt = $contextPrompt
    IssueNumber = $targetIssue.number
    IssueTitle = $targetIssue.title
    IssueBody = $targetIssue.body
    Repository = $repo
    RelevantCode = if ($relevantCode) { $relevantCode } else { 'Keine zusaetzlichen Code-Snippets gefunden.' }
}

$result = Invoke-VorceDeliberation `
    -RunContext $runContext `
    -TaskName "Planning Proposal #$($targetIssue.number)" `
    -Variables $variables

if ($result.status -eq 'waiting_provider') {
    $checkpointRef = Save-VorceDeliberationCheckpoint -RunContext $runContext -Result $result -Issue $targetIssue
    return @{
        issue_number = $targetIssue.number
        status = 'waiting_provider'
        outcome = $result.outcome
        error = $result.error
        error_class = $result.error_class
        retry_after = $result.retry_after
        resume_required = $true
        checkpoint_ref = $checkpointRef
        artifact_refs = @($result.artifact_refs)
        attempts = @($result.attempts)
        phases = @($result.phases)
        summary = $result.summary
    }
}

if (-not $result.success) {
    return @{
        issue_number = $targetIssue.number
        status = 'failed'
        outcome = $result.outcome
        error = $result.error
        error_class = $result.error_class
        artifact_refs = @($result.artifact_refs)
        attempts = @($result.attempts)
        phases = @($result.phases)
        summary = $result.summary
    }
}

if (-not (Test-Path -LiteralPath $proposalsDir)) {
    $null = New-Item -ItemType Directory -Path $proposalsDir -Force
}

$proposal = [ordered]@{
    issueId = $targetIssue.id
    issueNumber = $targetIssue.number
    title = $targetIssue.title
    body = $targetIssue.body
    deliberation = $result.payload
    deliberation_status = $result.status
    deliberation_trace = [ordered]@{
        summary = $result.summary
        phases = @($result.phases)
        artifact_refs = @($result.artifact_refs)
    }
    timestamp = (Get-Date).ToString('o')
    status = 'created'
}
$proposalKey = if ($null -ne $targetIssue.number) { $targetIssue.number } else { $targetIssue.id }
$proposalFile = Join-Path $proposalsDir "proposal_$proposalKey.json"
$proposal | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $proposalFile -Encoding UTF8

return @{
    issue_number = $targetIssue.number
    status = 'proposal_created'
    deliberation_status = $result.status
    timestamp = (Get-Date).ToString('o')
    proposal_file = $proposalFile
    artifact_refs = @($result.artifact_refs)
    attempts = @($result.attempts)
    phases = @($result.phases)
    summary = $result.summary
}
