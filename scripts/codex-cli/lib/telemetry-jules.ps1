function Read-TelemetryState {
    $state = Read-JsonLocked -Path $script:TelemetryStatePath
    if ($null -eq $state) {
        return [pscustomobject]@{}
    }
    return $state
}

function Write-TelemetryState {
    param([Parameter(Mandatory)][object]$State)
    Write-JsonLocked -Path $script:TelemetryStatePath -Data $State | Out-Null
}

function Test-ShouldPollJulesTelemetry {
    param(
        [Parameter(Mandatory)][object]$State,
        [int]$IntervalSeconds = 300
    )

    $lastPoll = [string](Get-TelemetryPropertyValue -Object $State -Name "jules_last_poll_at")
    if ([string]::IsNullOrWhiteSpace($lastPoll)) { return $true }

    try {
        $last = [datetimeoffset]::Parse($lastPoll, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return ((Get-Date).ToUniversalTime() - $last.UtcDateTime).TotalSeconds -ge $IntervalSeconds
    } catch {
        return $true
    }
}

function Get-JulesSessionTimestamp {
    param([AllowNull()][object]$Session)

    foreach ($field in @("createTime", "createdAt", "startTime", "updateTime", "updatedAt")) {
        $value = Get-TelemetryPropertyValue -Object $Session -Name $field
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return $value
        }
    }

    return $null
}

function Get-JulesSessionSourceName {
    param([AllowNull()][object]$Session)

    $sourceContext = Get-TelemetryPropertyValue -Object $Session -Name "sourceContext"
    return [string](Get-TelemetryPropertyValue -Object $sourceContext -Name "source")
}

function Test-JulesSessionCreatedOnReportDate {
    param(
        [AllowNull()][object]$Session,
        [Parameter(Mandatory)][string]$ReportDate
    )

    $timestampFields = @("createTime", "createdAt", "startTime", "startedAt")
    $hasTimestamp = $false

    foreach ($field in $timestampFields) {
        $value = Get-TelemetryPropertyValue -Object $Session -Name $field
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $hasTimestamp = $true
        if (Test-TelemetryTimestampMatchesDateLocalOrUtc -Timestamp $value -Date $ReportDate) {
            return $true
        }
    }

    return $false
}

function Get-JulesTelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ReportDate,
        [AllowNull()][object]$Config,
        [string]$StatePath
    )

    $usage = New-TelemetryUsage
    $usage.source = "jules-api"
    $usage | Add-Member -MemberType NoteProperty -Name "active_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "completed_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "failed_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "pending_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_capacity_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_in_progress_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_queued_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "live_waiting_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "account_sessions_observed_today" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "account_sessions_observed_rolling_24h" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_capacity_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_in_progress_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_queued_sessions" -Value 0 -Force
    $usage | Add-Member -MemberType NoteProperty -Name "scoped_live_waiting_sessions" -Value 0 -Force

    $state = if (-not [string]::IsNullOrWhiteSpace($StatePath) -and (Test-Path $StatePath)) { Read-JsonLocked -Path $StatePath } else { $null }

    try {
        if (-not (Get-Command Get-AllJulesSessions -ErrorAction SilentlyContinue)) {
            throw "Jules API helper not loaded."
        }

        $pageSize = 50
        $maxPages = 10
        if ($Config -and (Test-ObjectProperty -Object $Config -Name "jules")) {
            $configuredMaxPages = Get-TelemetryNumber (Get-TelemetryPropertyValue -Object $Config.jules -Name "session_poll_max_pages")
            if ($configuredMaxPages -gt 0) {
                $maxPages = [int]$configuredMaxPages
            }
        }

        $sessions = @(Get-AllJulesSessions -PageSize $pageSize -MaxPages $maxPages)
        $usage | Add-Member -MemberType NoteProperty -Name "api_sessions_seen" -Value $sessions.Count -Force
        $usage | Add-Member -MemberType NoteProperty -Name "api_sessions_today" -Value 0 -Force

        $scopedSources = @()
        if ($Config -and (Test-ObjectProperty -Object $Config -Name "repository") -and -not [string]::IsNullOrWhiteSpace([string]$Config.repository)) {
            $primaryRepo = [string]$Config.repository
            $scopedSources += "sources/github/$primaryRepo"
            if ($primaryRepo -eq "Vorce-Studios/Vorce") {
                $scopedSources += "sources/github/MrLongNight/MapFlow"
            }
        }
        $now = [datetimeoffset]::Now

        foreach ($session in $sessions) {
            $stateName = [string](Get-TelemetryPropertyValue -Object $session -Name "state")
            if ([string]::IsNullOrWhiteSpace($stateName)) { $stateName = "UNKNOWN" }
            $sessionSource = Get-JulesSessionSourceName -Session $session
            $isScoped = $scopedSources.Count -gt 0 -and $sessionSource -in $scopedSources

            switch -Regex ($stateName) {
                "^IN_PROGRESS$" { $usage.live_in_progress_sessions = [int64]$usage.live_in_progress_sessions + 1; $usage.live_capacity_sessions = [int64]$usage.live_capacity_sessions + 1; break }
                "^QUEUED$|^PLANNING$|^AWAITING_PLAN_APPROVAL$" { $usage.live_queued_sessions = [int64]$usage.live_queued_sessions + 1; $usage.live_capacity_sessions = [int64]$usage.live_capacity_sessions + 1; break }
                "^AWAITING_USER_FEEDBACK$|^PAUSED$" { $usage.live_waiting_sessions = [int64]$usage.live_waiting_sessions + 1; break }
            }

            if ($isScoped) {
                switch -Regex ($stateName) {
                    "^IN_PROGRESS$" { $usage.scoped_live_in_progress_sessions = [int64]$usage.scoped_live_in_progress_sessions + 1; $usage.scoped_live_capacity_sessions = [int64]$usage.scoped_live_capacity_sessions + 1; break }
                    "^QUEUED$|^PLANNING$|^AWAITING_PLAN_APPROVAL$" { $usage.scoped_live_queued_sessions = [int64]$usage.scoped_live_queued_sessions + 1; $usage.scoped_live_capacity_sessions = [int64]$usage.scoped_live_capacity_sessions + 1; break }
                    "^AWAITING_USER_FEEDBACK$|^PAUSED$" { $usage.scoped_live_waiting_sessions = [int64]$usage.scoped_live_waiting_sessions + 1; break }
                }
            }

            try {
                $createdAt = [datetimeoffset]::Parse([string](Get-TelemetryPropertyValue -Object $session -Name "createTime"))
                if (($now - $createdAt.ToLocalTime()) -lt [timespan]::FromHours(24)) {
                    $usage.account_sessions_observed_rolling_24h = [int64]$usage.account_sessions_observed_rolling_24h + 1
                }
            } catch { }

            if (-not (Test-JulesSessionCreatedOnReportDate -Session $session -ReportDate $ReportDate)) {
                continue
            }
            $usage.account_sessions_observed_today = [int64]$usage.account_sessions_observed_today + 1
            $usage.api_sessions_today = [int64]$usage.api_sessions_today + 1

            switch -Regex ($stateName) {
                "FAILED|ERROR|CANCEL" { $usage.failed_sessions = [int64]$usage.failed_sessions + 1; break }
                "COMPLETE|MERGED|DONE" { $usage.completed_sessions = [int64]$usage.completed_sessions + 1; break }
            }

            Add-TelemetryUsage -Usage $usage -ModelName "sessions" -Calls 1
        }
        $usage.active_sessions = [int64]$usage.scoped_live_capacity_sessions
        $usage.pending_sessions = [int64]$usage.scoped_live_waiting_sessions
    } catch {
        $usage.source = "jules-api-fallback"
        $usage | Add-Member -MemberType NoteProperty -Name "last_error" -Value $_.Exception.Message -Force

        if ($null -ne $state -and (Test-ObjectProperty -Object $state -Name "active_delegations")) {
            foreach ($delegation in @($state.active_delegations)) {
                Add-TelemetryUsage -Usage $usage -ModelName "sessions" -Calls 1
                $usage.active_sessions = [int64]$usage.active_sessions + 1
            }
        }
    }

    return $usage
}
