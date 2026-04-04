[CmdletBinding()]
param(
    [switch]$FinishCurrentWorkOnly,
    [int]$TimeoutMinutes = 20
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$companyState = Get-VorceStudiosCompanyState
$processState = Get-VorceStudiosProcessState

if ($FinishCurrentWorkOnly.IsPresent) {
    Set-VorceStudiosRuntimeMode -Mode 'draining' -Note 'Finish current work only requested.'

    if (Test-VorceStudiosPaperclipReady -and $companyState.company -and $companyState.company.id) {
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            $activeIssues = @(
                Get-VorceStudiosIssues -CompanyId $companyState.company.id |
                    Where-Object { @('in_progress', 'in_review') -contains [string]$_.status }
            )

            if ($activeIssues.Count -eq 0) {
                break
            }

            Start-Sleep -Seconds 10
        } while ((Get-Date) -lt $deadline)
    }
}

foreach ($entry in @('supervisor', 'paperclip')) {
    $processInfo = $processState[$entry]
    if ($processInfo -and $processInfo.pid) {
        $process = Get-Process -Id ([int]$processInfo.pid) -ErrorAction SilentlyContinue
        if ($null -ne $process) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

$serverProcess = Get-VorceStudiosServerProcessInfo
if ($serverProcess -and $serverProcess.pid) {
    Stop-Process -Id ([int]$serverProcess.pid) -Force -ErrorAction SilentlyContinue
}

$processState['supervisor'] = $null
$processState['paperclip'] = $null
Set-VorceStudiosProcessState -State $processState
Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Stopped via Stop-Vorce-Studios.ps1'

[pscustomobject]@{
    stoppedAt = Get-VorceStudiosTimestamp
    mode = 'stopped'
}
