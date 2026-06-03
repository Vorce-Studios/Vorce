# scripts/codex-cli/lib/telemetry-manager.ps1
# Collects local CLI telemetry and Jules API session snapshots for quota reporting.

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "quota-manager.ps1")

$script:TelemetryStatePath = Join-Path (Split-Path -Parent $PSScriptRoot) "telemetry-state.json"
$script:JulesApiPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "jules\jules-api.ps1"
$script:GeminiQuotaHelperPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tools\gemini-quota.mjs"
if (Test-Path $script:JulesApiPath) {
    . $script:JulesApiPath
}

function New-TelemetryUsage {
    return [pscustomobject]@{
        calls = 0
        estimated_cost_usd = 0.0
        source = "telemetry"
        last_synced_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Get-TelemetryNumber {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function Get-TelemetryDouble {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 0.0 }
    try { return [double]$Value } catch { return 0.0 }
}

function Convert-TelemetryResetToEpochSeconds {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }

    try {
        $numeric = [double]$Value
        if ($numeric -gt 0) { return [int64][Math]::Round($numeric) }
    } catch {
        # Fall through and try ISO/date parsing.
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

function Convert-TelemetryTimestampToIsoString {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return (Get-Date).ToUniversalTime().ToString("o")
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString("o")
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("o")
    } catch {
        return [string]$Value
    }
}

function Get-TelemetryPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Test-TelemetryTimestampMatchesDate {
    param(
        [AllowNull()][object]$Timestamp,
        [Parameter(Mandatory)][string]$Date
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return $false
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("yyyy-MM-dd") -eq $Date
    } catch {
        return $false
    }
}

function Test-TelemetryTimestampMatchesDateLocalOrUtc {
    param(
        [AllowNull()][object]$Timestamp,
        [Parameter(Mandatory)][string]$Date
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return $false
    }

    try {
        $dto = [datetimeoffset]::Parse([string]$Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dto.UtcDateTime.ToString("yyyy-MM-dd") -eq $Date -or $dto.LocalDateTime.ToString("yyyy-MM-dd") -eq $Date
    } catch {
        return $false
    }
}

function Get-TelemetryReportRange {
    param([Parameter(Mandatory)][string]$Date)

    try {
        $start = [datetime]::SpecifyKind(
            [datetime]::ParseExact($Date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture),
            [System.DateTimeKind]::Utc
        )
    } catch {
        $start = [datetime]::UtcNow.Date
    }

    return [pscustomobject]@{
        Start = $start
        End = $start.AddDays(1)
    }
}

function Get-TelemetrySessionDirectories {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][datetime]$Now
    )

    if (-not (Test-Path $Root)) { return @() }

    $dates = @(
        $Now.ToUniversalTime().AddDays(-1),
        $Now.ToUniversalTime(),
        $Now.ToUniversalTime().AddDays(1),
        $Now.AddDays(-1),
        $Now,
        $Now.AddDays(1)
    )

    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($date in $dates) {
        $path = Join-Path $Root ($date.ToString("yyyy\\MM\\dd"))
        if (Test-Path $path) {
            [void]$paths.Add([System.IO.Path]::GetFullPath($path))
        }
    }

    return @($paths)
}

function Read-TelemetryJsonlLines {
    param([Parameter(Mandatory)][string]$Path)

    $lines = [System.Collections.Generic.List[string]]::new()
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        while (-not $reader.EndOfStream) {
            [void]$lines.Add($reader.ReadLine())
        }
    } catch {
        return @()
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }

    return @($lines)
}

function Add-TelemetryUsage {
    param(
        [Parameter(Mandatory)][object]$Usage,
        [Parameter(Mandatory)][string]$ModelName,
        [int64]$Calls = 1,
        [int64]$InputTokens = 0,
        [int64]$OutputTokens = 0,
        [int64]$CachedTokens = 0,
        [int64]$ReasoningTokens = 0,
        [int64]$ToolTokens = 0,
        [int64]$DurationMs = 0,
        [double]$CostUsd = 0.0
    )

    $safeModelName = if ([string]::IsNullOrWhiteSpace($ModelName)) { "unknown" } else { $ModelName }

    if (-not (Test-ObjectProperty -Object $Usage -Name $safeModelName) -or $null -eq $Usage.$safeModelName) {
        $Usage | Add-Member -MemberType NoteProperty -Name $safeModelName -Value ([pscustomobject]@{
            calls = 0
            estimated_cost_usd = 0.0
            total_input_tokens = 0
            total_output_tokens = 0
            cached_tokens = 0
            reasoning_tokens = 0
            tool_tokens = 0
            total_duration_ms = 0
        }) -Force
    }

    $bucket = $Usage.$safeModelName
    $bucket.calls = [int64]$bucket.calls + $Calls
    $bucket.estimated_cost_usd = [Math]::Round([double]$bucket.estimated_cost_usd + $CostUsd, 6)
    $bucket.total_input_tokens = [int64]$bucket.total_input_tokens + $InputTokens
    $bucket.total_output_tokens = [int64]$bucket.total_output_tokens + $OutputTokens
    $bucket.cached_tokens = [int64]$bucket.cached_tokens + $CachedTokens
    $bucket.reasoning_tokens = [int64]$bucket.reasoning_tokens + $ReasoningTokens
    $bucket.tool_tokens = [int64]$bucket.tool_tokens + $ToolTokens
    $bucket.total_duration_ms = [int64]$bucket.total_duration_ms + $DurationMs

    $Usage.calls = [int64]$Usage.calls + $Calls
    $Usage.estimated_cost_usd = [Math]::Round([double]$Usage.estimated_cost_usd + $CostUsd, 6)
}

function Get-ModelCostPerCall {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$ModelName
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return 0.0 }

    if ((Test-ObjectProperty -Object $provider -Name "models") -and $provider.models) {
        foreach ($modelProp in $provider.models.PSObject.Properties) {
            $configuredName = [string](Get-TelemetryPropertyValue -Object $modelProp.Value -Name "name")
            if ($configuredName -eq $ModelName) {
                return Get-TelemetryDouble (Get-TelemetryPropertyValue -Object $modelProp.Value -Name "estimated_cost_per_call_usd")
            }
        }
    }

    if (Test-ObjectProperty -Object $provider -Name "estimated_cost_per_call_usd") {
        return Get-TelemetryDouble $provider.estimated_cost_per_call_usd
    }

    return 0.0
}
