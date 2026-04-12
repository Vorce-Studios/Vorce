Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')
. (Join-Path $PSScriptRoot 'IssueMetadata.ps1')
. (Join-Path $PSScriptRoot 'AfkMode.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\..') 'jules\jules-api.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\..') 'jules\jules-github.ps1')

$script:VorceProjectSyncSuspendedReason = $null

function ConvertTo-VorceStudiosIsoTimestamp {
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetimeoffset]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    return [string]$Value
}

function Get-VorceStudiosPlanningSnapshot {
    $raw = Read-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).PlanningSnapshotPath -Default @{
        updatedAt = $null
        repository = Get-VorceStudiosRepositorySlug
        records = @()
    }

    if ($raw -is [System.Collections.IDictionary]) {
        return [pscustomobject]@{
            updatedAt = if ($raw.ContainsKey('updatedAt')) { ConvertTo-VorceStudiosIsoTimestamp -Value $raw['updatedAt'] } else { $null }
            repository = if ($raw.ContainsKey('repository')) { [string]$raw['repository'] } else { Get-VorceStudiosRepositorySlug }
            records = if ($raw.ContainsKey('records')) { @($raw['records']) } else { @() }
        }
    }

    if ($null -eq $raw) {
        return [pscustomobject]@{
            updatedAt = $null
            repository = Get-VorceStudiosRepositorySlug
            records = @()
        }
    }

    return [pscustomobject]@{
        updatedAt = ConvertTo-VorceStudiosIsoTimestamp -Value $raw.updatedAt
        repository = [string]$raw.repository
        records = @($raw.records)
    }
}

function Set-VorceStudiosPlanningSnapshot {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [string]$Repository = ''
    )

    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).PlanningSnapshotPath -Value @{
        updatedAt = Get-VorceStudiosTimestamp
        repository = if (-not [string]::IsNullOrWhiteSpace($Repository)) { $Repository } else { Get-VorceStudiosRepositorySlug }
        records = @($Records)
    }
}

function Find-VorceStudiosPlanningRecord {
    param(
        [Parameter(Mandatory)][int]$IssueNumber
    )

    $records = @((Get-VorceStudiosPlanningSnapshot).records)
    $matches = @(
        $records |
            Where-Object { [int]$_.issueNumber -eq $IssueNumber } |
            Select-Object -First 1
    )
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Get-VorceStudiosGitHubLabelNames {
    param(
        [AllowNull()][object]$Issue
    )

    if ($null -eq $Issue) {
        return @()
    }

    return @(
        $Issue.labels |
            ForEach-Object {
                if ($_ -is [string]) { $_ } else { [string]$_.name }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
}

function Get-VorceStudiosProjectStatusName {
    param(
        [AllowNull()][object]$Issue
    )

    if ($null -eq $Issue -or -not $Issue.projectItems) {
        return $null
    }

    foreach ($item in @($Issue.projectItems)) {
        if ([string]$item.title -eq '@Vorce Project Manager' -and $item.status) {
            return [string]$item.status.name
        }
    }

    return $null
}

function Get-VorceStudiosPlanningPriorityBucket {
    param(
        [Parameter(Mandatory)][int]$Score
    )

    $policy = Get-VorceStudiosPolicy -Name 'planning'
    if ($Score -ge [int]$policy.Buckets.Critical) { return 'critical' }
    if ($Score -ge [int]$policy.Buckets.High) { return 'high' }
    if ($Score -ge [int]$policy.Buckets.Medium) { return 'medium' }
    return 'low'
}

function Get-VorceStudiosPlanningReadiness {
    param(
        [AllowNull()][string[]]$Labels,
        [AllowNull()][string]$ProjectStatus
    )

    if ($null -eq $Labels) {
        $Labels = @()
    }

    if ($Labels -contains 'Todo-UserISU') { return 'awaiting_user_approval' }
    if ($Labels -contains 'status: blocked') { return 'blocked' }
    if ($Labels -contains 'status: needs-review' -or $ProjectStatus -eq 'Review PR') { return 'in_review' }
    if ($Labels -contains 'status: needs-testing' -or $ProjectStatus -eq 'QA Test') { return 'awaiting_ui_test' }
    if ($Labels -contains 'status: in-progress' -or $ProjectStatus -in @('JulesSession', 'PR-Checks')) { return 'active' }
    return 'ready'
}

function Get-VorceStudiosPlanningSummary {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][int]$Score,
        [Parameter(Mandatory)][string]$Bucket,
        [Parameter(Mandatory)][string]$Readiness
    )

    $labels = Get-VorceStudiosGitHubLabelNames -Issue $Issue
    $criticalHints = @($labels | Where-Object { $_ -in @('bug', 'security', 'performance', 'testing', 'dependencies') })
    $hintText = if ($criticalHints.Count -gt 0) { $criticalHints -join ', ' } else { 'general backlog' }
    return ('{0} / score {1} / {2}' -f $Bucket, $Score, $Readiness.Replace('_', ' '))
}

function Invoke-VorceStudiosPlanningSweep {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    $policy = Get-VorceStudiosPolicy -Name 'planning'
    $issues = @(
        & gh issue list --repo $Repository --state open --limit ([int]$policy.Discovery.IssueLimit) --json number,title,body,labels,updatedAt,url,projectItems 2>$null |
            ConvertFrom-Json
    )

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($issue in $issues) {
        $labels = Get-VorceStudiosGitHubLabelNames -Issue $issue
        $projectStatus = Get-VorceStudiosProjectStatusName -Issue $issue
        $score = 0

        foreach ($entry in (Get-VorceStudiosPolicy -Name 'planning').Scoring.PriorityWeights.GetEnumerator()) {
            if ($labels -contains [string]$entry.Key) {
                $score += [int]$entry.Value
            }
        }

        foreach ($entry in (Get-VorceStudiosPolicy -Name 'planning').Scoring.LabelBonuses.GetEnumerator()) {
            if ($labels -contains [string]$entry.Key) {
                $score += [int]$entry.Value
            }
        }

        foreach ($entry in (Get-VorceStudiosPolicy -Name 'planning').Scoring.StatusPenalties.GetEnumerator()) {
            if ($labels -contains [string]$entry.Key) {
                $score += [int]$entry.Value
            }
        }

        foreach ($entry in (Get-VorceStudiosPolicy -Name 'planning').Scoring.ProjectStatusBonuses.GetEnumerator()) {
            if ($projectStatus -eq [string]$entry.Key) {
                $score += [int]$entry.Value
            }
        }

        if ([string]$issue.title -match '(^I_|^MF-|bug|fix|unsafe|ffi|render|output|timeline|migration)') {
            $score += 12
        }

        $bucket = Get-VorceStudiosPlanningPriorityBucket -Score $score
        $readiness = Get-VorceStudiosPlanningReadiness -Labels $labels -ProjectStatus $projectStatus
        $records.Add([pscustomobject]@{
            issueNumber = [int]$issue.number
            title = [string]$issue.title
            url = [string]$issue.url
            score = $score
            bucket = $bucket
            readiness = $readiness
            projectStatus = $projectStatus
            labels = @($labels)
            summary = Get-VorceStudiosPlanningSummary -Issue $issue -Score $score -Bucket $bucket -Readiness $readiness
            updatedAt = [string]$issue.updatedAt
        })
    }

    $ordered = @($records | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'updatedAt'; Descending = $true })
    Set-VorceStudiosPlanningSnapshot -Records $ordered -Repository $Repository
    return $ordered
}

function Ensure-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    $policy = Get-VorceStudiosPolicy -Name 'sync'
    $existing = @(
        & gh label list --repo $Repository --limit 200 2>$null |
            ForEach-Object { ($_ -split "`t")[0].Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($label in @($policy.GitHub.Labels.Ensure)) {
        if ($existing -contains [string]$label.Name) {
            continue
        }

        & gh label create ([string]$label.Name) --repo $Repository --color ([string]$label.Color).TrimStart('#') --description ([string]$label.Description) 2>$null | Out-Null
    }
}

function Ensure-VorceStudiosProjectFields {
    $policy = Get-VorceStudiosPolicy -Name 'sync'
    $owner = [string]$policy.GitHub.ProjectOwner
    $number = [int]$policy.GitHub.ProjectNumber
    $raw = & gh project field-list $number --owner $owner --format json 2>$null
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        Write-Warning ("GitHub Project-Felder konnten aktuell nicht gelesen werden: {0}#{1}" -f $owner, $number)
        return
    }

    try {
        $current = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning ("GitHub Project-Felder liefern kein auswertbares JSON: {0}" -f $_.Exception.Message)
        return
    }

    if ($null -eq $current -or -not ($current.PSObject.Properties.Name -contains 'fields')) {
        Write-Warning ("GitHub Project-Felder fehlen im Rueckgabeobjekt fuer {0}#{1}" -f $owner, $number)
        return
    }

    $existingNames = @($current.fields | ForEach-Object { [string]$_.name })

    foreach ($field in @($policy.GitHub.ProjectFields.Required)) {
        if ($existingNames -contains [string]$field.Name) {
            continue
        }

        $args = @('project', 'field-create', [string]$number, '--owner', $owner, '--name', [string]$field.Name, '--data-type', [string]$field.DataType)
        if ([string]$field.DataType -eq 'SINGLE_SELECT') {
            $args += @('--single-select-options', (@($field.Options) -join ','))
        }

        & gh @args 2>$null | Out-Null
    }
}

function Get-VorceStudiosManagedGitHubLabels {
    return @((Get-VorceStudiosPolicy -Name 'sync').GitHub.Labels.Managed)
}

function Set-VorceStudiosManagedGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string[]]$DesiredLabels
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $existing = Get-GitHubIssueLabelNames -Issue $issue
    $managed = Get-VorceStudiosManagedGitHubLabels
    $desired = @($DesiredLabels | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    foreach ($label in $managed) {
        if (($existing -contains $label) -and ($desired -notcontains $label)) {
            Remove-GitHubIssueLabel -Repository $Repository -IssueNumber $IssueNumber -LabelName $label
        }
    }

    $missing = @($desired | Where-Object { $existing -notcontains $_ })
    if ($missing.Count -gt 0) {
        Add-GitHubIssueLabels -Repository $Repository -IssueNumber $IssueNumber -LabelNames $missing
    }
}

function Get-VorceStudiosApprovalSnapshot {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$Metadata
    )

    if (-not $Metadata.ContainsKey('approval_id')) {
        return $null
    }

    $approval = Get-VorceStudiosApproval -ApprovalId ([string]$Metadata['approval_id'])
    if ($null -eq $approval) {
        return $null
    }

    return $approval
}

function Get-VorceStudiosPaperclipStatusLabelSet {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][hashtable]$Metadata,
        [AllowNull()][object]$Approval,
        [AllowNull()][object]$PlanningRecord
    )

    $labels = New-Object System.Collections.Generic.List[string]
    $labels.Add('sync: paperclip')

    $reviewStatus = if ($Metadata.ContainsKey('review_status')) { [string]$Metadata['review_status'] } else { 'n_a' }
    $humanGate = if ($Metadata.ContainsKey('human_gate')) { [string]$Metadata['human_gate'] } else { 'none' }
    $approvalStatus = if ($null -ne $Approval) { [string]$Approval.status } else { 'n_a' }

    switch ([string]$Issue.status) {
        'todo' { $labels.Add('status: in-progress') }
        'in_progress' { $labels.Add('status: in-progress') }
        'in_review' { $labels.Add('status: needs-review') }
        'blocked' {
            if ($humanGate -eq 'manual_ui_gate') {
                $labels.Add('status: needs-testing')
                $labels.Add('gate: ui-test')
            } elseif ($approvalStatus -eq 'pending') {
                $labels.Add('status: blocked')
                $labels.Add('gate: approval')
            } elseif ($reviewStatus -eq 'passed') {
                $labels.Add('status: ready-to-merge')
            } else {
                $labels.Add('status: blocked')
            }
        }
        'done' { $labels.Add('status: ready-to-merge') }
    }

    switch ($reviewStatus) {
        'passed' { $labels.Add('review: passed') }
        'changes_requested' { $labels.Add('review: changes-requested') }
    }

    return @($labels | Select-Object -Unique)
}

function Get-VorceStudiosProjectFieldValueMap {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][hashtable]$Metadata,
        [AllowNull()][object]$PlanningRecord,
        [AllowNull()][object]$Approval,
        [AllowNull()][object]$BaseSync
    )

    $names = (Get-VorceStudiosPolicy -Name 'sync').GitHub.ProjectFields.Names
    $priorityMap = @{
        critical = 'A'
        high = 'A'
        medium = 'B'
        low = 'C'
    }
    $toolAgentMap = @{
        jules = 'AgentJules'
        gemini = 'Gemini CLI'
        qwen = 'Qwen CLI'
        codex = 'Codex CLI'
        copilot = 'Copilot CLI'
        antigravity = 'Antigravity'
        atlas = 'Atlas'
    }

    $bucket = if ($null -ne $PlanningRecord) { [string]$PlanningRecord.bucket } else { [string]$Issue.priority }
    $reviewStatus = if ($Metadata.ContainsKey('review_status')) { [string]$Metadata['review_status'] } else { 'n_a' }
    $humanGate = if ($Metadata.ContainsKey('human_gate')) { [string]$Metadata['human_gate'] } else { 'none' }
    $approvalMapped = if ($null -eq $Approval) {
        $null
    } else {
        switch ([string]$Approval.status) {
            'approved' { 'approved' }
            'rejected' { 'rejected' }
            default { 'clarification' }
        }
    }

    $areaLabel = $null
    foreach ($label in @($Metadata['gh_labels'])) {
        if ([string]$label -like 'phase-*' -or [string]$label -like 'component:*') {
            $areaLabel = [string]$label
            break
        }
    }

    return @{
        ($names.Agent) = if ($Metadata.ContainsKey('executor_tool') -and $toolAgentMap.ContainsKey([string]$Metadata['executor_tool'])) { [string]$toolAgentMap[[string]$Metadata['executor_tool']] } else { $null }
        ($names.SubAgent) = if ([string]$Issue.status -eq 'in_review') { 'code_reviewer' } elseif ([string]$Metadata['task_type'] -eq 'architecture') { 'architect' } elseif ([string]$Issue.status -eq 'blocked' -and $humanGate -eq 'manual_ui_gate') { 'tester' } else { 'coder' }
        ($names.PermitIssue) = $approvalMapped
        ($names.TaskType) = switch ([string]$Metadata['task_type']) {
            'architecture' { 'Refactor' }
            'review' { 'Test' }
            default {
                if ([string]$Metadata['risk_class'] -eq 'high') { 'Fix' } else { 'Feature' }
            }
        }
        ($names.Priority) = if ($priorityMap.ContainsKey($bucket)) { [string]$priorityMap[$bucket] } else { $null }
        ($names.Description) = if ($null -ne $PlanningRecord) { [string]$PlanningRecord.summary } else { $null }
        ($names.TaskId) = [string]$Issue.identifier
        ($names.Area) = $areaLabel
        ($names.ReviewStatus) = $reviewStatus
        ($names.HumanGate) = $humanGate
        ($names.PaperclipIssue) = [string]$Issue.identifier
    }
}

function Set-VorceStudiosProjectExtraFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][hashtable]$FieldMap
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$script:VorceProjectSyncSuspendedReason)) {
        return $false
    }

    try {
        $context = Get-VorceProjectContext -Repository $Repository
        if ($null -eq $context) {
            return $false
        }

        $issueContentId = Get-GitHubIssueContentId -Repository $Repository -IssueNumber $IssueNumber
        if ([string]::IsNullOrWhiteSpace($issueContentId)) {
            return $false
        }

        $itemId = Ensure-VorceProjectItem -Context $context -IssueContentId $issueContentId
        foreach ($entry in $FieldMap.GetEnumerator()) {
            $field = Get-VorceProjectField -Context $context -FieldName ([string]$entry.Key)
            if ($null -eq $field) { continue }
            Set-VorceProjectFieldValue -Context $context -ItemId $itemId -Field $field -Value ([string]$entry.Value)
        }

        return $true
    } catch {
        $message = $_.Exception.Message
        $isTransientProjectError = (
            $message -match 'rate limit' -or
            $message -match 'unknown owner type' -or
            $message -match 'Project V2 .+ wurde nicht gefunden'
        )

        if ($isTransientProjectError) {
            if ([string]::IsNullOrWhiteSpace([string]$script:VorceProjectSyncSuspendedReason)) {
                Write-Warning ("Project-V2-Sync wird fuer diesen Lauf ausgesetzt: {0}" -f $message)
            }
            $script:VorceProjectSyncSuspendedReason = $message
            return $false
        }

        throw
    }
}

function Format-VorceStudiosMarkdownValue {
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return '_n/a_' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return '_n/a_' }
    if ($text -match '^https?://') { return $text }
    return ('`{0}`' -f $text)
}

function Format-VorceStudiosTrackingBlock {
    param(
        [Parameter(Mandatory)][hashtable]$Fields
    )

    $approvalDisplay = if ([string]::IsNullOrWhiteSpace([string]$Fields.ApprovalStatus) -or [string]$Fields.ApprovalStatus -eq 'n_a') {
        $null
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$Fields.ApprovalChannel) -and [string]$Fields.ApprovalChannel -ne 'paperclip') {
        '{0} via {1}' -f [string]$Fields.ApprovalStatus, [string]$Fields.ApprovalChannel
    } else {
        [string]$Fields.ApprovalStatus
    }

    $lines = @(
        $script:JulesIssueBlockStart,
        ('<!-- jules-session-id: {0} -->' -f [string]$Fields.SessionId),
        ('<!-- jules-session-name: {0} -->' -f [string]$Fields.SessionName),
        ('<!-- vorce-queue-state: {0} -->' -f [string]$Fields.QueueState),
        ('<!-- vorce-remote-state: {0} -->' -f [string]$Fields.RemoteState),
        ('<!-- vorce-work-branch: {0} -->' -f [string]$Fields.WorkBranch),
        ('<!-- vorce-last-update: {0} -->' -f [string]$Fields.LastUpdate),
        ('<!-- vorce-paperclip-issue-id: {0} -->' -f [string]$Fields.PaperclipIssueId),
        ('<!-- vorce-paperclip-issue-key: {0} -->' -f [string]$Fields.PaperclipIssueKey),
        ('<!-- vorce-orchestration-status: {0} -->' -f [string]$Fields.OrchestrationStatus),
        ('<!-- vorce-review-status: {0} -->' -f [string]$Fields.ReviewStatus),
        ('<!-- vorce-human-gate: {0} -->' -f [string]$Fields.HumanGate),
        ('<!-- vorce-approval-id: {0} -->' -f [string]$Fields.ApprovalId),
        ('<!-- vorce-approval-status: {0} -->' -f [string]$Fields.ApprovalStatus),
        ('<!-- vorce-executor: {0} -->' -f [string]$Fields.Executor),
        ('<!-- vorce-planner-score: {0} -->' -f [string]$Fields.PlannerScore),
        ('<!-- vorce-planner-bucket: {0} -->' -f [string]$Fields.PlannerBucket),
        ('<!-- vorce-planner-updated: {0} -->' -f [string]$Fields.PlannerUpdatedAt),
        '## Vorce Project Manager',
        ('- Queue State: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.QueueState)),
        ('- Remote State: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.RemoteState)),
        ('- Orchestration Status: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.OrchestrationStatus)),
        ('- Work Branch: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.WorkBranch)),
        ('- Linked PR: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.PullRequestUrl)),
        ('- Current Executor: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.Executor)),
        ('- Review Status: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.ReviewStatus)),
        ('- Human Gate: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.HumanGate)),
        ('- Approval: {0}' -f (Format-VorceStudiosMarkdownValue -Value $approvalDisplay)),
        ('- Planning: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.PlanningSummary)),
        ('- Last Update: {0}' -f (Format-VorceStudiosMarkdownValue -Value $Fields.LastUpdate)),
        $script:JulesIssueBlockEnd
    )

    return ($lines -join "`n")
}

function Upsert-VorceStudiosTrackingBlock {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][hashtable]$Fields
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { '' } else { [string]$issue.body }
    $block = Format-VorceStudiosTrackingBlock -Fields $Fields
    $pattern = [regex]::Escape($script:JulesIssueBlockStart) + '.*?' + [regex]::Escape($script:JulesIssueBlockEnd)
    $cleanBody = [regex]::Replace($body, "(?:\s*)$pattern(?:\s*)", '', [System.Text.RegularExpressions.RegexOptions]::Singleline).Trim()

    $updatedBody = if ([string]::IsNullOrWhiteSpace($cleanBody)) {
        $block
    } else {
        "{0}{1}{1}{2}" -f $cleanBody, [Environment]::NewLine, $block
    }

    Set-GitHubIssueBody -Repository $Repository -IssueNumber $IssueNumber -Body $updatedBody
}

function Get-VorceStudiosSessionSnapshot {
    param(
        [Parameter(Mandatory)][hashtable]$Metadata
    )

    if (-not $Metadata.ContainsKey('session_name')) {
        return @{
            Session = $null
            LatestActivity = $null
            FetchFailed = $false
            ErrorMessage = ''
        }
    }

    try {
        $session = Get-JulesSession -SessionIdOrName ([string]$Metadata['session_name']) -ApiKey $env:JULES_API_KEY
        $latest = $null
        if ($null -ne $session) {
            $activities = Get-AllJulesActivities -SessionIdOrName ([string]$Metadata['session_name']) -ApiKey $env:JULES_API_KEY -MaxPages 2
            $latest = Get-JulesLatestActivity -Activities $activities
        }

        return @{
            Session = $session
            LatestActivity = $latest
            FetchFailed = $false
            ErrorMessage = ''
        }
    } catch {
        return @{
            Session = $null
            LatestActivity = $null
            FetchFailed = $true
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Sync-VorceStudiosIssueToGitHub {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][object]$Issue
    )

    $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$Issue.description)
    if (-not $metadata.ContainsKey('gh_issue')) {
        return $null
    }

    $ghIssueNumber = [int]$metadata['gh_issue']
    if (
        (-not $metadata.ContainsKey('session_name')) -or
        [string]::IsNullOrWhiteSpace([string]$metadata['session_name'])
    ) {
        $trackedReference = Get-JulesSessionReferenceFromIssue -Repository $Context.Repository -IssueNumber $ghIssueNumber
        if ($null -ne $trackedReference) {
            if (-not [string]::IsNullOrWhiteSpace([string]$trackedReference.SessionName)) {
                $metadata['session_name'] = [string]$trackedReference.SessionName
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$trackedReference.SessionId)) {
                $metadata['session_id'] = [string]$trackedReference.SessionId
            }
        }
    }

    $sessionSnapshot = Get-VorceStudiosSessionSnapshot -Metadata $metadata
    try {
        $baseSync = Sync-VorceIssueTracking -Repository $Context.Repository -IssueNumber $ghIssueNumber -Session $sessionSnapshot.Session -LatestActivity $sessionSnapshot.LatestActivity -StartingBranch ([string]$metadata['work_branch']) -SourceName 'Vorce-Studios'
    } catch {
        Write-Warning ("Basis-GitHub-Sync fuer GH #{0} laeuft im Fallback-Modus: {1}" -f $ghIssueNumber, $_.Exception.Message)
        $baseSync = [pscustomobject]@{
            SessionId = if ($metadata.ContainsKey('session_id')) { [string]$metadata['session_id'] } else { '' }
            SessionName = if ($metadata.ContainsKey('session_name')) { [string]$metadata['session_name'] } else { '' }
            QueueState = if ([string]$Issue.status -eq 'blocked') { 'blocked' } elseif ([string]$Issue.status -eq 'todo') { 'approved-awaiting-dispatch' } else { 'issue-only' }
            RemoteState = if (-not [string]::IsNullOrWhiteSpace([string]$metadata['pr_url'])) {
                'pr-open'
            } elseif ($sessionSnapshot.FetchFailed -and -not [string]::IsNullOrWhiteSpace([string]$metadata['session_name'])) {
                'stale-session-reference'
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$metadata['session_name'])) {
                'awaiting-session'
            } else {
                'issue-only'
            }
            WorkBranch = if ($metadata.ContainsKey('work_branch')) { [string]$metadata['work_branch'] } else { '' }
            PullRequestUrl = if ($metadata.ContainsKey('pr_url')) { [string]$metadata['pr_url'] } else { '' }
            LastUpdate = Get-VorceStudiosTimestamp
        }
    }
    $approval = Get-VorceStudiosApprovalSnapshot -Context $Context -Metadata $metadata
    $planningRecord = Find-VorceStudiosPlanningRecord -IssueNumber $ghIssueNumber
    $metadata['gh_labels'] = Get-VorceStudiosGitHubLabelNames -Issue (Get-GitHubIssue -Repository $Context.Repository -IssueNumber $ghIssueNumber)

    $reviewStatus = if ($metadata.ContainsKey('review_status')) { [string]$metadata['review_status'] } else { 'n_a' }
    $humanGate = if ($metadata.ContainsKey('human_gate')) { [string]$metadata['human_gate'] } else { 'none' }
    $approvalStatus = if ($null -eq $approval) { 'n_a' } else { [string]$approval.status }
    $approvalChannel = if ($approvalStatus -eq 'pending') { Get-VorceStudiosPreferredApprovalChannel } else { 'paperclip' }

    $orchestrationStatus = switch ([string]$Issue.status) {
        'backlog' { 'planned' }
        'todo' { 'queued' }
        'in_progress' { 'executing' }
        'in_review' { 'in_review' }
        'blocked' {
            if ($approvalStatus -eq 'pending') { 'awaiting_approval' }
            elseif ($humanGate -eq 'manual_ui_gate') { 'awaiting_ui_validation' }
            elseif ($reviewStatus -eq 'passed') { 'ready_to_merge' }
            else { 'blocked' }
        }
        'done' { 'done' }
        'cancelled' { 'cancelled' }
        default { [string]$Issue.status }
    }

    $fields = @{
        SessionId = [string]$baseSync.SessionId
        SessionName = [string]$baseSync.SessionName
        QueueState = [string]$baseSync.QueueState
        RemoteState = [string]$baseSync.RemoteState
        WorkBranch = [string]$baseSync.WorkBranch
        PullRequestUrl = [string]$baseSync.PullRequestUrl
        LastUpdate = [string]$baseSync.LastUpdate
        PaperclipIssueId = [string]$Issue.id
        PaperclipIssueKey = [string]$Issue.identifier
        OrchestrationStatus = $orchestrationStatus
        ReviewStatus = $reviewStatus
        HumanGate = $humanGate
        ApprovalId = if ($null -eq $approval) { '' } else { [string]$approval.id }
        ApprovalStatus = $approvalStatus
        ApprovalChannel = $approvalChannel
        Executor = if ($metadata.ContainsKey('executor_tool')) { [string]$metadata['executor_tool'] } else { [string]$metadata['preferred_executor'] }
        PlannerScore = if ($null -eq $planningRecord) { '' } else { [string]$planningRecord.score }
        PlannerBucket = if ($null -eq $planningRecord) { '' } else { [string]$planningRecord.bucket }
        PlannerUpdatedAt = if ($null -eq (Get-VorceStudiosPlanningSnapshot).updatedAt) { '' } else { [string](Get-VorceStudiosPlanningSnapshot).updatedAt }
        PlanningSummary = if ($null -eq $planningRecord) { '' } else { [string]$planningRecord.summary }
    }

    Upsert-VorceStudiosTrackingBlock -Repository $Context.Repository -IssueNumber $ghIssueNumber -Fields $fields
    Set-VorceStudiosManagedGitHubLabels -Repository $Context.Repository -IssueNumber $ghIssueNumber -DesiredLabels (Get-VorceStudiosPaperclipStatusLabelSet -Issue $Issue -Metadata $metadata -Approval $approval -PlanningRecord $planningRecord)
    try {
        Set-VorceStudiosProjectExtraFields -Repository $Context.Repository -IssueNumber $ghIssueNumber -FieldMap (Get-VorceStudiosProjectFieldValueMap -Issue $Issue -Metadata $metadata -PlanningRecord $planningRecord -Approval $approval -BaseSync $baseSync) | Out-Null
    } catch {
        Write-Warning ("Project-V2-Sync fuer GH #{0} wird spaeter erneut versucht: {1}" -f $ghIssueNumber, $_.Exception.Message)
    }

    return [pscustomobject]$fields
}
