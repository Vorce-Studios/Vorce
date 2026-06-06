# scripts/codex-cli/lib/quota-manager.ps1
# Manages call counting and budget estimation for AI providers
# Uses atomic writes from state-manager.ps1

Set-StrictMode -Version Latest

$script:QuotaFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "quota-registry.json"

function Read-QuotaRegistry {
    if (-not (Test-Path $script:QuotaFilePath)) {
        throw "quota-registry.json nicht gefunden: $($script:QuotaFilePath)"
    }

    $content = Get-Content $script:QuotaFilePath -Raw -Encoding UTF8
    $registry = $content | ConvertFrom-Json

    # Daily reset check
    $today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
    if ($registry.last_reset_date -ne $today) {
        foreach ($providerName in ($registry.providers.PSObject.Properties.Name)) {
            $provider = $registry.providers.$providerName
            $provider.usage_today.calls = 0
            $provider.usage_today.estimated_cost_usd = 0.0
        }
        $registry.last_reset_date = $today
        Save-QuotaRegistry -Registry $registry
        Write-Host "[QUOTA] Taeglicher Reset durchgefuehrt." -ForegroundColor DarkGray
    }

    return $registry
}

function Save-QuotaRegistry {
    param([Parameter(Mandatory)][object]$Registry)

    # Use atomic write if Write-SafeJson is available (loaded from state-manager.ps1)
    if (Get-Command Write-SafeJson -ErrorAction SilentlyContinue) {
        Write-SafeJson -FilePath $script:QuotaFilePath -Data $Registry
    } else {
        $Registry | ConvertTo-Json -Depth 10 | Set-Content $script:QuotaFilePath -Encoding UTF8
    }
}

function Test-ProviderAvailable {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return $false }
    if (-not $provider.enabled) { return $false }

    # Check call limit
    if ($provider.daily_limit -and [int]$provider.usage_today.calls -ge [int]$provider.daily_limit) {
        return $false
    }

    # Check budget limit
    $hasBudget = $provider.PSObject.Properties.Name -contains "daily_budget_usd"
    if ($hasBudget -and $provider.daily_budget_usd -and [double]$provider.usage_today.estimated_cost_usd -ge [double]$provider.daily_budget_usd) {
        return $false
    }

    # Check auth env var if required
    $hasAuthVar = $provider.PSObject.Properties.Name -contains "auth_env_var"
    if ($hasAuthVar -and -not [string]::IsNullOrWhiteSpace($provider.auth_env_var)) {
        $envVal = [System.Environment]::GetEnvironmentVariable($provider.auth_env_var)
        if ([string]::IsNullOrWhiteSpace($envVal)) {
            return $false
        }
    }

    return $true
}

function Test-PrimaryProvidersAvailable {
    param([Parameter(Mandatory)][object]$Registry)

    $codexAvailable = Test-ProviderAvailable -Registry $Registry -ProviderName "codex_orchestrator"
    $geminiAvailable = Test-ProviderAvailable -Registry $Registry -ProviderName "gemini_cli"

    return $codexAvailable -or $geminiAvailable
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
    $hasDirect = $provider.PSObject.Properties.Name -contains "estimated_cost_per_call_usd"
    if ($hasDirect -and $provider.estimated_cost_per_call_usd) {
        return [double]$provider.estimated_cost_per_call_usd
    }

    # Check model-specific cost
    if ($provider.models -and $provider.models.$ModelTier) {
        return [double]$provider.models.$ModelTier.estimated_cost_per_call_usd
    }

    # Fallback: try first available model
    if ($provider.models) {
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

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return }

    $cost = Get-EstimatedCost -Registry $Registry -ProviderName $ProviderName -ModelTier $ModelTier
    $provider.usage_today.calls = [int]$provider.usage_today.calls + 1
    $provider.usage_today.estimated_cost_usd = [Math]::Round([double]$provider.usage_today.estimated_cost_usd + $cost, 4)

    Save-QuotaRegistry -Registry $Registry
}

function Get-QuotaSummary {
    param([Parameter(Mandatory)][object]$Registry)

    $lines = @()
    $lines += "--- Quota Status ---"

    foreach ($name in ($Registry.providers.PSObject.Properties.Name)) {
        $p = $Registry.providers.$name
        $status = if ($p.enabled) { "ON" } else { "OFF" }
        $calls = [int]$p.usage_today.calls

        $hasLimit = $p.PSObject.Properties.Name -contains "daily_limit"
        $limitStr = if ($hasLimit -and $p.daily_limit) { [string][int]$p.daily_limit } else { "n/a" }

        $cost = [Math]::Round([double]$p.usage_today.estimated_cost_usd, 2)

        $hasBudget = $p.PSObject.Properties.Name -contains "daily_budget_usd"
        $budgetStr = if ($hasBudget -and $p.daily_budget_usd) { "`${0}" -f [Math]::Round([double]$p.daily_budget_usd, 2) } else { "n/a" }

        $lines += ("  {0,-15} [{1}]  Calls: {2}/{3}  Cost: `${4}/{5}" -f $name, $status, $calls, $limitStr, $cost, $budgetStr)
    }

    return ($lines -join "`n")
}

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory)][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $false }
    if ($null -eq $Object.PSObject) { return $false }
    return $Object.PSObject.Properties.Name -contains $Name
}

function Set-ProviderUsageSnapshot {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][object]$UsageToday
    )

    $provider = $Registry.providers.$ProviderName
    if ($null -eq $provider) { return }

    $provider.usage_today = $UsageToday
    Save-QuotaRegistry -Registry $Registry
}

function Initialize-ProviderUsageToday {
    param([Parameter(Mandatory)][object]$Provider)

    if (-not (Test-ObjectProperty -Object $Provider -Name "usage_today") -or $null -eq $Provider.usage_today) {
        $Provider | Add-Member -MemberType NoteProperty -Name "usage_today" -Value ([pscustomobject]@{
            calls = 0
            estimated_cost_usd = 0.0
        }) -Force
    } else {
        $usage = $Provider.usage_today
        if (-not (Test-ObjectProperty -Object $usage -Name "calls")) {
            $usage | Add-Member -MemberType NoteProperty -Name "calls" -Value 0 -Force
        }
        if (-not (Test-ObjectProperty -Object $usage -Name "estimated_cost_usd")) {
            $usage | Add-Member -MemberType NoteProperty -Name "estimated_cost_usd" -Value 0.0 -Force
        }
    }
}

function Get-ProviderUsageTotals {
    param([Parameter(Mandatory)][object]$Provider)
    return [pscustomobject]@{
        calls = if (Test-ObjectProperty -Object $Provider.usage_today -Name "calls") { $Provider.usage_today.calls } else { 0 }
        estimated_cost_usd = if (Test-ObjectProperty -Object $Provider.usage_today -Name "estimated_cost_usd") { $Provider.usage_today.estimated_cost_usd } else { 0.0 }
    }
}
