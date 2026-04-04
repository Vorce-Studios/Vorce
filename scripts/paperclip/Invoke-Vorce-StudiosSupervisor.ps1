[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\CapacityLedger.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')

$system = Get-VorceStudiosSystemPolicy
$intervals = $system.Supervisor.AgentIntervals
$maintenanceIntervals = if ($system.Supervisor.ContainsKey('MaintenanceIntervals')) { $system.Supervisor.MaintenanceIntervals } else { @{} }

while ($true) {
    $state = Get-VorceStudiosRuntimeState
    if ([string]$state.mode -eq 'stopped') {
        break
    }

    Update-VorceStudiosCapacityLedgerFromProbe | Out-Null

    $roles = @(
        @{ Key = 'discovery'; Interval = [int]$intervals.DiscoveryScout },
        @{ Key = 'chief_of_staff'; Interval = [int]$intervals.ChiefOfStaff },
        @{ Key = 'jules'; Interval = [int]$intervals.JulesBuilder },
        @{ Key = 'gemini_review'; Interval = [int]$intervals.ReviewPool },
        @{ Key = 'qwen_review'; Interval = [int]$intervals.ReviewPool },
        @{ Key = 'codex_review'; Interval = [int]$intervals.ReviewPool },
        @{ Key = 'ops'; Interval = [int]$intervals.OpsSteward },
        @{ Key = 'ceo'; Interval = [int]$intervals.CEO }
    )

    foreach ($role in $roles) {
        if ([string]$state.mode -eq 'draining' -and $role.Key -eq 'discovery') {
            continue
        }

        $lastRunText = if ($state.lastRoleRuns.ContainsKey($role.Key)) { [string]$state.lastRoleRuns[$role.Key] } else { '' }
        $shouldRun = $true
        if (-not [string]::IsNullOrWhiteSpace($lastRunText)) {
            try {
                $lastRun = [datetimeoffset]$lastRunText
                $elapsedSeconds = (([datetimeoffset](Get-Date)) - $lastRun).TotalSeconds
                $shouldRun = ($elapsedSeconds -ge $role.Interval)
            } catch {
                $shouldRun = $true
            }
        }

        if (-not $shouldRun) {
            continue
        }

        try {
            & (Join-Path $ScriptDir 'Invoke-Vorce-StudiosAgent.ps1') -Role $role.Key | Out-Null
        } catch {
            Write-Warning ("Supervisor-Fehler fuer Rolle '{0}': {1}" -f $role.Key, $_.Exception.Message)
        }

        $state = Get-VorceStudiosRuntimeState
        $state.lastRoleRuns[$role.Key] = Get-VorceStudiosTimestamp
        Set-VorceStudiosRuntimeState -State $state
    }

    if ($maintenanceIntervals.ContainsKey('GitHubSync')) {
        $state = Get-VorceStudiosRuntimeState
        $lastRunText = if ($state.lastRoleRuns.ContainsKey('github_sync')) { [string]$state.lastRoleRuns['github_sync'] } else { '' }
        $shouldRunSync = $true
        if (-not [string]::IsNullOrWhiteSpace($lastRunText)) {
            try {
                $lastRun = [datetimeoffset]$lastRunText
                $elapsedSeconds = (([datetimeoffset](Get-Date)) - $lastRun).TotalSeconds
                $shouldRunSync = ($elapsedSeconds -ge [int]$maintenanceIntervals.GitHubSync)
            } catch {
                $shouldRunSync = $true
            }
        }

        if ($shouldRunSync) {
            try {
                & (Join-Path $ScriptDir 'Sync-Vorce-StudiosGitHubState.ps1') | Out-Null
            } catch {
                Write-Warning ("Supervisor-GitHub-Sync fehlgeschlagen: {0}" -f $_.Exception.Message)
            }

            $state = Get-VorceStudiosRuntimeState
            $state.lastRoleRuns['github_sync'] = Get-VorceStudiosTimestamp
            Set-VorceStudiosRuntimeState -State $state
        }
    }

    $companyState = Get-VorceStudiosCompanyState
    if ($null -ne $companyState.company -and -not [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
        try {
            Send-VorceStudiosAfkHeartbeat -Context @{ Company = $companyState.company } | Out-Null
        } catch {
            Write-Warning ("AFK-Heartbeat fehlgeschlagen: {0}" -f $_.Exception.Message)
        }
    }

    Start-Sleep -Seconds ([int]$system.Supervisor.TickSeconds)
}
