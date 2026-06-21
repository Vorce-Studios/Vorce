# Write-Log.ps1 (Vorce 3.0)
# Dot-source safe logging helpers for console, session logs and JSONL events.

function Get-VorceLogRoot {
    if ($global:VarDir) {
        return Join-Path $global:VarDir 'log'
    }
    return Join-Path (Join-Path $PSScriptRoot '..\..\..\var') 'log'
}

function Initialize-VorceLogDirectory {
    $logRoot = Get-VorceLogRoot
    $null = New-Item -ItemType Directory -Path $logRoot -Force
    foreach ($relative in @('events', 'sessions', 'crash-reports')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $logRoot $relative) -Force
    }
    return $logRoot
}

function Get-VorceLogPath {
    param(
        [string]$SessionId,
        [string]$Category = 'session',
        [string]$DateStamp
    )

    $logRoot = Initialize-VorceLogDirectory
    switch ($Category) {
        'event' {
            if (-not $DateStamp) { $DateStamp = Get-Date -Format 'yyyyMMdd' }
            return Join-Path $logRoot ("events/vorce-events-$DateStamp.jsonl")
        }
        'error' { return Join-Path $logRoot 'vorce-errors.log' }
        'session' {
            if (-not $SessionId) { $SessionId = 'default' }
            return Join-Path $logRoot ("sessions/$SessionId.log")
        }
        default { return Join-Path $logRoot 'vorce.log' }
    }
}

function Protect-VorceSecretText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $redacted = $Text
    $redacted = $redacted -replace '(Authorization:\s*Bearer\s+)[^\s''"]+', '$1[REDACTED]'
    $redacted = $redacted -replace '\b(ghp_[A-Za-z0-9_]+)\b', '[REDACTED]'
    $redacted = $redacted -replace '\b(github_pat_[A-Za-z0-9_]+)\b', '[REDACTED]'
    $redacted = $redacted -replace '([A-Za-z_][A-Za-z0-9_]*\s*=\s*)(["'']?)([A-Za-z0-9+/=-]{12,})(\2)', '$1$2[REDACTED]$4'

    if ($redacted.Length -gt 500) {
        $redacted = $redacted.Substring(0, 500)
    }

    return $redacted
}

function ConvertTo-VorceJsonSafe {
    param([object]$Value)

    try {
        return $Value | ConvertTo-Json -Depth 12 -Compress
    } catch {
        return '{"serialization_error":true}'
    }
}

function Write-VorceLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'UNKNOWN',
        [string]$EventType = 'diagnostic',
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$RunName,
        [string]$Provider,
        [int]$Attempt,
        [string]$Status,
        [int]$DurationMs,
        [object]$Data = @{},
        [int]$ProcessId = 0
    )

    $logRoot = Initialize-VorceLogDirectory
    $messageText = Protect-VorceSecretText -Text $Message
    $timestamp = Get-Date
    $entry = [ordered]@{
        timestamp = $timestamp.ToString('o')
        level = $Level
        event_type = $EventType
        component = $Component
        session_id = $SessionId
        correlation_id = $CorrelationId
        main_run_id = $MainRunId
        sub_run_id = $SubRunId
        part_run_id = $PartRunId
        run_name = $RunName
        provider = $Provider
        attempt = if ($Attempt -gt 0) { $Attempt } else { $null }
        status = $Status
        duration_ms = if ($DurationMs -gt 0) { $DurationMs } else { $null }
        message = $messageText
        data = $Data
        pid = $ProcessId
    }

    $terminal = "[{0}] [{1}] [{2}] {3}" -f $entry.timestamp, $Level, $Component, $messageText
    switch ($Level) {
        'DEBUG' { Write-Host $terminal -ForegroundColor DarkCyan }
        'INFO' { Write-Host $terminal -ForegroundColor Gray }
        'WARN' { Write-Host $terminal -ForegroundColor Yellow }
        'ERROR' { Write-Host $terminal -ForegroundColor Red }
        'FATAL' { Write-Host $terminal -ForegroundColor Red -BackgroundColor DarkRed }
    }

    $effectiveSessionId = if ($SessionId) { $SessionId } else { 'default' }
    $sessionPath = Get-VorceLogPath -SessionId $effectiveSessionId -Category 'session'
    Add-Content -LiteralPath $sessionPath -Value $terminal -Encoding UTF8

    $jsonlPath = Get-VorceLogPath -Category 'event' -DateStamp (Get-Date -Format 'yyyyMMdd')
    Add-Content -LiteralPath $jsonlPath -Value (ConvertTo-VorceJsonSafe $entry) -Encoding UTF8

    if ($Level -in @('ERROR', 'FATAL')) {
        $errorPath = Get-VorceLogPath -Category 'error'
        Add-Content -LiteralPath $errorPath -Value $terminal -Encoding UTF8
    }

    return [pscustomobject]$entry
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'UNKNOWN',
        [hashtable]$Data = @{}
    )

    return Write-VorceLogEntry -Level $Level -Message $Message -Component $Component -Data $Data
}

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        os_version = $PSVersionTable.PSVersion.ToString()
        hostname = $env:COMPUTERNAME
        powershell = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-ProcessInfo {
    [CmdletBinding()]
    param()

    try {
        return @(
            Get-Process | Where-Object {
                $_.ProcessName -match 'Vorce|vite|dashboard|sync-service|autopilot'
            } | Select-Object Id, ProcessName, Path
        )
    } catch {
        return @()
    }
}

function Write-VorceFatalReport {
    param(
        [string]$Message,
        [string]$Component = 'UNKNOWN',
        [object]$Data = @{}
    )

    $logRoot = Initialize-VorceLogDirectory
    $reportPath = Join-Path $logRoot ("crash-reports/crash-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $report = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        component = $Component
        message = Protect-VorceSecretText -Text $Message
        data = $Data
        system_info = Get-SystemInfo
        process_info = Get-ProcessInfo
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return $reportPath
}
