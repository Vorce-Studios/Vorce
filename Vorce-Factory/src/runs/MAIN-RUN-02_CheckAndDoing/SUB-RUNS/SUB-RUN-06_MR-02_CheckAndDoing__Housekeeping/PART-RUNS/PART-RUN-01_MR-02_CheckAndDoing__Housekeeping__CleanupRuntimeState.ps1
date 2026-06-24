# CleanupRuntimeState.ps1 (Vorce 3.0)
# Updates housekeeping state and delegates all filesystem retention centrally.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'state/StateManager.ps1')
. (Join-Path $global:LibDir 'maintenance/RetentionManager.ps1')

function Get-HousekeepingStat {
    param([Parameter(Mandatory)][string]$Name)

    if ($ConfigBag.GlobalState.stats -is [System.Collections.IDictionary]) {
        if ($ConfigBag.GlobalState.stats.Contains($Name)) {
            return $ConfigBag.GlobalState.stats[$Name]
        }
        return $null
    }
    $property = $ConfigBag.GlobalState.stats.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Set-HousekeepingStat {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if ($ConfigBag.GlobalState.stats -is [System.Collections.IDictionary]) {
        $ConfigBag.GlobalState.stats[$Name] = $Value
    } else {
        $ConfigBag.GlobalState.stats |
            Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

Write-VorceStep -Message 'Starte Housekeeping...' -Status 'RUN'

$completedDelegations = @()
$remainingDelegations = @()
if ($ConfigBag.GlobalState.PSObject.Properties.Name -contains 'active_delegations') {
    $completedDelegations = @($ConfigBag.GlobalState.active_delegations | Where-Object {
        $_.status -in @('completed', 'merged', 'closed')
    })
    $remainingDelegations = @($ConfigBag.GlobalState.active_delegations | Where-Object {
        $_.status -notin @('completed', 'merged', 'closed')
    })

    if ($completedDelegations.Count -gt 0 -and -not [bool]$ConfigBag.DryRun) {
        $cleanupReport = @{
            timestamp = (Get-Date).ToString('o')
            removed_delegations = @($completedDelegations | ForEach-Object {
                @{
                    issueNumber = $_.issueNumber
                    title = $_.title
                    status = $_.status
                    completedAt = $_.completedAt
                }
            })
        }
        $cleanupDir = Join-Path $global:VarDir 'db/completed_delegations'
        $null = New-Item -ItemType Directory -Path $cleanupDir -Force
        $cleanupReportFile = Join-Path $cleanupDir "cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $cleanupReport | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $cleanupReportFile -Encoding UTF8
        $ConfigBag.GlobalState.active_delegations = $remainingDelegations
    }
}

$policyPath = Join-Path $global:VarDir 'config/retention-policy.json'
$retentionReport = Invoke-VorceRetention `
    -VarRoot $global:VarDir `
    -PolicyPath $policyPath `
    -DryRun ([bool]$ConfigBag.DryRun) `
    -Confirm:$false

if ($retentionReport.status -in @('safety_blocked', 'completed_with_warnings')) {
    Write-VorceStep -Message "Retention beendet mit Status '$($retentionReport.status)'." -Status 'WARN'
} else {
    Write-VorceStep -Message (
        'Retention: {0} geloescht, {1} komprimiert, {2} rotiert, {3} geschuetzt.' -f
        $retentionReport.totals.deleted,
        $retentionReport.totals.compressed,
        $retentionReport.totals.rotated,
        $retentionReport.totals.protected
    ) -Status 'OK'
}

if ($ConfigBag.GlobalState.PSObject.Properties.Name -notcontains 'stats') {
    $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name 'stats' -Value @{
        total_runs = 0
        successful_runs = 0
        failed_runs = 0
        total_issues_processed = 0
        total_delegations_created = 0
        last_housekeeping = (Get-Date).ToString('o')
    }
}

Set-HousekeepingStat -Name 'last_housekeeping' -Value (Get-Date).ToString('o')
Set-HousekeepingStat -Name 'total_runs' -Value ([int](Get-HousekeepingStat -Name 'total_runs') + 1)
if ($ParentState.reviews) {
    $currentReviews = [int](Get-HousekeepingStat -Name 'total_reviews_dispatched')
    Set-HousekeepingStat -Name 'total_reviews_dispatched' `
        -Value ($currentReviews + @($ParentState.reviews).Count)
}
if ($ParentState.agents) {
    $unhealthyAgents = @($ParentState.agents.Values | Where-Object { $_.status -ne 'running' })
    if ($unhealthyAgents.Count -gt 0) {
        $currentUnhealthy = [int](Get-HousekeepingStat -Name 'unhealthy_agent_sessions')
        Set-HousekeepingStat -Name 'unhealthy_agent_sessions' `
            -Value ($currentUnhealthy + $unhealthyAgents.Count)
    }
}

if (-not [bool]$ConfigBag.DryRun) {
    Save-VorceGlobalState -State $ConfigBag.GlobalState
}

$housekeepingResult = @{
    status = if ($retentionReport.status -eq 'safety_blocked') { 'completed_with_warnings' } else { 'completed' }
    cleaned_delegations = if ([bool]$ConfigBag.DryRun) { 0 } else { $completedDelegations.Count }
    retention = $retentionReport
    tmp_files_cleaned = $retentionReport.totals.deleted
    session_locks_cleaned = 0
    stats_updated = -not [bool]$ConfigBag.DryRun
    next_housekeeping = (Get-Date).AddHours(24).ToString('o')
    timestamp = (Get-Date).ToString('o')
}

Write-VorceStep -Message 'Housekeeping abgeschlossen.' -Status 'OK'
return $housekeepingResult
