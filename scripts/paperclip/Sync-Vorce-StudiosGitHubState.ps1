[CmdletBinding()]
param(
    [switch]$RunPlanningSweep,
    [ValidateSet('active', 'all')][string]$Scope = 'active',
    [switch]$EnsureRuntime
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

if (-not (Test-VorceStudiosPaperclipReady)) {
    throw 'Paperclip ist nicht bereit. Bitte zuerst Start-Vorce-Studios.ps1 ausfuehren.'
}

$companyState = Get-VorceStudiosCompanyState
if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    throw 'Vorce-Studios ist noch nicht initialisiert.'
}

$context = @{
    Company = $companyState.company
    Agents = $companyState.agents
    Project = $companyState.project
    Repository = Get-VorceStudiosRepositorySlug
}

$projectState = Ensure-VorceStudiosPrimaryProject -CompanyId ([string]$context.Company.id) -NormalizeIssues
if ($null -ne $projectState.Project) {
    $context['Project'] = @{
        id = [string]$projectState.Project.id
        name = [string]$projectState.Project.name
    }
    $companyState['project'] = $context.Project
    Set-VorceStudiosCompanyState -State $companyState
}

if ($EnsureRuntime.IsPresent -or $Scope -eq 'all' -or $RunPlanningSweep.IsPresent) {
    Ensure-VorceStudiosProjectFields
    Ensure-VorceStudiosPlugins -Context $context | Out-Null
    Ensure-VorceStudiosGitHubLabels -Repository $context.Repository
}

if ($RunPlanningSweep.IsPresent) {
    Invoke-VorceStudiosPlanningSweep -Repository $context.Repository | Out-Null
}

if ($EnsureRuntime.IsPresent -or $Scope -eq 'all') {
    Invoke-VorceStudiosGitHubPluginPeriodicSync -IgnoreFailure | Out-Null
}

$synced = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]
foreach ($issue in @(Get-VorceStudiosIssues -CompanyId $context.Company.id)) {
    $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$issue.description)
    if (-not $metadata.ContainsKey('gh_issue')) {
        continue
    }

    if ($Scope -eq 'active') {
        $recentlyTouched = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$issue.updatedAt)) {
            try {
                $recentlyTouched = ((([datetimeoffset](Get-Date)) - [datetimeoffset][string]$issue.updatedAt).TotalHours -le 72)
            } catch {
                $recentlyTouched = $false
            }
        }

        $hasLiveBlockedState = (
            ([string]$issue.status -eq 'blocked') -and (
                (-not [string]::IsNullOrWhiteSpace([string]$metadata['session_name'])) -or
                (-not [string]::IsNullOrWhiteSpace([string]$metadata['approval_id'])) -or
                ([string]$metadata['review_status'] -in @('pending', 'changes_requested', 'manual_ui_required')) -or
                $recentlyTouched
            )
        )
        $hasLiveState = (
            [string]$issue.status -in @('todo', 'in_progress', 'in_review') -or
            $hasLiveBlockedState -or
            (-not [string]::IsNullOrWhiteSpace([string]$metadata['session_name'])) -or
            (-not [string]::IsNullOrWhiteSpace([string]$metadata['approval_id'])) -or
            ([string]$metadata['review_status'] -in @('pending', 'changes_requested', 'manual_ui_required'))
        )
        if (-not $hasLiveState) {
            continue
        }
    }

    try {
        $result = Sync-VorceStudiosIssueToGitHub -Context $context -Issue $issue
        if ($null -ne $result) {
            $synced.Add([pscustomobject]@{
                paperclipIssue = [string]$issue.identifier
                githubIssue = [int]$metadata['gh_issue']
                orchestrationStatus = [string]$result.OrchestrationStatus
                pullRequestUrl = [string]$result.PullRequestUrl
            })
        }
    } catch {
        $message = $_.Exception.Message
        Write-Warning ("GitHub-Sync fuer {0}/GH#{1} fehlgeschlagen: {2}" -f [string]$issue.identifier, [int]$metadata['gh_issue'], $message)
        $failures.Add([pscustomobject]@{
            paperclipIssue = [string]$issue.identifier
            githubIssue = [int]$metadata['gh_issue']
            error = $message
        })
    }
}

[pscustomobject]@{
    repository = $context.Repository
    scope = $Scope
    syncedCount = $synced.Count
    failedCount = $failures.Count
    items = $synced.ToArray()
    failures = $failures.ToArray()
}
