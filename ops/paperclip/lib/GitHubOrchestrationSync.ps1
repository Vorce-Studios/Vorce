Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')
. (Join-Path (Join-Path $PSScriptRoot '..\..\..') 'scripts\paperclip\lib\IssueMetadata.ps1')

function Get-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    $json = gh label list --repo $Repository --limit 200 --json name,color,description 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        return @()
    }

    return @($json | ConvertFrom-Json)
}

function Ensure-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    $syncPolicy = Get-VorceStudiosPolicy -Name 'sync'
    $existingByName = @{}
    foreach ($label in @(Get-VorceStudiosGitHubLabels -Repository $Repository)) {
        $existingByName[[string]$label.name] = $label
    }

    foreach ($desired in @($syncPolicy.GitHub.Labels.Ensure)) {
        $name = [string]$desired.Name
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        if ($existingByName.ContainsKey($name)) {
            continue
        }

        gh label create $name --repo $Repository --color ([string]$desired.Color) --description ([string]$desired.Description) 2>$null | Out-Null
    }

    return $true
}

function Ensure-VorceStudiosProjectFields {
    return $true
}

function Get-VorceStudiosGitHubIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [ValidateSet('open', 'closed', 'all')][string]$State = 'all',
        [int]$Limit = 200
    )

    $json = gh issue list --repo $Repository --state $State --limit $Limit --json number,title,body,url,updatedAt,state,labels 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        throw "GitHub Issues fuer '$Repository' konnten nicht geladen werden."
    }

    return @($json | ConvertFrom-Json)
}

function Get-VorceStudiosGitHubIssueLabelNames {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    return @(
        @($Issue.labels) |
            ForEach-Object { ([string]$_.name).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-VorceStudiosGitHubIssueBodyText {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    $parts = @(
        [string]$Issue.title,
        [string]$Issue.body
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    return (($parts -join "`n") ?? '').ToLowerInvariant()
}

function Resolve-VorceStudiosGitHubIssueGoalKey {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    $policy = Get-VorceStudiosPolicy -Name 'goals'
    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    $bodyText = Get-VorceStudiosGitHubIssueBodyText -Issue $Issue

    foreach ($goal in @($policy.Goals)) {
        $goalLabels = @([string[]]$goal.Labels | ForEach-Object { $_.ToLowerInvariant() })
        if ($goalLabels.Count -gt 0 -and @($labels | Where-Object { $goalLabels -contains $_ }).Count -gt 0) {
            return [string]$goal.Id
        }
    }

    if ($bodyText -match 'paperclip|plugin|ci|build|merge|release|packag|sync|control plane') {
        return 'R1'
    }
    if ($bodyText -match 'render|audio|project|import|persist|save|load|crash|panic|bug|regression') {
        return 'R2'
    }
    if ($bodyText -match 'feature|workflow|editor|timeline|ui|ux|preset|export|integration') {
        return 'R3'
    }
    if ($bodyText -match 'review|verify|jules|pr|pull request') {
        return 'R4'
    }

    return 'R3'
}

function Resolve-VorceStudiosGitHubIssuePriority {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][string]$GoalKey
    )

    $policy = Get-VorceStudiosPolicy -Name 'goals'
    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    $blockerLabels = @([string[]]$policy.Prioritization.BlockerLabels | ForEach-Object { $_.ToLowerInvariant() })

    if (@($labels | Where-Object { $blockerLabels -contains $_ }).Count -gt 0) {
        return 'critical'
    }

    switch ($GoalKey) {
        'R1' { return 'critical' }
        'R2' { return 'high' }
        'R3' { return 'medium' }
        'R4' { return 'medium' }
        default { return 'low' }
    }
}

function Resolve-VorceStudiosGitHubIssueSequence {
    param(
        [Parameter(Mandatory)][string]$GoalKey
    )

    switch ($GoalKey) {
        'R1' { return 'S1' }
        'R5' { return 'S1' }
        'R2' { return 'S2' }
        'R3' { return 'S3' }
        'R4' { return 'S4' }
        default { return 'S3' }
    }
}

function Get-VorceStudiosGitHubIssueSequenceRank {
    param(
        [Parameter(Mandatory)][string]$SequenceId
    )

    switch ($SequenceId) {
        'S1' { return 1 }
        'S2' { return 2 }
        'S3' { return 3 }
        'S4' { return 4 }
        default { return 99 }
    }
}

function Get-VorceStudiosPriorityRank {
    param(
        [Parameter(Mandatory)][string]$Priority
    )

    switch ($Priority) {
        'critical' { return 1 }
        'high' { return 2 }
        'medium' { return 3 }
        'low' { return 4 }
        default { return 99 }
    }
}

function ConvertTo-VorceStudiosGitHubIssueDescription {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][string]$GoalKey,
        [Parameter(Mandatory)][string]$SequenceId
    )

    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    $metadata = @{
        source = 'github'
        gh_issue = [string]$Issue.number
        gh_url = [string]$Issue.url
        gh_state = [string]$Issue.state
        gh_updated_at = [string]$Issue.updatedAt
        gh_labels = $labels
        goal_key = $GoalKey
        release_sequence = $SequenceId
    }

    $labelText = if ($labels.Count -gt 0) { $labels -join ', ' } else { 'none' }
    $bodyText = [string]$Issue.body
    if ([string]::IsNullOrWhiteSpace($bodyText)) {
        $bodyText = '_No GitHub body provided._'
    }

    $text = @"
GitHub source issue for the official Vorce release plan.

Repository: $Repository
GitHub issue: #$($Issue.number)
URL: $($Issue.url)
State: $($Issue.state)
Release sequence: $SequenceId
Goal bucket: $GoalKey
Labels: $labelText

GitHub body:

$bodyText
"@

    return Set-VorceStudiosIssueMetadata -Text $text -Metadata $metadata
}

function Get-VorceStudiosPlanningSnapshotPath {
    $paths = Get-VorceStudiosPaths
    return (Join-Path $paths.RuntimeRoot 'planning-snapshot.json')
}

function Get-VorceStudiosPlanningSnapshot {
    $path = Get-VorceStudiosPlanningSnapshotPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{
            updatedAt = $null
            items = @()
        }
    }

    return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable)
}

function Invoke-VorceStudiosPlanningSweep {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 200
    )

    $issues = @(Get-VorceStudiosGitHubIssues -Repository $Repository -State 'open' -Limit $Limit)
    $records = foreach ($issue in $issues) {
        $goalKey = Resolve-VorceStudiosGitHubIssueGoalKey -Issue $issue
        $sequenceId = Resolve-VorceStudiosGitHubIssueSequence -GoalKey $goalKey
        $priority = Resolve-VorceStudiosGitHubIssuePriority -Issue $issue -GoalKey $goalKey
        [pscustomobject]@{
            number = [int]$issue.number
            title = [string]$issue.title
            url = [string]$issue.url
            goalKey = $goalKey
            sequenceId = $sequenceId
            bucket = $priority
            priority = $priority
            labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $issue)
            updatedAt = [string]$issue.updatedAt
        }
    }

    $sorted = @(
        $records |
            Sort-Object `
                @{ Expression = { Get-VorceStudiosGitHubIssueSequenceRank -SequenceId ([string]$_.sequenceId) } }, `
                @{ Expression = { Get-VorceStudiosPriorityRank -Priority ([string]$_.priority) } }, `
                @{ Expression = { try { [datetimeoffset][string]$_.updatedAt } catch { [datetimeoffset]::MinValue } }; Descending = $true }, `
                @{ Expression = { [int]$_.number } }
    )

    $snapshot = @{
        repository = $Repository
        updatedAt = Get-VorceStudiosTimestamp
        items = $sorted
    }
    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPlanningSnapshotPath) -Value $snapshot

    return $sorted
}

function Sync-VorceStudiosGitHubIssuesToPaperclip {
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [ValidateSet('open', 'closed', 'all')][string]$State = 'all',
        [int]$Limit = 200
    )

    $goals = if ($Context.ContainsKey('Goals')) { $Context.Goals } else { @{} }
    $existingByGitHubNumber = @{}
    foreach ($paperclipIssue in @(Get-VorceStudiosIssues -CompanyId ([string]$Context.Company.id))) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$paperclipIssue.description)
        if ($metadata.ContainsKey('gh_issue')) {
            $existingByGitHubNumber[[string]$metadata['gh_issue']] = $paperclipIssue
        }
    }

    $created = New-Object System.Collections.Generic.List[string]
    $updated = New-Object System.Collections.Generic.List[string]
    $skipped = New-Object System.Collections.Generic.List[string]
    $items = @(Get-VorceStudiosGitHubIssues -Repository ([string]$Context.Repository) -State $State -Limit $Limit)

    foreach ($issue in $items) {
        $goalKey = Resolve-VorceStudiosGitHubIssueGoalKey -Issue $issue
        $sequenceId = Resolve-VorceStudiosGitHubIssueSequence -GoalKey $goalKey
        $priority = Resolve-VorceStudiosGitHubIssuePriority -Issue $issue -GoalKey $goalKey
        $goalId = if ($goals.ContainsKey($goalKey)) { [string]$goals[$goalKey].id } else { $null }
        $title = ('[GH#{0}] {1}' -f [int]$issue.number, [string]$issue.title)
        $description = ConvertTo-VorceStudiosGitHubIssueDescription -Repository ([string]$Context.Repository) -Issue $issue -GoalKey $goalKey -SequenceId $sequenceId
        $existing = if ($existingByGitHubNumber.ContainsKey([string]$issue.number)) { $existingByGitHubNumber[[string]$issue.number] } else { $null }
        $desiredStatus = if ([string]$issue.state -eq 'closed') {
            'done'
        } elseif ($null -eq $existing) {
            'backlog'
        } else {
            $currentStatus = [string]$existing.status
            if ($currentStatus -in @('in_progress', 'in_review', 'blocked', 'todo')) {
                $currentStatus
            } elseif ($currentStatus -in @('done', 'cancelled')) {
                'backlog'
            } else {
                'backlog'
            }
        }

        if ($null -eq $existing) {
            $payload = @{
                title = $title
                description = $description
                priority = $priority
                status = $desiredStatus
                projectId = [string]$Context.Project.id
            }
            if (-not [string]::IsNullOrWhiteSpace($goalId)) {
                $payload['goalId'] = $goalId
            }

            $createdIssue = New-VorceStudiosIssue -CompanyId ([string]$Context.Company.id) -Payload $payload
            $existingByGitHubNumber[[string]$issue.number] = $createdIssue
            $created.Add([string]$createdIssue.identifier) | Out-Null
            continue
        }

        $patch = @{}
        if ([string]$existing.title -ne $title) {
            $patch['title'] = $title
        }
        if ([string]$existing.description -ne $description) {
            $patch['description'] = $description
        }
        if ([string]$existing.priority -ne $priority) {
            $patch['priority'] = $priority
        }
        if ([string]$existing.status -ne $desiredStatus) {
            $patch['status'] = $desiredStatus
        }
        if ([string]$existing.projectId -ne [string]$Context.Project.id) {
            $patch['projectId'] = [string]$Context.Project.id
        }
        if (-not [string]::IsNullOrWhiteSpace($goalId) -and [string]$existing.goalId -ne $goalId) {
            $patch['goalId'] = $goalId
        }

        if ($patch.Count -eq 0) {
            $skipped.Add([string]$existing.identifier) | Out-Null
            continue
        }

        $updatedIssue = Update-VorceStudiosIssue -IssueId ([string]$existing.id) -Payload $patch
        $existingByGitHubNumber[[string]$issue.number] = $updatedIssue
        $updated.Add([string]$updatedIssue.identifier) | Out-Null
    }

    return @{
        repository = [string]$Context.Repository
        created = $created.ToArray()
        updated = $updated.ToArray()
        skipped = $skipped.ToArray()
        totalSeen = $items.Count
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

    return [pscustomobject]@{
        OrchestrationStatus = [string]$Issue.status
        PullRequestUrl = if ($metadata.ContainsKey('pr_url')) { [string]$metadata['pr_url'] } else { '' }
    }
}
