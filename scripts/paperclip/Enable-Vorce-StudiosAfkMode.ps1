[CmdletBinding()]
param(
    [int]$HeartbeatMinutes = 0,
    [int]$QuietHoursMinutes = 0,
    [string]$DefaultChatId,
    [string]$ApprovalsChatId,
    [string]$UpdatedBy = 'manual'
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$state = Enable-VorceStudiosAfkModeState -UpdatedBy $UpdatedBy
if ($HeartbeatMinutes -gt 0) {
    $state['heartbeatMinutes'] = $HeartbeatMinutes
}
if ($QuietHoursMinutes -gt 0) {
    $state['quietHoursMinutes'] = $QuietHoursMinutes
}
if (-not [string]::IsNullOrWhiteSpace($DefaultChatId)) {
    $state.transport.telegram.defaultChatId = $DefaultChatId
}
if (-not [string]::IsNullOrWhiteSpace($ApprovalsChatId)) {
    $state.transport.telegram.approvalsChatId = $ApprovalsChatId
}

$state.transport.telegram.configured = Test-VorceStudiosTelegramTransportReady
$state.transport.telegram.enabled = $state.transport.telegram.configured
Set-VorceStudiosAfkModeState -State $state

$companyState = Get-VorceStudiosCompanyState
if ((Test-VorceStudiosPaperclipReady) -and $companyState.company -and $companyState.company.id) {
    Ensure-VorceStudiosTelegramPlugin -Context @{
        Company = $companyState.company
        Agents = $companyState.agents
        Project = $companyState.project
        Repository = Get-VorceStudiosRepositorySlug
    } | Out-Null
}

[pscustomobject]@{
    enabled = $true
    preferredApprovalChannel = Get-VorceStudiosPreferredApprovalChannel
    telegramReady = Test-VorceStudiosTelegramTransportReady
    state = Get-VorceStudiosAfkModeState
}
