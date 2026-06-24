# SUB-RUN-04_ReviewDispatch.ps1 (Vorce 3.0)
# Finds reviewable pull requests and records review dispatch requests.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [hashtable]$ConfigBag,

    [Parameter(Mandatory)]
    [object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'state/StateManager.ps1')
. (Join-Path $global:LibDir 'engines/QuotaManager.ps1')
. (Join-Path $global:LibDir 'integrations/GitHubClient.ps1')

Write-VorceStep -Message 'Starte ReviewDispatch...' -Status 'RUN'

$repo = [string]$ConfigBag.Config.repository
$reviewDir = Join-Path $global:VarDir 'db/reviews'
if (-not (Test-Path -LiteralPath $reviewDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $reviewDir -Force
}

if ($ConfigBag.DryRun) {
    Write-VorceStep -Message 'DryRun: GitHub-Abfrage und Review-Dispatch werden nicht ausgefuehrt.' -Status 'INFO'
    return @{ status = 'dry_run'; prs_found = 0; reviews_dispatched = 0; timestamp = (Get-Date).ToString('o') }
}

try {
    $commandResult = Invoke-VorceGitHubCommand -Arguments @(
        'pr', 'list',
        '--repo', $repo,
        '--state', 'open',
        '--limit', '100',
        '--json', 'number,title,url,isDraft,labels,reviewRequests,commits,createdAt,headRefName,baseRefName,changedFiles,additions,deletions'
    )
    $pullRequests = @(ConvertFrom-VorceGitHubJson -CommandResult $commandResult)
    $prData = @($pullRequests | Where-Object {
        $labelNames = @($_.labels | ForEach-Object { [string]$_.name })
        $reviewerNames = @($_.reviewRequests | ForEach-Object { [string]$_.login })
        $commitCount = @($_.commits).Count
        $_.isDraft -ne $true -and
        $labelNames -notcontains 'no-review' -and
        ($reviewerNames -contains 'claude' -or $reviewerNames -contains 'gemini') -and
        $commitCount -lt 20
    })

    if ($prData.Count -eq 0) {
        Write-VorceStep -Message 'Keine PRs im Review-Status gefunden.' -Status 'INFO'
        return @{ status = 'no_prs_for_review'; prs_found = 0; reviews_dispatched = 0; timestamp = (Get-Date).ToString('o') }
    }

    Write-VorceStep -Message "Gefunden $($prData.Count) PRs fuer Review" -Status 'INFO'
} catch {
    Write-VorceStep -Message "Fehler beim Abrufen von PRs: $($_.Exception.Message)" -Status 'ERROR'
    return @{
        status = 'error'
        error = $_.Exception.Message
        error_class = if ($commandResult) { $commandResult.ErrorClass } else { 'github_query_failed' }
        prs_found = 0
        reviews_dispatched = 0
        timestamp = (Get-Date).ToString('o')
    }
}

$reviewsDispatched = 0
foreach ($pullRequest in $prData) {
    Write-VorceStep -Message "Dispatche Review fuer PR #$($pullRequest.number): $($pullRequest.title)" -Status 'RUN'

    try {
        $labelNames = @($pullRequest.labels | ForEach-Object { [string]$_.name })
        $agentName = if ($labelNames -contains 'ai-review-gemini') { 'gemini_cli' } else { 'claude_code' }
        if (-not (Test-VorceQuota -AgentName $agentName)) {
            Write-VorceStep -Message "Quota fuer $agentName erschoepft, ueberspringe PR" -Status 'WARN'
            continue
        }

        $reviewFile = Join-Path $reviewDir (
            'review_{0}_{1}.json' -f $pullRequest.number, (Get-Date).ToString('yyyyMMdd_HHmmss')
        )
        $reviewRequest = [ordered]@{
            pr_number = $pullRequest.number
            pr_title = $pullRequest.title
            pr_url = $pullRequest.url
            requested_agent = $agentName
            created_at = $pullRequest.createdAt
            head_branch = $pullRequest.headRefName
            base_branch = $pullRequest.baseRefName
            files_changed = $pullRequest.changedFiles
            additions = $pullRequest.additions
            deletions = $pullRequest.deletions
            commit_count = @($pullRequest.commits).Count
        }

        $reviewRequest | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $reviewFile -Encoding UTF8

        if (-not $ParentState.reviews) {
            $ParentState | Add-Member -MemberType NoteProperty -Name 'reviews' -Value @() -Force
        }
        $ParentState.reviews += [pscustomobject]$reviewRequest
        $reviewsDispatched++

        Write-VorceStep -Message "Review fuer PR #$($pullRequest.number) an $agentName dispatched" -Status 'OK'
    } catch {
        Write-VorceStep `
            -Message "Fehler bei Review Dispatch fuer #$($pullRequest.number): $($_.Exception.Message)" `
            -Status 'ERROR'
    }
}

$reviewDispatchResult = @{
    status = 'completed'
    prs_found = $prData.Count
    reviews_dispatched = $reviewsDispatched
    quota_available_for_claude = (Test-VorceQuota -AgentName 'claude_code')
    quota_available_for_gemini = (Test-VorceQuota -AgentName 'gemini_cli')
    timestamp = (Get-Date).ToString('o')
}

Write-VorceStep `
    -Message "ReviewDispatch abgeschlossen: $reviewsDispatched von $($prData.Count) Reviews dispatched." `
    -Status 'OK'
return $reviewDispatchResult
