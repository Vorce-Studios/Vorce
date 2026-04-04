Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')
. (Join-Path $PSScriptRoot 'IssueMetadata.ps1')

function Get-VorceStudiosAfkModeState {
    $paths = Get-VorceStudiosPaths
    $policy = Get-VorceStudiosPolicy -Name 'afk'

    return Read-VorceStudiosJsonFile -Path $paths.AfkModeStatePath -Default @{
        enabled = [bool]$policy.Mode.DefaultEnabled
        preferredApprovalChannel = [string]$policy.Mode.PreferredApprovalChannel
        heartbeatMinutes = [int]$policy.Mode.HeartbeatMinutes
        quietHoursMinutes = [int]$policy.Mode.QuietHoursMinutes
        lastHeartbeatAt = $null
        lastDigestHash = ''
        updatedAt = Get-VorceStudiosTimestamp
        updatedBy = 'system'
        transport = @{
            telegram = @{
                configured = $false
                enabled = $false
                defaultChatId = if (-not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID)) { [string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID } else { '' }
                approvalsChatId = if (-not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_APPROVALS_CHAT_ID)) { [string]$env:VORCE_TELEGRAM_APPROVALS_CHAT_ID } else { '' }
            }
        }
    }
}

function Set-VorceStudiosAfkModeState {
    param(
        [Parameter(Mandatory)][hashtable]$State
    )

    $State['updatedAt'] = Get-VorceStudiosTimestamp
    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).AfkModeStatePath -Value $State
}

function Enable-VorceStudiosAfkModeState {
    param(
        [string]$UpdatedBy = 'manual'
    )

    $state = Get-VorceStudiosAfkModeState
    $state['enabled'] = $true
    $state['updatedBy'] = $UpdatedBy
    if (-not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID)) {
        $state.transport.telegram.defaultChatId = [string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_APPROVALS_CHAT_ID)) {
        $state.transport.telegram.approvalsChatId = [string]$env:VORCE_TELEGRAM_APPROVALS_CHAT_ID
    }
    $state.transport.telegram.configured = Test-VorceStudiosTelegramTransportReady
    $state.transport.telegram.enabled = $state.transport.telegram.configured
    Set-VorceStudiosAfkModeState -State $state
    return $state
}

function Disable-VorceStudiosAfkModeState {
    param(
        [string]$UpdatedBy = 'manual'
    )

    $state = Get-VorceStudiosAfkModeState
    $state['enabled'] = $false
    $state['updatedBy'] = $UpdatedBy
    Set-VorceStudiosAfkModeState -State $state
    return $state
}

function Test-VorceStudiosTelegramTransportReady {
    return (
        -not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_BOT_TOKEN) -and
        -not [string]::IsNullOrWhiteSpace([string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID)
    )
}

function Get-VorceStudiosPreferredApprovalChannel {
    $state = Get-VorceStudiosAfkModeState
    if ($state.enabled -and $state.transport.telegram.enabled) {
        return 'telegram'
    }

    return 'paperclip'
}

function Send-VorceStudiosTelegramMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$ChatId
    )

    if (-not (Test-VorceStudiosTelegramTransportReady)) {
        return $false
    }

    $targetChat = if (-not [string]::IsNullOrWhiteSpace($ChatId)) { $ChatId } else { [string]$env:VORCE_TELEGRAM_DEFAULT_CHAT_ID }
    if ([string]::IsNullOrWhiteSpace($targetChat)) {
        return $false
    }

    $uri = 'https://api.telegram.org/bot{0}/sendMessage' -f [string]$env:VORCE_TELEGRAM_BOT_TOKEN
    try {
        Invoke-RestMethod -Method POST -Uri $uri -ContentType 'application/json' -Body (@{
            chat_id = $targetChat
            text = $Message
            disable_web_page_preview = $true
        } | ConvertTo-Json -Depth 5) -TimeoutSec 12 | Out-Null
        return $true
    } catch {
        Write-Warning ("Telegram-Nachricht konnte nicht gesendet werden: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Send-VorceStudiosAfkHeartbeat {
    param(
        [Parameter(Mandatory)][hashtable]$Context
    )

    $state = Get-VorceStudiosAfkModeState
    if (-not [bool]$state.enabled) {
        return $null
    }

    if (-not (Test-VorceStudiosTelegramTransportReady)) {
        return $null
    }

    $issues = @(Get-VorceStudiosIssues -CompanyId $Context.Company.id)
    $activeCount = @($issues | Where-Object { [string]$_.status -in @('in_progress', 'in_review') }).Count
    $blockedCount = @($issues | Where-Object { [string]$_.status -eq 'blocked' }).Count
    $todoCount = @($issues | Where-Object { [string]$_.status -in @('todo', 'backlog') }).Count

    $focusIssue = @(
        $issues |
            Where-Object { [string]$_.status -in @('in_progress', 'in_review', 'todo', 'blocked', 'backlog') } |
            Sort-Object `
                @{ Expression = { switch ([string]$_.status) { 'in_progress' { 0 } 'in_review' { 1 } 'todo' { 2 } 'blocked' { 3 } default { 4 } } } }, `
                @{ Expression = 'updatedAt'; Descending = $true } |
            Select-Object -First 1
    )[0]

    $focusText = 'idle'
    if ($null -ne $focusIssue) {
        $metadata = Get-VorceStudiosIssueMetadata -Text ([string]$focusIssue.description)
        $ghRef = if ($metadata.ContainsKey('gh_issue')) { ('GH#{0}' -f [string]$metadata['gh_issue']) } else { [string]$focusIssue.identifier }
        $focusText = switch ([string]$focusIssue.status) {
            'in_progress' { 'run {0}/{1}' -f [string]$focusIssue.identifier, $ghRef }
            'in_review' { 'review {0}/{1}' -f [string]$focusIssue.identifier, $ghRef }
            'todo' { 'todo {0}/{1}' -f [string]$focusIssue.identifier, $ghRef }
            'blocked' { 'blocked {0}/{1}' -f [string]$focusIssue.identifier, $ghRef }
            default { 'backlog {0}/{1}' -f [string]$focusIssue.identifier, $ghRef }
        }
    }

    $digest = '[Vorce-Studios] {0} | blk {1} | todo {2}' -f $focusText, $blockedCount, $todoCount
    $hash = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($digest))

    if (-not [string]::IsNullOrWhiteSpace([string]$state.lastHeartbeatAt)) {
        try {
            $elapsedSinceLast = (([datetimeoffset](Get-Date)) - [datetimeoffset][string]$state.lastHeartbeatAt).TotalMinutes
            if ($elapsedSinceLast -lt [int]$state.heartbeatMinutes) {
                return $null
            }
        } catch {
        }
    }

    $shouldSend = $true
    if (-not [string]::IsNullOrWhiteSpace([string]$state.lastDigestHash) -and [string]$state.lastDigestHash -eq $hash) {
        $shouldSend = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$state.lastHeartbeatAt)) {
            try {
                $elapsed = (([datetimeoffset](Get-Date)) - [datetimeoffset][string]$state.lastHeartbeatAt).TotalMinutes
                $shouldSend = ($elapsed -ge [int]$state.quietHoursMinutes)
            } catch {
                $shouldSend = $true
            }
        }
    }

    if (-not $shouldSend) {
        return $null
    }

    if (Send-VorceStudiosTelegramMessage -Message $digest -ChatId ([string]$state.transport.telegram.defaultChatId)) {
        $state['lastHeartbeatAt'] = Get-VorceStudiosTimestamp
        $state['lastDigestHash'] = $hash
        Set-VorceStudiosAfkModeState -State $state
        return $digest
    }

    return $null
}
