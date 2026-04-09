Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')

function Get-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    # Mock or wrap gh label list
    return @()
}

function Ensure-VorceStudiosGitHubLabels {
    param(
        [Parameter(Mandatory)][string]$Repository
    )

    # Simplified: could call gh label create ...
    return $true
}

function Ensure-VorceStudiosProjectFields {
    # Stub for field sync
    return $true
}

function Ensure-VorceStudiosGoalsFromPolicy {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $policy = Get-VorceStudiosPolicy -Name 'goals'
    $existingGoals = @(Get-VorceStudiosGoals -CompanyId $CompanyId)
    $existingById = @{}
    $existingByTitle = @{}
    foreach ($goal in $existingGoals) {
        $id = [string](Get-VorceStudiosObjectPropertyValue -Object $goal -PropertyName 'id')
        $title = [string](Get-VorceStudiosObjectPropertyValue -Object $goal -PropertyName 'title')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $existingById[$id] = $goal
        }
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            $existingByTitle[$title] = $goal
        }
    }

    $created = New-Object System.Collections.Generic.List[string]
    foreach ($goal in @($policy.Goals)) {
        $id = [string]$goal.Id
        $title = [string]$goal.Title
        if ($existingById.ContainsKey($id) -or $existingByTitle.ContainsKey($title)) {
            continue
        }

        try {
            Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/goals" -f $CompanyId) -Body @{
                id = $id
                title = $title
                description = [string]$goal.Description
                priority = [string]$goal.Priority
                labels = @($goal.Labels)
            } | Out-Null
            $created.Add($id)
        } catch {
        }
    }

    return @{
        createdCount = $created.Count
        createdGoalIds = $created.ToArray()
        totalGoals = @($policy.Goals).Count
    }
}

function Get-VorceStudiosGitHubOpenIssues {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [int]$Limit = 200
    )

    $output = (& gh issue list --repo $Repository --state open --limit $Limit --json number,title,body,url,labels,state,updatedAt 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw ("GitHub issue sync failed for {0}: {1}" -f $Repository, $output.Trim())
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return @()
    }

    return @($output | ConvertFrom-Json)
}

function Get-VorceStudiosGitHubIssueLabelNames {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    return @(
        @(Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'labels') |
            ForEach-Object { [string](Get-VorceStudiosObjectPropertyValue -Object $_ -PropertyName 'name') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-VorceStudiosGitHubIssuePaperclipTitle {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    return ('[GH#{0}] {1}' -f [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'number'), [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'title'))
}

function Get-VorceStudiosGoalIdMapByPolicyId {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $policy = Get-VorceStudiosPolicy -Name 'goals'
    $goalsByTitle = @{}
    foreach ($goal in @(Get-VorceStudiosGoals -CompanyId $CompanyId)) {
        $title = [string](Get-VorceStudiosObjectPropertyValue -Object $goal -PropertyName 'title')
        if (-not [string]::IsNullOrWhiteSpace($title)) {
            $goalsByTitle[$title] = [string](Get-VorceStudiosObjectPropertyValue -Object $goal -PropertyName 'id')
        }
    }

    $result = @{}
    foreach ($goal in @($policy.Goals)) {
        $title = [string]$goal.Title
        if ($goalsByTitle.ContainsKey($title)) {
            $result[[string]$goal.Id] = [string]$goalsByTitle[$title]
        }
    }

    return $result
}

function Resolve-VorceStudiosGitHubIssuePriority {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    if ($labels -contains 'priority: critical') { return 'critical' }
    if ($labels -contains 'priority: high') { return 'high' }
    if ($labels -contains 'priority: low') { return 'low' }
    return 'medium'
}

function Resolve-VorceStudiosGitHubIssueStatus {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    if ($labels -contains 'status: blocked') { return 'blocked' }
    if ($labels -contains 'status: needs-review') { return 'in_review' }
    return 'todo'
}

function Resolve-VorceStudiosGitHubIssueGoalId {
    param(
        [Parameter(Mandatory)][object]$Issue,
        [Parameter(Mandatory)][hashtable]$GoalIdByPolicyId
    )

    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue | ForEach-Object { $_.ToLowerInvariant() })
    $text = ('{0} {1}' -f [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'title'), [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'body')).ToLowerInvariant()

    if ($GoalIdByPolicyId.ContainsKey('G1') -and (($labels -contains 'bug') -or ($labels -contains 'security') -or ($labels -contains 'testing') -or ($text -match 'ffmpeg|does not start|startup|crash|regression|tls|dtls|validation'))) {
        return [string]$GoalIdByPolicyId['G1']
    }

    if ($GoalIdByPolicyId.ContainsKey('G3') -and (($labels -contains 'documentation') -or ($labels -contains 'dependencies') -or ($labels -contains 'refactoring') -or ($labels -contains 'sync: paperclip') -or ($text -match 'paperclip|telegram|adapter|github|agent|autonom|orchestrat|workflow|skill|goal|qwen_local'))) {
        return [string]$GoalIdByPolicyId['G3']
    }

    if ($GoalIdByPolicyId.ContainsKey('G4') -and (($labels -contains 'release') -or ($labels -contains 'community') -or ($text -match 'release|community|professional video io|video i/o'))) {
        return [string]$GoalIdByPolicyId['G4']
    }

    if ($GoalIdByPolicyId.ContainsKey('G2')) {
        return [string]$GoalIdByPolicyId['G2']
    }

    return @($GoalIdByPolicyId.Values | Select-Object -First 1)[0]
}

function New-VorceStudiosGitHubIssueDescription {
    param(
        [Parameter(Mandatory)][object]$Issue
    )

    $labels = @(Get-VorceStudiosGitHubIssueLabelNames -Issue $Issue)
    $labelSummary = if ($labels.Count -gt 0) { $labels -join ', ' } else { 'none' }
    $body = [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'body')
    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = '_No GitHub description provided._'
    }
    if ($body.Length -gt 12000) {
        $body = $body.Substring(0, 12000).TrimEnd() + "`n`n[truncated during import]"
    }

    return @(
        ('Imported from GitHub issue [#{0}]({1}).' -f [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'number'), [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'url'))
        ''
        ('GitHub labels: {0}' -f $labelSummary)
        ('GitHub updatedAt: {0}' -f [string](Get-VorceStudiosObjectPropertyValue -Object $Issue -PropertyName 'updatedAt'))
        ''
        '## GitHub Description'
        $body.Trim()
        ''
        '## Sync Contract'
        '- This Paperclip issue is linked through `paperclip-plugin-github-issues`.'
        '- Open/closed state should stay in sync with the linked GitHub issue.'
    ) -join "`n"
}

function Find-VorceStudiosPaperclipIssueForGitHubIssue {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PaperclipIssues,
        [Parameter(Mandatory)][object]$GitHubIssue
    )

    $expectedTitle = Get-VorceStudiosGitHubIssuePaperclipTitle -Issue $GitHubIssue
    $url = [string](Get-VorceStudiosObjectPropertyValue -Object $GitHubIssue -PropertyName 'url')

    $byTitle = @(
        $PaperclipIssues |
            Where-Object { [string](Get-VorceStudiosObjectPropertyValue -Object $_ -PropertyName 'title') -eq $expectedTitle } |
            Select-Object -First 1
    )
    if ($byTitle.Count -gt 0) {
        return $byTitle[0]
    }

    $byUrl = @(
        $PaperclipIssues |
            Where-Object { [string](Get-VorceStudiosObjectPropertyValue -Object $_ -PropertyName 'description') -like ('*{0}*' -f $url) } |
            Select-Object -First 1
    )
    if ($byUrl.Count -gt 0) {
        return $byUrl[0]
    }

    return $null
}

function Sync-VorceStudiosGitHubIssuesToPaperclip {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $syncPolicy = Get-VorceStudiosPolicy -Name 'sync'
    $repository = [string]$syncPolicy.GitHub.Repository
    $linkTool = Resolve-VorceStudiosGitHubLinkToolName
    $goalIdByPolicyId = Get-VorceStudiosGoalIdMapByPolicyId -CompanyId $CompanyId

    $projectState = Ensure-VorceStudiosPrimaryProject -CompanyId $CompanyId
    $projectId = [string](Get-VorceStudiosObjectPropertyValue -Object $projectState.Project -PropertyName 'id')
    $paperclipIssues = @(Get-VorceStudiosIssues -CompanyId $CompanyId)
    $githubIssues = @(Get-VorceStudiosGitHubOpenIssues -Repository $repository)
    $created = New-Object System.Collections.Generic.List[string]
    $updated = New-Object System.Collections.Generic.List[string]
    $linked = New-Object System.Collections.Generic.List[string]
    $linkErrors = New-Object System.Collections.Generic.List[string]

    foreach ($githubIssue in $githubIssues) {
        $title = Get-VorceStudiosGitHubIssuePaperclipTitle -Issue $githubIssue
        $description = New-VorceStudiosGitHubIssueDescription -Issue $githubIssue
        $priority = Resolve-VorceStudiosGitHubIssuePriority -Issue $githubIssue
        $status = Resolve-VorceStudiosGitHubIssueStatus -Issue $githubIssue
        $goalId = Resolve-VorceStudiosGitHubIssueGoalId -Issue $githubIssue -GoalIdByPolicyId $goalIdByPolicyId
        $paperclipIssue = Find-VorceStudiosPaperclipIssueForGitHubIssue -PaperclipIssues $paperclipIssues -GitHubIssue $githubIssue

        $payload = @{
            title = $title
            description = $description
            priority = $priority
            status = $status
        }
        if (-not [string]::IsNullOrWhiteSpace($projectId)) {
            $payload.projectId = $projectId
        }
        if (-not [string]::IsNullOrWhiteSpace($goalId)) {
            $payload.goalId = $goalId
        }

        if ($null -eq $paperclipIssue) {
            $paperclipIssue = New-VorceStudiosIssue -CompanyId $CompanyId -Payload $payload
            $paperclipIssues += $paperclipIssue
            $created.Add($title)
        } else {
            $updatePayload = @{}
            foreach ($field in @('title', 'description', 'priority', 'status', 'projectId', 'goalId')) {
                $currentValue = [string](Get-VorceStudiosObjectPropertyValue -Object $paperclipIssue -PropertyName $field)
                $desiredValue = [string](Get-VorceStudiosObjectPropertyValue -Object $payload -PropertyName $field)
                if ($currentValue -ne $desiredValue) {
                    $updatePayload[$field] = $payload[$field]
                }
            }

            if ($updatePayload.Count -gt 0) {
                $paperclipIssue = Update-VorceStudiosIssue -IssueId ([string]$paperclipIssue.id) -Payload $updatePayload
                $updated.Add($title)
            }
        }

        try {
            $linkResult = Invoke-VorceStudiosPluginTool -Tool $linkTool -RunContext @{ companyId = $CompanyId } -Parameters @{
                ghIssueUrl = [string](Get-VorceStudiosObjectPropertyValue -Object $githubIssue -PropertyName 'url')
                paperclipIssueId = [string](Get-VorceStudiosObjectPropertyValue -Object $paperclipIssue -PropertyName 'id')
            }
            $error = [string](Get-VorceStudiosObjectPropertyValue -Object $linkResult -PropertyName 'error')
            if ([string]::IsNullOrWhiteSpace($error) -or ($error -match 'already linked')) {
                $linked.Add($title)
            } else {
                $linkErrors.Add(('{0}: {1}' -f $title, $error))
            }
        } catch {
            $linkErrors.Add(('{0}: {1}' -f $title, $_.Exception.Message))
        }
    }

    Invoke-VorceStudiosGitHubPluginPeriodicSync -IgnoreFailure | Out-Null

    return @{
        repository = $repository
        totalGitHubIssues = $githubIssues.Count
        createdCount = $created.Count
        updatedCount = $updated.Count
        linkedCount = $linked.Count
        createdIssues = $created.ToArray()
        updatedIssues = $updated.ToArray()
        linkErrors = $linkErrors.ToArray()
    }
}
