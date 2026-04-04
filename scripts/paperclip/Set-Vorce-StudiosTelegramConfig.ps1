[CmdletBinding()]
param(
    [string]$BotToken,
    [string]$DefaultChatId,
    [string]$ApprovalsChatId,
    [string]$ErrorsChatId,
    [switch]$EnableAfkMode,
    [string]$UpdatedBy = 'manual'
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

function Set-VorceStudiosEnvFileValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $lines = if (Test-Path -LiteralPath $Path) { @(Get-Content -LiteralPath $Path) } else { @() }
    $escaped = ('{0}={1}' -f $Key, $Value)
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^{0}=' -f [regex]::Escape($Key))) {
            $lines[$i] = $escaped
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $lines += $escaped
    }

    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$paths = Get-VorceStudiosPaths
if (-not (Test-Path -LiteralPath $paths.PaperclipEnvPath)) {
    [System.IO.File]::WriteAllText($paths.PaperclipEnvPath, '', (New-Object System.Text.UTF8Encoding($false)))
}

if (-not [string]::IsNullOrWhiteSpace($BotToken)) {
    Set-VorceStudiosEnvFileValue -Path $paths.PaperclipEnvPath -Key 'VORCE_TELEGRAM_BOT_TOKEN' -Value $BotToken
    Set-Item -Path 'Env:VORCE_TELEGRAM_BOT_TOKEN' -Value $BotToken
}
if (-not [string]::IsNullOrWhiteSpace($DefaultChatId)) {
    Set-VorceStudiosEnvFileValue -Path $paths.PaperclipEnvPath -Key 'VORCE_TELEGRAM_DEFAULT_CHAT_ID' -Value $DefaultChatId
    Set-Item -Path 'Env:VORCE_TELEGRAM_DEFAULT_CHAT_ID' -Value $DefaultChatId
}
if (-not [string]::IsNullOrWhiteSpace($ApprovalsChatId)) {
    Set-VorceStudiosEnvFileValue -Path $paths.PaperclipEnvPath -Key 'VORCE_TELEGRAM_APPROVALS_CHAT_ID' -Value $ApprovalsChatId
    Set-Item -Path 'Env:VORCE_TELEGRAM_APPROVALS_CHAT_ID' -Value $ApprovalsChatId
}
if (-not [string]::IsNullOrWhiteSpace($ErrorsChatId)) {
    Set-VorceStudiosEnvFileValue -Path $paths.PaperclipEnvPath -Key 'VORCE_TELEGRAM_ERRORS_CHAT_ID' -Value $ErrorsChatId
    Set-Item -Path 'Env:VORCE_TELEGRAM_ERRORS_CHAT_ID' -Value $ErrorsChatId
}

Import-VorceStudiosPaperclipEnvironment

$companyState = Get-VorceStudiosCompanyState
$pluginState = $null
if ((Test-VorceStudiosPaperclipReady) -and $companyState.company -and $companyState.company.id) {
    $pluginState = Ensure-VorceStudiosTelegramPlugin -Context @{
        Company = $companyState.company
        Agents = $companyState.agents
        Project = $companyState.project
        Repository = Get-VorceStudiosRepositorySlug
    }
}

$afkState = if ($EnableAfkMode.IsPresent) {
    Enable-VorceStudiosAfkModeState -UpdatedBy $UpdatedBy
} else {
    Get-VorceStudiosAfkModeState
}

[pscustomobject]@{
    telegramReady = Test-VorceStudiosTelegramTransportReady
    plugin = $pluginState
    afkMode = $afkState
    envPath = $paths.PaperclipEnvPath
}
