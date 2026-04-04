[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ceo', 'chief_of_staff', 'discovery', 'jules', 'gemini_review', 'qwen_review', 'codex_review', 'ops', 'atlas')]
    [string]$Role
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\CapacityLedger.ps1')
. (Join-Path $ScriptDir 'lib\IssueMetadata.ps1')
. (Join-Path $ScriptDir 'lib\CliTools.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')
. (Join-Path $ScriptDir '..\jules\jules-api.ps1')
. (Join-Path $ScriptDir '..\jules\jules-github.ps1')

Import-VorceStudiosPaperclipEnvironment

function Get-VorceStudiosAgentContext {
    $companyState = Get-VorceStudiosCompanyState
    if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
        return $null
    }

    return @{
        Company = $companyState.company
        Agents = $companyState.agents
        Project = $companyState.project
        Repository = Get-VorceStudiosRepositorySlug
        Runtime = Get-VorceStudiosRuntimeState
        Ledger = Get-VorceStudiosCapacityLedger
    }
}

function Get-VorceStudiosOpenCompanyIssues {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    return @(
        Get-VorceStudiosIssues -CompanyId $Context.Company.id |
            Where-Object { [string]$_.status -ne 'done' -and [string]$_.status -ne 'cancelled' }
    )
}

function Get-VorceStudiosIssuePriority {
    param(
        [Parameter(Mandatory)][object]$GitHubIssue
    )

    $labelNames = @($GitHubIssue.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.name } })
    if ($labelNames -contains 'critical') { return 'critical' }
    if ($labelNames -contains 'high-priority') { return 'high' }
    if ($labelNames -contains 'bug') { return 'high' }
    return 'medium'
}

function Get-VorceStudiosTaskType {
    param(
        [Parameter(Mandatory)][object]$GitHubIssue
    )

    $text = ('{0} {1}' -f [string]$GitHubIssue.title, [string]$GitHubIssue.body).ToLowerInvariant()
    if ($text -match 'verify|review') { return 'review' }
    if ($text -match 'refactor|architecture|design') { return 'architecture' }
    if ($text -match 'bug|fix|render|output|preview|projector|media') { return 'implementation' }
    return 'implementation'
}

function Get-VorceStudiosRiskClass {
    param(
        [Parameter(Mandatory)][object]$GitHubIssue
    )

    $text = ('{0} {1}' -f [string]$GitHubIssue.title, [string]$GitHubIssue.body).ToLowerInvariant()
    if ($text -match 'render|media|projector|output|persist|migration|unsafe|dependency|ci') { return 'high' }
    if ($text -match 'ui|preview|control') { return 'medium' }
    return 'low'
}

function Test-VorceStudiosUiSurface {
    param(
        [Parameter(Mandatory)][object]$GitHubIssue
    )

    $text = ('{0} {1}' -f [string]$GitHubIssue.title, [string]$GitHubIssue.body).ToLowerInvariant()
    return ($text -match 'ui|preview|projector|window|layout|interaction|visible')
}

function Get-VorceStudiosExecutorChain {
    param(
        [Parameter(Mandatory)][string]$TaskType
    )

    $routing = Get-VorceStudiosPolicy -Name 'routing'
    if ($routing.Executors.ContainsKey($TaskType)) {
        return @($routing.Executors[$TaskType].FallbackChain)
    }
    return @('jules', 'gemini', 'qwen', 'codex')
}

function Get-VorceStudiosReviewerChain {
    param(
        [Parameter(Mandatory)][string]$RiskClass
    )

    $routing = Get-VorceStudiosPolicy -Name 'routing'
    if ($RiskClass -eq 'high') {
        return @($routing.Reviewers.HighRisk)
    }
    return @($routing.Reviewers.Default)
}

function Get-VorceStudiosAgentKeyForTool {
    param(
        [Parameter(Mandatory)][string]$Tool
    )

    switch ($Tool) {
        'jules' { return 'jules' }
        'gemini' { return 'gemini_review' }
        'qwen' { return 'qwen_review' }
        'codex' { return 'codex_review' }
        default { return 'ops' }
    }
}

function Add-VorceStudiosCommentSafe {
    param(
        [Parameter(Mandatory)][string]$IssueId,
        [Parameter(Mandatory)][string]$Body
    )

    try {
        Add-VorceStudiosIssueComment -IssueId $IssueId -Body $Body | Out-Null
    } catch {
        Write-Warning ("Issue-Kommentar konnte nicht geschrieben werden: {0}" -f $_.Exception.Message)
    }
}

function Get-VorceStudiosGitHubIssueUrl {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Metadata
    )

    if (-not $Metadata.ContainsKey('gh_issue')) {
        return $null
    }

    return ('https://github.com/{0}/issues/{1}' -f $Context.Repository, [string]$Metadata['gh_issue'])
}

function Get-VorceStudiosReviewResult {
    param(
        [AllowNull()][string]$Text
    )

    $result = @{
        verdict = 'changes_requested'
        summary = ''
        findings = @()
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        $result.summary = 'No structured review output was produced.'
        $result.findings = @('no automated review output')
        return $result
    }

    if ($Text -match 'VERDICT:\s*(?<value>pass|changes_requested|manual_ui_required)') {
        $result.verdict = [string]$Matches['value']
    }

    if ($Text -match 'SUMMARY:\s*(?<value>.+?)(?:\r?\n[A-Z][A-Z_]+:|\z)') {
        $result.summary = ([string]$Matches['value']).Trim()
    }

    if ($Text -match 'FINDINGS:\s*(?<value>[\s\S]+)$') {
        $findingBlock = ([string]$Matches['value']).Trim()
        $lines = @(
            $findingBlock -split '\r?\n' |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($lines.Count -gt 0) {
            $result.findings = @(
                $lines |
                    ForEach-Object { $_ -replace '^-+\s*', '' } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'none' }
            )
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$result.summary)) {
        $result.summary = 'Automated review finished without a structured summary.'
    }

    return $result
}

function Get-VorceStudiosLastObjectResult {
    param(
        [AllowNull()][object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $items = @($InputObject | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) {
        return $null
    }

    return $items[$items.Count - 1]
}

function Get-VorceStudiosSafePropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Ensure-VorceStudiosApprovalForIssue {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][hashtable]$Metadata,
        [Parameter(Mandatory)][string]$GateType,
        [Parameter(Mandatory)][string]$Summary
    )

    if ($Metadata.ContainsKey('approval_id')) {
        $existing = Get-VorceStudiosApproval -ApprovalId ([string]$Metadata['approval_id'])
        if ($null -ne $existing) {
            return $existing
        }
    }

    $payload = @{
        type = 'approve_ceo_strategy'
        requestedByAgentId = [string]$Context.Agents['ceo'].id
        issueIds = @([string]$Issue.id)
        payload = @{
            gateType = $GateType
            summary = $Summary
            repository = $Context.Repository
            paperclipIssueId = [string]$Issue.id
            paperclipIssueKey = [string]$Issue.identifier
            githubIssueNumber = if ($Metadata.ContainsKey('gh_issue')) { [int]$Metadata['gh_issue'] } else { $null }
            pullRequestUrl = if ($Metadata.ContainsKey('pr_url')) { [string]$Metadata['pr_url'] } else { $null }
            preferredChannel = Get-VorceStudiosPreferredApprovalChannel
        }
    }

    $approval = New-VorceStudiosApproval -CompanyId $Context.Company.id -Payload $payload
    $Metadata['approval_id'] = [string]$approval.id
    $Metadata['approval_status'] = [string]$approval.status
    return $approval
}

function Update-VorceStudiosIssueMetadataAndState {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Metadata,
        [hashtable]$Patch = @{}
    )

    $description = Set-VorceStudiosIssueMetadata -Text ([string]$Issue.description) -Metadata $Metadata
    $payload = @{ description = $description }
    $commentBody = $null
    foreach ($key in $Patch.Keys) {
        if ([string]$key -eq 'comment') {
            $commentBody = [string]$Patch[$key]
            continue
        }

        $payload[$key] = $Patch[$key]
    }

    $updated = Update-VorceStudiosIssue -IssueId $Issue.id -Payload $payload
    if ($null -ne $updated) {
        if (-not [string]::IsNullOrWhiteSpace($commentBody)) {
            Add-VorceStudiosCommentSafe -IssueId ([string]$updated.id) -Body $commentBody
        }

        try {
            Sync-VorceStudiosIssueToGitHub -Context $Context -Issue $updated | Out-Null
        } catch {
            Write-Warning ("GitHub-Sync fuer Issue '{0}' fehlgeschlagen: {1}" -f [string]$Issue.title, $_.Exception.Message)
        }
    }

    return $updated
}

function Invoke-VorceStudiosDiscovery {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $planningPolicy = Get-VorceStudiosPolicy -Name 'planning'
    $planningRecords = @(
        Invoke-VorceStudiosPlanningSweep -Repository $Context.Repository
    )
    $planningByIssue = @{}
    foreach ($record in $planningRecords) {
        $planningByIssue[[string]$record.issueNumber] = $record
    }

    $existingIssueNumbers = @{}
    $companyIssues = @(Get-VorceStudiosOpenCompanyIssues -Context $Context)
    foreach ($issue in $companyIssues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        if ($metadata.ContainsKey('gh_issue')) {
            $existingIssueNumbers[[string]$metadata['gh_issue']] = $true
        }
    }

    $ghIssuesByNumber = @{}
    foreach ($item in (Get-GitHubIssues -Repository $Context.Repository -State open -Limit ([int]$planningPolicy.Discovery.IssueLimit))) {
        $ghIssuesByNumber[[string]$item.number] = $item
    }

    $imported = 0
    foreach ($record in $planningRecords) {
        $ghIssue = $ghIssuesByNumber[[string]$record.issueNumber]
        if ($null -eq $ghIssue) { continue }
        $labelNames = @($ghIssue.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.name } })
        $eligible = ($labelNames -contains 'Todo-UserISU') -or ($labelNames -contains 'jules-task') -or ($labelNames -contains 'bug') -or ([string]$ghIssue.title).StartsWith('__')
        if (-not $eligible) { continue }
        if ($existingIssueNumbers.ContainsKey([string]$ghIssue.number)) { continue }
        if ($imported -ge [int]$planningPolicy.Discovery.ImportLimit) { break }

        $taskType = Get-VorceStudiosTaskType -GitHubIssue $ghIssue
        $riskClass = Get-VorceStudiosRiskClass -GitHubIssue $ghIssue
        $uiSurface = Test-VorceStudiosUiSurface -GitHubIssue $ghIssue
        $executorChain = Get-VorceStudiosExecutorChain -TaskType $taskType
        $preferredExecutor = $executorChain[0]
        $reviewChain = Get-VorceStudiosReviewerChain -RiskClass $riskClass

        $metadata = @{
            gh_issue = [string]$ghIssue.number
            repo = $Context.Repository
            task_type = $taskType
            risk_class = $riskClass
            ui_surface = if ($uiSurface) { 'true' } else { 'false' }
            preferred_executor = $preferredExecutor
            fallback_chain = $executorChain
            review_chain = $reviewChain
            human_gate = if ($uiSurface) { 'manual_ui_gate' } else { 'none' }
            planner_score = [string]$record.score
            planner_bucket = [string]$record.bucket
            planner_readiness = [string]$record.readiness
            sync_origin = 'github_issue'
        }

        $issueDescription = Set-VorceStudiosIssueMetadata -Text ([string]$ghIssue.body) -Metadata $metadata
        $payload = @{
            title = ('GH #{0}: {1}' -f $ghIssue.number, $ghIssue.title)
            description = $issueDescription
            status = if ([string]$record.readiness -in @('active', 'in_review')) { 'todo' } else { 'backlog' }
            priority = if ([string]$record.bucket -eq 'critical') { 'critical' } elseif ([string]$record.bucket -eq 'high') { 'high' } elseif ([string]$record.bucket -eq 'medium') { 'medium' } else { 'low' }
        }
        if ($Context.Project) {
            $payload['projectId'] = $Context.Project.id
        }

        $created = New-VorceStudiosIssue -CompanyId $Context.Company.id -Payload $payload
        if ($null -ne $created) {
            try {
                Sync-VorceStudiosIssueToGitHub -Context $Context -Issue $created | Out-Null
            } catch {
                Write-Warning ("Discovery-Sync fuer GH #{0} fehlgeschlagen: {1}" -f $ghIssue.number, $_.Exception.Message)
            }
        }
        $imported++
    }

    foreach ($existingIssue in $companyIssues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$existingIssue.description)
        if ($metadata.ContainsKey('gh_issue') -and $ghIssuesByNumber.ContainsKey([string]$metadata['gh_issue'])) {
            $ghIssue = $ghIssuesByNumber[[string]$metadata['gh_issue']]
            $planningRecord = if ($planningByIssue.ContainsKey([string]$ghIssue.number)) { $planningByIssue[[string]$ghIssue.number] } else { $null }
            $taskType = Get-VorceStudiosTaskType -GitHubIssue $ghIssue
            $riskClass = Get-VorceStudiosRiskClass -GitHubIssue $ghIssue
            $uiSurface = Test-VorceStudiosUiSurface -GitHubIssue $ghIssue
            $executorChain = Get-VorceStudiosExecutorChain -TaskType $taskType
            $reviewChain = Get-VorceStudiosReviewerChain -RiskClass $riskClass

            $metadata['task_type'] = $taskType
            $metadata['risk_class'] = $riskClass
            $metadata['ui_surface'] = if ($uiSurface) { 'true' } else { 'false' }
            $metadata['preferred_executor'] = $executorChain[0]
            $metadata['fallback_chain'] = $executorChain
            $metadata['review_chain'] = $reviewChain
            $metadata['source_of_truth'] = 'github'
            if ($null -ne $planningRecord) {
                $metadata['planner_score'] = [string]$planningRecord.score
                $metadata['planner_bucket'] = [string]$planningRecord.bucket
                $metadata['planner_readiness'] = [string]$planningRecord.readiness
            }

            $priority = if ($null -eq $planningRecord) {
                [string]$existingIssue.priority
            } elseif ([string]$planningRecord.bucket -eq 'critical') {
                'critical'
            } elseif ([string]$planningRecord.bucket -eq 'high') {
                'high'
            } elseif ([string]$planningRecord.bucket -eq 'medium') {
                'medium'
            } else {
                'low'
            }

            $status = [string]$existingIssue.status
            if ($status -in @('backlog', 'todo')) {
                if ($null -ne $planningRecord -and [string]$planningRecord.readiness -in @('active', 'in_review')) {
                    $status = 'todo'
                } elseif ($null -ne $planningRecord -and [string]$planningRecord.readiness -eq 'awaiting_user_approval') {
                    $status = 'backlog'
                }
            }

            Update-VorceStudiosIssueMetadataAndState -Issue $existingIssue -Context $Context -Metadata $metadata -Patch @{
                priority = $priority
                status = $status
            } | Out-Null
        }

        try {
            Sync-VorceStudiosIssueToGitHub -Context $Context -Issue $existingIssue | Out-Null
        } catch {
            Write-Warning ("Planning-Sync fuer bestehendes Issue '{0}' fehlgeschlagen: {1}" -f [string]$existingIssue.title, $_.Exception.Message)
        }
    }

    Connect-VorceStudiosGitHubPluginLinks -Context $Context
}

function Invoke-VorceStudiosChiefOfStaff {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $issues = Get-VorceStudiosOpenCompanyIssues -Context $Context
    foreach ($issue in $issues) {
        if ([string]$issue.status -eq 'blocked') { continue }
        if ([string]$Context.Runtime.mode -eq 'draining' -and [string]$issue.status -eq 'backlog') { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$issue.assigneeAgentId)) { continue }

        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        $taskType = if ($metadata.ContainsKey('task_type')) { [string]$metadata['task_type'] } else { 'implementation' }
        $chain = if ($metadata.ContainsKey('fallback_chain')) { @($metadata['fallback_chain']) } else { Get-VorceStudiosExecutorChain -TaskType $taskType }
        $selectedTool = Get-VorceStudiosPreferredTool -Chain $chain
        if ([string]::IsNullOrWhiteSpace($selectedTool)) {
            continue
        }

        $agentKey = Get-VorceStudiosAgentKeyForTool -Tool $selectedTool
        if (-not $Context.Agents.ContainsKey($agentKey)) {
            continue
        }

        $metadata['executor_tool'] = $selectedTool
        $patch = @{
            assigneeAgentId = $Context.Agents[$agentKey].id
            status = if ([string]$issue.status -eq 'backlog') { 'todo' } else { [string]$issue.status }
            comment = ('Assigned by Chief of Staff to {0} using tool {1}.' -f $Context.Agents[$agentKey].name, $selectedTool)
        }
        Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch $patch | Out-Null
    }
}

function Invoke-VorceStudiosJulesBuilder {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $agentId = [string]$Context.Agents['jules'].id
    $issues = Get-VorceStudiosOpenCompanyIssues -Context $Context | Where-Object { [string]$_.assigneeAgentId -eq $agentId }

    foreach ($issue in $issues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        if (-not $metadata.ContainsKey('gh_issue')) {
            $metadata['human_gate'] = 'needs_manual_mapping'
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = 'Jules Builder blocked: missing gh_issue metadata.'
            } | Out-Null
            continue
        }

        $ghIssueNumber = [int]$metadata['gh_issue']
        $reference = Get-JulesSessionReferenceFromIssue -Repository $Context.Repository -IssueNumber $ghIssueNumber
        $session = $null
        if ($reference) {
            $metadata['session_id'] = [string]$reference.SessionId
            $metadata['session_name'] = [string]$reference.SessionName
            try {
                $lookupKey = if (-not [string]::IsNullOrWhiteSpace([string]$reference.SessionName)) {
                    [string]$reference.SessionName
                } else {
                    [string]$reference.SessionId
                }
                if (-not [string]::IsNullOrWhiteSpace($lookupKey)) {
                    $session = Get-JulesSession -SessionIdOrName $lookupKey -ApiKey $env:JULES_API_KEY
                }
            } catch {
                $session = $null
            }
        }

        if ($metadata.ContainsKey('review_feedback')) {
            $reworkMessage = @(
                'Please address the following review findings and update the existing PR if possible.',
                '',
                [string]$metadata['review_feedback']
            ) -join "`n"

            if ($null -ne $session -and [string]$session.state -notin @('COMPLETED', 'FAILED')) {
                try {
                    & (Join-Path $ScriptDir '..\jules\respond-jules-session.ps1') -SessionId ([string]$metadata['session_name']) -IssueNumber $ghIssueNumber -Repository $Context.Repository -Message $reworkMessage -UpdateIssueBody:$true -PostIssueComment:$true | Out-Null
                    $metadata.Remove('review_feedback')
                    $metadata['review_status'] = 'pending'
                    $metadata['human_gate'] = 'none'
                    Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                        status = 'in_progress'
                        comment = 'Review findings were sent back to Jules for follow-up work.'
                    } | Out-Null
                    continue
                } catch {
                    Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                        status = 'blocked'
                        comment = ('Jules rework handoff failed: {0}' -f $_.Exception.Message)
                    } | Out-Null
                    continue
                }
            }

            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = 'Review requested follow-up work, but the current Jules session is no longer reusable. Manual decision required.'
            } | Out-Null
            continue
        }

        if ($null -eq $session -and [string]$Context.Runtime.mode -ne 'draining') {
            try {
                $createdOutput = @(& (Join-Path $ScriptDir '..\jules\create-jules-session.ps1') -IssueNumber $ghIssueNumber -Repository $Context.Repository -AutoCreatePr -ValidateSource:$false -RemoveTodoUserLabel:$false)
            } catch {
                $guard = $null
                try {
                    $guard = Get-JulesDuplicateDispatchGuard -IssueNumber $ghIssueNumber -Repository $Context.Repository -ApiKey $env:JULES_API_KEY
                } catch {
                    $guard = $null
                }

                if ($null -ne $guard) {
                    $metadata['duplicate_guard_reason'] = [string]$guard.Reason
                }

                Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                    status = 'blocked'
                    comment = ('Jules session creation blocked: {0}' -f $_.Exception.Message)
                } | Out-Null
                continue
            }

            $created = Get-VorceStudiosLastObjectResult -InputObject $createdOutput
            if ($null -eq $created) {
                Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                    status = 'blocked'
                    comment = 'Jules session creation returned no usable result.'
                } | Out-Null
                continue
            }

            $createdSessionId = [string](Get-VorceStudiosSafePropertyValue -InputObject $created -PropertyName 'SessionId')
            $createdSessionName = [string](Get-VorceStudiosSafePropertyValue -InputObject $created -PropertyName 'SessionName')
            $createdSessionUrl = [string](Get-VorceStudiosSafePropertyValue -InputObject $created -PropertyName 'SessionUrl')
            if ([string]::IsNullOrWhiteSpace($createdSessionUrl) -and -not [string]::IsNullOrWhiteSpace($createdSessionName)) {
                $createdSessionUrl = 'https://jules.google.com/{0}' -f $createdSessionName
            }

            $metadata['session_id'] = $createdSessionId
            $metadata['session_name'] = $createdSessionName
            $metadata['review_status'] = 'pending'
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'in_progress'
                comment = if (-not [string]::IsNullOrWhiteSpace($createdSessionUrl)) {
                    ('Jules session started: {0}' -f $createdSessionUrl)
                } elseif (-not [string]::IsNullOrWhiteSpace($createdSessionName)) {
                    ('Jules session started: {0}' -f $createdSessionName)
                } else {
                    'Jules session started.'
                }
            } | Out-Null
            continue
        }

        $snapshot = & (Join-Path $ScriptDir '..\jules\monitor-jules-sessions.ps1') -IssueNumber $ghIssueNumber -Repository $Context.Repository -SyncIssueBody:$true
        $item = @($snapshot | Select-Object -First 1)[0]
        if ($null -eq $item) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.PullRequestUrl)) {
            $metadata['pr_url'] = [string]$item.PullRequestUrl
        }

        $needsAttention = $false
        if ($item.PSObject.Properties.Name -contains 'NeedsAttention') {
            $needsAttention = [bool]$item.NeedsAttention
        }

        if ($needsAttention) {
            if ([string]$item.State -eq 'AWAITING_PLAN_APPROVAL') {
                $metadata['human_gate'] = 'approval_required'
            } elseif ([string]$item.State -eq 'AWAITING_USER_FEEDBACK') {
                $metadata['human_gate'] = 'clarification'
            }
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('Jules attention required: {0}' -f [string]$item.LastActivity)
            } | Out-Null
            continue
        }

        $duplicateActiveSessionsDetected = $false
        if ($item.PSObject.Properties.Name -contains 'DuplicateActiveSessionsDetected') {
            $duplicateActiveSessionsDetected = [bool]$item.DuplicateActiveSessionsDetected
        }

        if ($duplicateActiveSessionsDetected) {
            $duplicateIds = @()
            if ($item.PSObject.Properties.Name -contains 'DuplicateActiveSessionIds') {
                $duplicateIds = @($item.DuplicateActiveSessionIds)
            }

            $metadata['human_gate'] = 'clarification'
            $metadata['duplicate_guard_reason'] = if ($item.PSObject.Properties.Name -contains 'DuplicateGuardReason') { [string]$item.DuplicateGuardReason } else { 'multiple_active_sessions' }
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('Duplicate active Jules sessions detected for GH #{0}: {1}' -f $ghIssueNumber, $(if ($duplicateIds.Count -gt 0) { $duplicateIds -join ', ' } else { 'unknown session ids' }))
            } | Out-Null
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$item.PullRequestUrl)) {
            $nextAgentKey = 'ops'
            if (([string]$metadata['risk_class'] -ne 'low') -or ([string]$metadata['ui_surface'] -eq 'true')) {
                $reviewTool = Get-VorceStudiosPreferredTool -Chain (Get-VorceStudiosReviewerChain -RiskClass ([string]$metadata['risk_class']))
                if (-not [string]::IsNullOrWhiteSpace($reviewTool)) {
                    $nextAgentKey = Get-VorceStudiosAgentKeyForTool -Tool $reviewTool
                }
            }

            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                assigneeAgentId = $Context.Agents[$nextAgentKey].id
                status = 'in_review'
                comment = ('Jules produced PR {0}; routed to {1}.' -f [string]$item.PullRequestUrl, $Context.Agents[$nextAgentKey].name)
            } | Out-Null
            continue
        }

        Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
            status = 'in_progress'
        } | Out-Null
    }
}

function Invoke-VorceStudiosReviewer {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$ReviewerRole,
        [Parameter(Mandatory)][string]$ToolName
    )

    $agentId = [string]$Context.Agents[$ReviewerRole].id
    $issues = Get-VorceStudiosOpenCompanyIssues -Context $Context | Where-Object { [string]$_.assigneeAgentId -eq $agentId }

    foreach ($issue in $issues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        $prUrl = if ($metadata.ContainsKey('pr_url')) { [string]$metadata['pr_url'] } else { $null }
        if ([string]::IsNullOrWhiteSpace($prUrl) -and $metadata.ContainsKey('gh_issue')) {
            $pr = Find-GitHubPullRequestForIssue -Repository $Context.Repository -IssueNumber ([int]$metadata['gh_issue']) -SessionId ([string]$metadata['session_id'])
            if ($pr) {
                $prUrl = [string]$pr.url
                $metadata['pr_url'] = $prUrl
            }
        }

        if ([string]::IsNullOrWhiteSpace($prUrl)) {
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = 'Review blocked: no PR found yet.'
            } | Out-Null
            continue
        }

        try {
            $prData = & gh pr view $prUrl --repo $Context.Repository --json number,title,url,additions,deletions,changedFiles,files,reviewDecision,isDraft,baseRefName,headRefName 2>$null | ConvertFrom-Json
            $diffText = & gh pr diff $prUrl --repo $Context.Repository 2>$null | Out-String
        } catch {
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('Review blocked: unable to inspect PR {0}.' -f $prUrl)
            } | Out-Null
            continue
        }

        $prTitle = [string](Get-VorceStudiosSafePropertyValue -InputObject $prData -PropertyName 'title')
        $prViewUrl = [string](Get-VorceStudiosSafePropertyValue -InputObject $prData -PropertyName 'url')
        $prChangedFiles = [string](Get-VorceStudiosSafePropertyValue -InputObject $prData -PropertyName 'changedFiles')
        $prAdditions = [string](Get-VorceStudiosSafePropertyValue -InputObject $prData -PropertyName 'additions')
        $prDeletions = [string](Get-VorceStudiosSafePropertyValue -InputObject $prData -PropertyName 'deletions')
        if ([string]::IsNullOrWhiteSpace($prTitle)) {
            $prTitle = $prUrl
        }
        if ([string]::IsNullOrWhiteSpace($prViewUrl)) {
            $prViewUrl = $prUrl
        }

        $diffExcerpt = ($diffText -split "`r?`n" | Select-Object -First 300) -join "`n"
        $reviewPrompt = @"
You are reviewing a Vorce pull request.

PR: $prTitle
URL: $prViewUrl
Changed files: $prChangedFiles
Additions: $prAdditions
Deletions: $prDeletions
Risk class: $($metadata['risk_class'])
UI surface: $($metadata['ui_surface'])

Return exactly this structure:
VERDICT: pass|changes_requested|manual_ui_required
SUMMARY: one short paragraph
FINDINGS:
- finding or 'none'

Patch excerpt:
$diffExcerpt
"@

        try {
            $result = Invoke-VorceStudiosReviewPrompt -ToolChain @($ToolName) -Prompt $reviewPrompt -WorkingDirectory (Get-VorceStudiosRoot)
            $text = [string]$result.stdout
        } catch {
            if (Test-VorceStudiosQuotaFailureText -Text $_.Exception.Message) {
                $fallbackChain = Get-VorceStudiosReviewerChain -RiskClass ([string]$metadata['risk_class'])
                $fallbackTool = Get-VorceStudiosPreferredTool -Chain ($fallbackChain | Where-Object { $_ -ne $ToolName })
                if (-not [string]::IsNullOrWhiteSpace($fallbackTool)) {
                    $nextAgentKey = Get-VorceStudiosAgentKeyForTool -Tool $fallbackTool
                    Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                        assigneeAgentId = $Context.Agents[$nextAgentKey].id
                        status = 'todo'
                        comment = ('Review re-routed from {0} to {1} because of quota or rate limits.' -f $ToolName, $fallbackTool)
                    } | Out-Null
                    continue
                }
            }

            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('Review failed on tool {0}: {1}' -f $ToolName, $_.Exception.Message)
            } | Out-Null
            continue
        }

        $metadata['last_review_tool'] = $ToolName
        $parsed = Get-VorceStudiosReviewResult -Text $text
        $metadata['last_review_summary'] = [string]$parsed.summary
        Add-VorceStudiosCommentSafe -IssueId $issue.id -Body ("## Automated Review ({0})`n`n{1}" -f $ToolName, $text)

        if ([string]$parsed.verdict -eq 'manual_ui_required') {
            $metadata['review_status'] = 'manual_ui_required'
            $metadata['human_gate'] = 'manual_ui_gate'
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                assigneeAgentId = $Context.Agents['ops'].id
                comment = 'Manual UI validation required before merge.'
            } | Out-Null
            continue
        }

        if ([string]$parsed.verdict -eq 'changes_requested') {
            $metadata['review_status'] = 'changes_requested'
            $metadata['human_gate'] = 'none'
            $feedbackLines = New-Object System.Collections.Generic.List[string]
            $feedbackLines.Add([string]$parsed.summary)
            foreach ($finding in @($parsed.findings | Select-Object -First 10)) {
                $feedbackLines.Add('- {0}' -f [string]$finding)
            }
            $metadata['review_feedback'] = ($feedbackLines -join "`n").Trim()
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                assigneeAgentId = $Context.Agents['jules'].id
                status = 'todo'
                comment = ('Automated review requested changes via {0}; routing back to Jules.' -f $ToolName)
            } | Out-Null
            continue
        }

        $metadata['review_status'] = 'passed'
        $metadata['human_gate'] = 'none'
        $metadata.Remove('review_feedback')
        Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
            assigneeAgentId = $Context.Agents['ops'].id
            status = 'in_review'
            comment = ('Automated review passed via {0}; routed to Ops.' -f $ToolName)
        } | Out-Null
    }
}

function Invoke-VorceStudiosOps {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $agentId = [string]$Context.Agents['ops'].id
    $issues = Get-VorceStudiosOpenCompanyIssues -Context $Context | Where-Object { [string]$_.assigneeAgentId -eq $agentId }
    $risk = Get-VorceStudiosPolicy -Name 'risk'

    foreach ($issue in $issues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        $prUrl = if ($metadata.ContainsKey('pr_url')) { [string]$metadata['pr_url'] } else { $null }
        if ([string]::IsNullOrWhiteSpace($prUrl)) { continue }

        $pr = Get-GitHubPullRequest -Repository $Context.Repository -PullRequestUrl $prUrl
        $checks = Get-GitHubPullRequestChecks -Repository $Context.Repository -PullRequestUrl $prUrl
        if ($null -eq $pr) {
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('Ops blocked: PR could not be loaded for {0}.' -f $prUrl)
            } | Out-Null
            continue
        }

        $pendingChecks = @($checks | Where-Object { [string]$_.state -notin @('SUCCESS', 'SKIPPED') })
        if ($pendingChecks.Count -gt 0) {
            $metadata['review_status'] = if ($metadata.ContainsKey('review_status')) { [string]$metadata['review_status'] } else { 'pending' }
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'in_review'
            } | Out-Null
            continue
        }

        if ([string]$pr.reviewDecision -eq 'CHANGES_REQUESTED') {
            $metadata['review_status'] = 'changes_requested'
            $metadata['review_feedback'] = 'GitHub review decision is CHANGES_REQUESTED. Inspect review threads and address the requested changes.'
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                assigneeAgentId = $Context.Agents['jules'].id
                status = 'todo'
                comment = 'GitHub review decision is CHANGES_REQUESTED; routing back for rework.'
            } | Out-Null
            continue
        }

        $requiresUiGate = ([string]$metadata['ui_surface'] -eq 'true')
        $requiresExtraReview = ([string]$metadata['risk_class'] -eq 'high')
        if ($requiresUiGate) {
            $metadata['review_status'] = if ([string]$metadata['review_status'] -eq 'manual_ui_required') { 'manual_ui_required' } else { 'passed' }
            $metadata['human_gate'] = 'manual_ui_gate'
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = 'PR checks are green, but manual UI validation is required.'
            } | Out-Null
            continue
        }

        if ($requiresExtraReview -and -not $metadata.ContainsKey('last_review_tool')) {
            $metadata['review_status'] = 'pending'
            $reviewTool = Get-VorceStudiosPreferredTool -Chain (Get-VorceStudiosReviewerChain -RiskClass 'high')
            $reviewAgentKey = if ([string]::IsNullOrWhiteSpace($reviewTool)) { 'codex_review' } else { Get-VorceStudiosAgentKeyForTool -Tool $reviewTool }
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                assigneeAgentId = $Context.Agents[$reviewAgentKey].id
                status = 'todo'
                comment = 'Extra review required by risk policy before merge.'
            } | Out-Null
            continue
        }

        $fastLane = ($pr.changedFiles -le $risk.MergeFastLane.MaxFiles) -and (($pr.additions + $pr.deletions) -le $risk.MergeFastLane.MaxNetLines) -and (-not $requiresExtraReview)
        $message = if ($fastLane) {
            'Checks passed. This PR qualifies for the low-risk fast lane and is ready for merge.'
        } else {
            'Checks passed. Ready for merge review by the owner.'
        }

        $metadata['review_status'] = 'passed'
        $metadata['human_gate'] = if ($fastLane) { 'none' } else { 'approval_required' }
        Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
            status = 'blocked'
            comment = $message
        } | Out-Null
    }
}

function Invoke-VorceStudiosCEO {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $issues = Get-VorceStudiosOpenCompanyIssues -Context $Context | Where-Object { [string]$_.status -eq 'blocked' }
    $briefingLines = New-Object System.Collections.Generic.List[string]
    $briefingLines.Add('## CEO Briefing')
    $briefingLines.Add('')

    foreach ($issue in $issues) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
        $approval = if ($metadata.ContainsKey('approval_id')) { Get-VorceStudiosApproval -ApprovalId ([string]$metadata['approval_id']) } else { $null }
        if ($null -ne $approval) {
            $metadata['approval_status'] = [string]$approval.status
        }

        $riskClass = if ($metadata.ContainsKey('risk_class')) { [string]$metadata['risk_class'] } else { 'low' }
        $reviewStatus = if ($metadata.ContainsKey('review_status')) { [string]$metadata['review_status'] } else { 'n_a' }
        $humanGate = if ($metadata.ContainsKey('human_gate')) { [string]$metadata['human_gate'] } else { 'none' }
        $approvalStatus = if ($null -eq $approval) { 'n_a' } else { [string]$approval.status }
        $githubUrl = Get-VorceStudiosGitHubIssueUrl -Context $Context -Metadata $metadata

        $briefingLines.Add(('- {0} | risk={1} | review={2} | human_gate={3} | approval={4}' -f [string]$issue.title, $riskClass, $reviewStatus, $humanGate, $approvalStatus))

        if ($null -ne $approval -and [string]$approval.status -eq 'approved') {
            if ($humanGate -eq 'manual_ui_gate') {
                $metadata['human_gate'] = 'none'
                if ($reviewStatus -eq 'manual_ui_required') {
                    $metadata['review_status'] = 'passed'
                }
                Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                    assigneeAgentId = $Context.Agents['ops'].id
                    status = 'in_review'
                    comment = 'Owner approved the manual gate. Routed back to Ops for final merge handling.'
                } | Out-Null
                continue
            }

            if ($reviewStatus -eq 'passed' -or $humanGate -eq 'approval_required') {
                $metadata['human_gate'] = 'none'
                Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                    assigneeAgentId = $Context.Agents['ops'].id
                    status = 'in_review'
                    comment = 'Owner approval received. Routed back to Ops for final merge handling.'
                } | Out-Null
                continue
            }
        }

        if ($null -ne $approval -and [string]$approval.status -eq 'rejected') {
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = 'Owner rejected the current proposal. Manual follow-up or a refined plan is required.'
            } | Out-Null
            continue
        }

        $requiresApproval = $false
        $gateType = ''
        $approvalSummary = ''
        if ($humanGate -eq 'manual_ui_gate') {
            $requiresApproval = $true
            $gateType = 'manual_ui_validation'
            $approvalSummary = 'Please validate the UI behaviour of this change and approve only if the visible behaviour matches expectations.'
        } elseif ($humanGate -eq 'approval_required') {
            $requiresApproval = $true
            $gateType = 'merge_review'
            $approvalSummary = 'Please approve or reject the merge recommendation for this PR.'
        } elseif ($riskClass -eq 'high' -and $reviewStatus -eq 'passed') {
            $requiresApproval = $true
            $gateType = 'high_risk_merge'
            $approvalSummary = 'High-risk change is ready for merge review and requires owner approval.'
            $metadata['human_gate'] = 'approval_required'
        } elseif ($humanGate -eq 'clarification') {
            $requiresApproval = $true
            $gateType = 'jules_clarification'
            $approvalSummary = 'Jules is waiting for clarification before continuing.'
        }

        if ($requiresApproval -and $null -eq $approval) {
            $approvalBody = if (-not [string]::IsNullOrWhiteSpace($githubUrl) -and -not [string]::IsNullOrWhiteSpace([string]$metadata['pr_url'])) {
                '{0} GH: {1} PR: {2}' -f $approvalSummary, $githubUrl, [string]$metadata['pr_url']
            } elseif (-not [string]::IsNullOrWhiteSpace($githubUrl)) {
                '{0} GH: {1}' -f $approvalSummary, $githubUrl
            } else {
                $approvalSummary
            }

            $approval = Ensure-VorceStudiosApprovalForIssue -Context $Context -Issue $issue -Metadata $metadata -GateType $gateType -Summary $approvalBody
            Update-VorceStudiosIssueMetadataAndState -Issue $issue -Context $Context -Metadata $metadata -Patch @{
                status = 'blocked'
                comment = ('CEO requested approval for {0}.' -f $gateType)
            } | Out-Null
            continue
        }
    }

    if ($briefingLines.Count -gt 2 -and $issues.Count -gt 0) {
        Add-VorceStudiosCommentSafe -IssueId ([string]$issues[0].id) -Body ($briefingLines -join "`n")
    }
}

$context = Get-VorceStudiosAgentContext
if ($null -eq $context) {
    return
}

switch ($Role) {
    'discovery' { Invoke-VorceStudiosDiscovery -Context $context }
    'chief_of_staff' { Invoke-VorceStudiosChiefOfStaff -Context $context }
    'jules' { Invoke-VorceStudiosJulesBuilder -Context $context }
    'gemini_review' { Invoke-VorceStudiosReviewer -Context $context -ReviewerRole 'gemini_review' -ToolName 'gemini' }
    'qwen_review' { Invoke-VorceStudiosReviewer -Context $context -ReviewerRole 'qwen_review' -ToolName 'qwen' }
    'codex_review' { Invoke-VorceStudiosReviewer -Context $context -ReviewerRole 'codex_review' -ToolName 'codex' }
    'ops' { Invoke-VorceStudiosOps -Context $context }
    'ceo' { Invoke-VorceStudiosCEO -Context $context }
    default { }
}
