[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\CapacityLedger.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')

$runtimeState = Get-VorceStudiosRuntimeState
$processState = Get-VorceStudiosProcessState
$companyState = Get-VorceStudiosCompanyState
$ledger = Update-VorceStudiosCapacityLedgerFromProbe

$dashboard = $null
$companyId = $null
if ($null -eq $companyState.atlas) {
    $companyState['atlas'] = Get-VorceStudiosAtlasState
}
if ($null -ne $companyState.company -and $companyState.company.ContainsKey('id')) {
    $companyId = [string]$companyState.company['id']
}

$afkState = Get-VorceStudiosAfkModeState
$afkState['effectiveApprovalChannel'] = Get-VorceStudiosPreferredApprovalChannel

$plugins = if (Test-VorceStudiosPaperclipReady) { @(Get-VorceStudiosPlugins) } else { @() }
$githubPluginMatches = @($plugins | Where-Object { [string]$_.pluginKey -eq 'paperclip-plugin-github-issues' } | Select-Object -First 1)
$telegramPluginMatches = @($plugins | Where-Object { [string]$_.pluginKey -eq 'paperclip-plugin-telegram' } | Select-Object -First 1)
$githubPlugin = if ($githubPluginMatches.Count -gt 0) { $githubPluginMatches[0] } else { $null }
$telegramPlugin = if ($telegramPluginMatches.Count -gt 0) { $telegramPluginMatches[0] } else { $null }
$planningSnapshot = Get-VorceStudiosPlanningSnapshot
$syncPolicy = Get-VorceStudiosPolicy -Name 'sync'

if ((Test-VorceStudiosPaperclipReady) -and (-not [string]::IsNullOrWhiteSpace($companyId))) {
    $dashboard = Get-VorceStudiosDashboard -CompanyId $companyId
}

[pscustomobject]@{
    timestamp = Get-VorceStudiosTimestamp
    apiBase = Get-VorceStudiosApiBase
    paperclipReady = Test-VorceStudiosPaperclipReady
    serverProcess = Get-VorceStudiosServerProcessInfo
    runtimeMode = $runtimeState.mode
    company = $companyState.company
    project = $companyState.project
    atlas = $companyState.atlas
    processes = $processState
    afkMode = $afkState
    sync = @{
        sourceOfTruth = [string]$syncPolicy.GitHub.SourceOfTruth
        repository = [string]$syncPolicy.GitHub.Repository
        projectOwner = [string]$syncPolicy.GitHub.ProjectOwner
        projectNumber = [int]$syncPolicy.GitHub.ProjectNumber
        githubPlugin = if ($null -eq $githubPlugin) { $null } else { @{
            status = [string]$githubPlugin.status
            updatedAt = [string]$githubPlugin.updatedAt
            lastError = if ($null -eq $githubPlugin.lastError) { $null } else { [string]$githubPlugin.lastError }
        } }
        telegramPlugin = if ($null -eq $telegramPlugin) { $null } else { @{
            status = [string]$telegramPlugin.status
            updatedAt = [string]$telegramPlugin.updatedAt
            lastError = if ($null -eq $telegramPlugin.lastError) { $null } else { [string]$telegramPlugin.lastError }
        } }
        planningSnapshot = @{
            updatedAt = [string]$planningSnapshot.updatedAt
            top = @(
                @($planningSnapshot.records | Select-Object -First 5) |
                    ForEach-Object {
                        @{
                            issueNumber = [int]$_.issueNumber
                            bucket = [string]$_.bucket
                            score = [int]$_.score
                            readiness = [string]$_.readiness
                            title = [string]$_.title
                        }
                    }
            )
        }
    }
    capacity = $ledger.tools
    plugins = $plugins
    dashboard = $dashboard
}
