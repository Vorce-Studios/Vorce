# scripts/codex-cli/lib/quota-manager.ps1
# Manages call counting and budget estimation for AI providers

Set-StrictMode -Version Latest

# Dot-source state-manager to get Read-JsonLocked/Write-JsonLocked
. (Join-Path $PSScriptRoot "state-manager.ps1")

$script:QuotaFilePath = Join-Path (Split-Path -Parent $PSScriptRoot) "quota-registry.json"

function Test-ObjectProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    return $null -ne ($Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

function Ensure-ProviderUsageToday {
    param([Parameter(Mandatory)][object]$Provider)

    if (-not (Test-ObjectProperty -Object $Provider -Name "usage_today") -or $null -eq $Provider.usage_today) {
        $Provider | Add-Member -MemberType NoteProperty -Name "usage_today" -Value ([pscustomobject]@{}) -Force
    }

    if (-not (Test-ObjectProperty -Object $Provider.usage_today -Name "calls")) {
        $Provider.usage_today | Add-Member -MemberType NoteProperty -Name "calls" -Value 0 -Force
    }
    if (-not (Test-ObjectProperty -Object $Provider.usage_today -Name "estimated_cost_usd")) {
        $Provider.usage_today | Add-Member -MemberType NoteProperty -Name "estimated_cost_usd" -Value 0.0 -Force
    }
}

function Ensure-ModelUsageBucket {
    param(
        [Parameter(Mandatory)][object]$Provider,
        [Parameter(Mandatory)][string]$ModelName
    )

    Ensure-ProviderUsageToday -Provider $Provider
    if (-not (Test-ObjectProperty -Object $Provider.usage_today -Name $ModelName) -or $null -eq $Provider.usage_today.$ModelName) {
        $Provider.usage_today | Add-Member -MemberType NoteProperty -Name $ModelName -Value ([pscustomobject]@{
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

    $bucket = $Provider.usage_today.$ModelName
    foreach ($field in @("calls", "estimated_cost_usd", "total_input_tokens", "total_output_tokens", "cached_tokens", "reasoning_tokens", "tool_tokens", "total_duration_ms")) {
        if (-not (Test-ObjectProperty -Object $bucket -Name $field)) {
            $value = if ($field -eq "estimated_cost_usd") { 0.0 } else { 0 }
            $bucket | Add-Member -MemberType NoteProperty -Name $field -Value $value -Force
        }
    }

    return $bucket
}

function Get-ProviderModelName {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$ModelTier = "default"
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return $ModelTier }
    if ((Test-ObjectProperty -Object $provider -Name "models") -and $provider.models -and (Test-ObjectProperty -Object $provider.models -Name $ModelTier)) {
        return [string]$provider.models.$ModelTier.name
    }
    return $ModelTier
}

function Get-ProviderUsageTotals {
    param([Parameter(Mandatory)][object]$Provider)

    $directCalls = 0
    $directCost = 0.0
    $modelCalls = 0
    $modelCost = 0.0

    if ((Test-ObjectProperty -Object $Provider -Name "usage_today") -and $Provider.usage_today) {
        foreach ($prop in $Provider.usage_today.PSObject.Properties) {
            if ($prop.Name -eq "calls") {
                if ($null -ne $prop.Value) { $directCalls = [int]$prop.Value }
                continue
            }
            if ($prop.Name -eq "estimated_cost_usd") {
                if ($null -ne $prop.Value) { $directCost = [double]$prop.Value }
                continue
            }

            $value = $prop.Value
            if ($null -ne $value -and (Test-ObjectProperty -Object $value -Name "calls")) {
                $modelCalls += [int]$value.calls
                if (Test-ObjectProperty -Object $value -Name "estimated_cost_usd") {
                    $modelCost += [double]$value.estimated_cost_usd
                }
            }
        }
    }

    return [pscustomobject]@{
        calls = $(if ($modelCalls -gt 0) { $modelCalls } else { $directCalls })
        estimated_cost_usd = $(if ($modelCost -gt 0) { $modelCost } else { $directCost })
    }
}

function Copy-ObjectProperties {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Source
    )

    foreach ($prop in $Source.PSObject.Properties) {
        $Target | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
    }
}

function Read-QuotaRegistry {
    if (-not (Test-Path $script:QuotaFilePath)) {
        throw "quota-registry.json nicht gefunden: $($script:QuotaFilePath)"
    }

    $registry = Read-JsonLocked -Path $script:QuotaFilePath
    if ($null -eq $registry) {
        throw "quota-registry.json konnte nicht gelesen werden (Lock/Format Error)"
    }

    # Daily reset check
    $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    if ($registry.last_reset_date -ne $today) {
        foreach ($providerName in ($registry.providers.PSObject.Properties.Name)) {
            $provider = $registry.providers.$providerName
            Ensure-ProviderUsageToday -Provider $provider
            Reset-UsageObject -Obj $provider.usage_today
            Ensure-ProviderUsageToday -Provider $provider
        }
        $registry.last_reset_date = $today
        Save-QuotaRegistry -Registry $registry
        Write-Host "[QUOTA] Taeglicher Reset durchgefuehrt." -ForegroundColor DarkGray
    }

    return $registry
}

function Reset-UsageObject {
    param([Parameter(Mandatory)][object]$Obj)

    foreach ($prop in $Obj.PSObject.Properties) {
        if ($prop.Value -is [System.Management.Automation.PSCustomObject] -or $prop.Value -is [System.Collections.IDictionary]) {
            Reset-UsageObject -Obj $prop.Value
        }
        else {
            if ($prop.Value -is [int] -or $prop.Value -is [long] -or $prop.Value -is [double] -or $prop.Value -is [decimal] -or $prop.Name -match "calls|tokens|cost|ms|requests") {
                if ($prop.Name -like "*cost*") {
                    $prop.Value = 0.0
                } else {
                    $prop.Value = 0
                }
            }
        }
    }
}

function Save-QuotaRegistry {
    param([Parameter(Mandatory)][object]$Registry)

    Write-JsonLocked -Path $script:QuotaFilePath -Data $Registry | Out-Null
}

function Test-ProviderAvailable {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return $false }
    if (-not $provider.enabled) { return $false }

    if ((Test-ObjectProperty -Object $provider -Name "command") -and -not [string]::IsNullOrWhiteSpace([string]$provider.command)) {
        if (-not (Get-Command ([string]$provider.command) -ErrorAction SilentlyContinue)) {
            return $false
        }
    }

    Ensure-ProviderUsageToday -Provider $provider
    $totals = Get-ProviderUsageTotals -Provider $provider
    $calls = [int]$totals.calls
    $cost = [double]$totals.estimated_cost_usd

    # Check call limit
    if ((Test-ObjectProperty -Object $provider -Name "daily_limit") -and $provider.daily_limit -and $calls -ge [int]$provider.daily_limit) {
        return $false
    }

    # Check budget limit
    $hasBudget = Test-ObjectProperty -Object $provider -Name "daily_budget_usd"
    if ($hasBudget -and $provider.daily_budget_usd -and $cost -ge [double]$provider.daily_budget_usd) {
        return $false
    }

    # Check auth env var if required
    $authEnvVar = if (Test-ObjectProperty -Object $provider -Name "auth_env_var") { [string]$provider.auth_env_var } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($authEnvVar)) {
        $envVal = [System.Environment]::GetEnvironmentVariable($authEnvVar)
        if ([string]::IsNullOrWhiteSpace($envVal)) {
            return $false
        }
    }

    return $true
}

function Get-EstimatedCost {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$ModelTier = "default"
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return 0.0 }

    # Jules has no model tiers - check for direct cost field
    $hasDirect = Test-ObjectProperty -Object $provider -Name "estimated_cost_per_call_usd"
    if ($hasDirect -and $provider.estimated_cost_per_call_usd) {
        return [double]$provider.estimated_cost_per_call_usd
    }

    # Check model-specific cost
    if ((Test-ObjectProperty -Object $provider -Name "models") -and $provider.models -and (Test-ObjectProperty -Object $provider.models -Name $ModelTier)) {
        return [double]$provider.models.$ModelTier.estimated_cost_per_call_usd
    }

    # Fallback: try first available model
    if ((Test-ObjectProperty -Object $provider -Name "models") -and $provider.models) {
        $firstModel = $provider.models.PSObject.Properties | Select-Object -First 1
        if ($firstModel) {
            return [double]$firstModel.Value.estimated_cost_per_call_usd
        }
    }

    return 0.0
}

function Register-ProviderCall {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$ModelTier = "default"
    )

    $updatedRegistry = Update-JsonLocked -Path $script:QuotaFilePath -DefaultValue $Registry -Updater {
        param($latestRegistry)

        if ($null -eq $latestRegistry -or $null -eq $latestRegistry.providers) {
            $latestRegistry = $Registry
        }

        $provider = $latestRegistry.providers.$ProviderName
        if ($null -eq $provider) { return $latestRegistry }

        Ensure-ProviderUsageToday -Provider $provider

        $cost = Get-EstimatedCost -Registry $latestRegistry -ProviderName $ProviderName -ModelTier $ModelTier
        $provider.usage_today.calls = [int]$provider.usage_today.calls + 1
        $provider.usage_today.estimated_cost_usd = [Math]::Round([double]$provider.usage_today.estimated_cost_usd + $cost, 4)

        $modelName = Get-ProviderModelName -Registry $latestRegistry -ProviderName $ProviderName -ModelTier $ModelTier
        if (-not [string]::IsNullOrWhiteSpace($modelName) -and $modelName -ne "default") {
            $bucket = Ensure-ModelUsageBucket -Provider $provider -ModelName $modelName
            $bucket.calls = [int]$bucket.calls + 1
            $bucket.estimated_cost_usd = [Math]::Round([double]$bucket.estimated_cost_usd + $cost, 4)
        }

        return $latestRegistry
    }

    Copy-ObjectProperties -Target $Registry -Source $updatedRegistry
}

function Set-ProviderUsageSnapshot {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][object]$UsageToday
    )

    $updatedRegistry = Update-JsonLocked -Path $script:QuotaFilePath -DefaultValue $Registry -Updater {
        param($latestRegistry)

        if ($null -eq $latestRegistry -or $null -eq $latestRegistry.providers) {
            $latestRegistry = $Registry
        }

        $provider = $latestRegistry.providers.$ProviderName
        if ($null -eq $provider) { return $latestRegistry }

        Ensure-ProviderUsageToday -Provider $provider

        $snapshot = $UsageToday
        if (-not (Test-ObjectProperty -Object $snapshot -Name "calls")) {
            $snapshot | Add-Member -MemberType NoteProperty -Name "calls" -Value 0 -Force
        }
        if (-not (Test-ObjectProperty -Object $snapshot -Name "estimated_cost_usd")) {
            $snapshot | Add-Member -MemberType NoteProperty -Name "estimated_cost_usd" -Value 0.0 -Force
        }

        $provider.usage_today = $snapshot
        Ensure-ProviderUsageToday -Provider $provider

        return $latestRegistry
    }

    Copy-ObjectProperties -Target $Registry -Source $updatedRegistry
}

function Get-QuotaSummary {
    param([Parameter(Mandatory)][object]$Registry)

    $lines = @()
    $lines += "--- Quota Status ---"

    foreach ($name in ($Registry.providers.PSObject.Properties.Name)) {
        $p = $Registry.providers.$name
        $status = if ($p.enabled) { "ON" } else { "OFF" }

        Ensure-ProviderUsageToday -Provider $p
        $totals = Get-ProviderUsageTotals -Provider $p
        $calls = [int]$totals.calls
        $hasLimit = Test-ObjectProperty -Object $p -Name "daily_limit"
        $limitStr = if ($hasLimit -and $p.daily_limit) { [string][int]$p.daily_limit } else { "n/a" }

        if ($name -eq "jules" -and (Test-ObjectProperty -Object $p.usage_today -Name "api_sessions_today")) {
            $calls = [int]$p.usage_today.api_sessions_today
            $active = if (Test-ObjectProperty -Object $p.usage_today -Name "active_sessions") { [int]$p.usage_today.active_sessions } else { 0 }
            $pending = if (Test-ObjectProperty -Object $p.usage_today -Name "pending_sessions") { [int]$p.usage_today.pending_sessions } else { 0 }
            $completed = if (Test-ObjectProperty -Object $p.usage_today -Name "completed_sessions") { [int]$p.usage_today.completed_sessions } else { 0 }
            $lines += ("  {0,-18} [{1}] Sessions: {2}/{3}  Active: {4}  Waiting: {5}  Done: {6}" -f $name, $status, $calls, $limitStr, $active, $pending, $completed)
            continue
        }

        if ((Test-ObjectProperty -Object $p.usage_today -Name "rate_limits") -and $p.usage_today.rate_limits) {
            $rate = $p.usage_today.rate_limits
            $primaryText = "n/a"
            $secondaryText = "n/a"
            if ((Test-ObjectProperty -Object $rate -Name "primary") -and $rate.primary) {
                $primaryWindow = if (Test-ObjectProperty -Object $rate.primary -Name "window_minutes") { $rate.primary.window_minutes } else { 0 }
                $primaryLabel = if ((Test-ObjectProperty -Object $rate.primary -Name "label") -and -not [string]::IsNullOrWhiteSpace([string]$rate.primary.label)) { [string]$rate.primary.label } else { formatQuotaWindowForSummary $primaryWindow }
                $primaryText = "{0}: {1:N1}%" -f $primaryLabel, [double]$rate.primary.used_percent
            }
            if ((Test-ObjectProperty -Object $rate -Name "secondary") -and $rate.secondary) {
                $secondaryWindow = if (Test-ObjectProperty -Object $rate.secondary -Name "window_minutes") { $rate.secondary.window_minutes } else { 0 }
                $secondaryLabel = if ((Test-ObjectProperty -Object $rate.secondary -Name "label") -and -not [string]::IsNullOrWhiteSpace([string]$rate.secondary.label)) { [string]$rate.secondary.label } else { formatQuotaWindowForSummary $secondaryWindow }
                $secondaryText = "{0}: {1:N1}%" -f $secondaryLabel, [double]$rate.secondary.used_percent
            }

            $tokenTotal = 0
            foreach ($usageProp in $p.usage_today.PSObject.Properties) {
                $bucket = $usageProp.Value
                if ($null -ne $bucket -and (Test-ObjectProperty -Object $bucket -Name "total_input_tokens")) {
                    $tokenTotal += [int64]$bucket.total_input_tokens
                    if (Test-ObjectProperty -Object $bucket -Name "total_output_tokens") {
                        $tokenTotal += [int64]$bucket.total_output_tokens
                    }
                }
            }

            $lines += ("  {0,-18} [{1}] Calls: {2}/{3}  Quota: {4}, {5}  Tokens: {6:N0}" -f $name, $status, $calls, $limitStr, $primaryText, $secondaryText, $tokenTotal)
            continue
        }

        $lines += ("  {0,-18} [{1}] Calls: {2}/{3}" -f $name, $status, $calls, $limitStr)
    }

    return ($lines -join "`n")
}

function formatQuotaWindowForSummary {
    param([AllowNull()][object]$Minutes)

    $value = 0
    try { $value = [int]$Minutes } catch { return "quota" }
    if ($value -eq 300) { return "5h" }
    if ($value -eq 10080) { return "week" }
    if ($value -ge 1440) { return ("{0}d" -f [Math]::Round($value / 1440)) }
    if ($value -ge 60) { return ("{0}h" -f [Math]::Round($value / 60)) }
    if ($value -gt 0) { return ("{0}m" -f $value) }
    return "quota"
}
