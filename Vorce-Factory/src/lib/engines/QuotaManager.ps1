# QuotaManager.ps1 (Vorce 3.0)
# Quota-Management fuer alle AI-Provider und CLI-Kommandos.

$providerRegistryPath = Join-Path $PSScriptRoot '..\integrations\ProviderRegistry.ps1'
if (-not (Get-Command Resolve-VorceProviderId -ErrorAction SilentlyContinue)) {
    . $providerRegistryPath
}

function Read-VorceQuotaRegistry {
    param()

    $registryPath = Join-Path $global:VarDir 'config/quota-registry.json'
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return [pscustomobject]@{}
    }

    try {
        $content = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content) -or $content -eq 'null') {
            return [pscustomobject]@{}
        }
        return $content | ConvertFrom-Json
    } catch {
        Write-Warning "Fehler beim Lesen der Quota Registry: $($_.Exception.Message)"
        return $null
    }
}

function Save-VorceQuotaRegistry {
    param([Parameter(Mandatory)][object]$Registry)

    $registryPath = Join-Path $global:VarDir 'config/quota-registry.json'
    $registryDir = Split-Path -Parent $registryPath
    if (-not (Test-Path -LiteralPath $registryDir)) {
        $null = New-Item -ItemType Directory -Path $registryDir -Force
    }

    try {
        $tempPath = "$registryPath.$([guid]::NewGuid().ToString('N')).tmp"
        $Registry | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        Move-Item -LiteralPath $tempPath -Destination $registryPath -Force
        if (Test-Path 'Variable:global:VorceExhaustedProviders') {
            $global:VorceExhaustedProviders = @{}
        }
        return $true
    } catch {
        Write-Warning "Fehler beim Speichern der Quota Registry: $($_.Exception.Message)"
        return $false
    }
}

function Get-VorceQuotaStatus {
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [string]$ModelTier = 'default'
    )

    $resolved = Resolve-VorceProviderId -ProviderName $AgentName
    if ($resolved -isnot [string]) {
        return [pscustomobject]@{
            available = $false
            provider_id = $null
            model_tier = $ModelTier
            error_class = 'unknown_provider'
        }
    }

    $registry = Read-VorceQuotaRegistry
    $providers = if ($registry) { $registry.providers } else { $null }
    if ($null -eq $providers -or $providers.PSObject.Properties.Name -notcontains $resolved) {
        return [pscustomobject]@{
            available = $false
            provider_id = $resolved
            model_tier = $ModelTier
            error_class = 'unknown_provider'
        }
    }

    $provider = $providers.$resolved
    if ($provider.enabled -ne $true) {
        return [pscustomobject]@{
            available = $false
            provider_id = $resolved
            model_tier = $ModelTier
            error_class = 'disabled'
        }
    }

    $usage = $provider.usage_today
    $calls = if ($usage -and $null -ne $usage.calls) { [int]$usage.calls } else { 0 }
    $cost = if ($usage -and $null -ne $usage.estimated_cost_usd) {
        [double]$usage.estimated_cost_usd
    } else {
        0.0
    }
    if ($provider.daily_limit -and $calls -ge [int]$provider.daily_limit) {
        return [pscustomobject]@{
            available = $false
            provider_id = $resolved
            model_tier = $ModelTier
            error_class = 'quota_exhausted'
        }
    }
    if ($provider.daily_budget_usd -and $cost -ge [double]$provider.daily_budget_usd) {
        return [pscustomobject]@{
            available = $false
            provider_id = $resolved
            model_tier = $ModelTier
            error_class = 'quota_exhausted'
        }
    }

    return [pscustomobject]@{
        available = $true
        provider_id = $resolved
        model_tier = $ModelTier
        error_class = $null
    }
}

function Test-VorceQuota {
    param(
        [string]$AgentName,
        [string]$ModelTier = 'default'
    )

    $status = Get-VorceQuotaStatus -AgentName $AgentName -ModelTier $ModelTier
    if (-not $status.available) { return $false }

    $registry = Read-VorceQuotaRegistry
    $provider = $registry.providers.($status.provider_id)
    if ($provider.command -and -not (Get-Command $provider.command -ErrorAction SilentlyContinue)) {
        return $false
    }
    return $true
}

function Add-VorceUsageProperty {
    param(
        [Parameter(Mandatory)][object]$Usage,
        [Parameter(Mandatory)][string]$Name,
        [object]$DefaultValue = 0
    )

    if ($Usage.PSObject.Properties.Name -notcontains $Name) {
        $Usage | Add-Member -MemberType NoteProperty -Name $Name -Value $DefaultValue -Force
    }
}

function Register-VorceQuotaUsage {
    param(
        [string]$AgentName,
        [string]$ModelTier = 'default',
        [double]$Cost = 0,
        [ValidateSet('success', 'retryable_failure', 'failure')]
        [string]$Outcome = 'success'
    )

    $resolved = Resolve-VorceProviderId -ProviderName $AgentName
    if ($resolved -isnot [string]) {
        return [pscustomobject]@{
            registered = $false
            provider_id = $null
            error_class = 'unknown_provider'
        }
    }

    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry -or $null -eq $registry.providers -or
        $registry.providers.PSObject.Properties.Name -notcontains $resolved) {
        return [pscustomobject]@{
            registered = $false
            provider_id = $resolved
            error_class = 'unknown_provider'
        }
    }

    $provider = $registry.providers.$resolved
    if (-not $provider.usage_today) {
        $provider | Add-Member -MemberType NoteProperty -Name usage_today -Value ([pscustomobject]@{}) -Force
    }
    $usage = $provider.usage_today
    foreach ($name in @(
        'calls', 'attempted_calls', 'successful_calls',
        'retryable_failures', 'failed_calls', 'estimated_cost_usd'
    )) {
        Add-VorceUsageProperty -Usage $usage -Name $name
    }

    $usage.calls = [int]$usage.calls + 1
    $usage.attempted_calls = [int]$usage.attempted_calls + 1
    switch ($Outcome) {
        'success' { $usage.successful_calls = [int]$usage.successful_calls + 1 }
        'retryable_failure' { $usage.retryable_failures = [int]$usage.retryable_failures + 1 }
        'failure' { $usage.failed_calls = [int]$usage.failed_calls + 1 }
    }
    $usage.estimated_cost_usd = [double]$usage.estimated_cost_usd + $Cost
    Add-VorceUsageProperty -Usage $usage -Name 'last_synced_at' -DefaultValue $null
    $usage.last_synced_at = (Get-Date).ToString('o')

    $saved = Save-VorceQuotaRegistry -Registry $registry
    return [pscustomobject]@{
        registered = $saved
        provider_id = $resolved
        model_tier = $ModelTier
        outcome = $Outcome
        error_class = if ($saved) { $null } else { 'artifact_missing' }
    }
}

function Get-VorceQuotaSummary {
    param([object]$Registry)

    if ($null -eq $Registry) {
        $Registry = Read-VorceQuotaRegistry
        if ($null -eq $Registry) { return 'Keine Quota Registry gefunden' }
    }

    $summary = @('=== QUOTA SUMMARY ===')
    foreach ($providerName in $Registry.providers.PSObject.Properties.Name) {
        $provider = $Registry.providers.$providerName
        $status = if ($provider.enabled) { 'ENABLED' } else { 'DISABLED' }
        $usage = $provider.usage_today
        $summary += "`n[$status] $providerName"
        $summary += "  Calls today: $(if ($usage.calls) { $usage.calls } else { 0 })"
        $summary += "  Attempted: $(if ($usage.attempted_calls) { $usage.attempted_calls } else { 0 })"
        $summary += "  Successful: $(if ($usage.successful_calls) { $usage.successful_calls } else { 0 })"
        $summary += "  Retryable failures: $(if ($usage.retryable_failures) { $usage.retryable_failures } else { 0 })"
        $summary += "  Est. cost: $([double]$usage.estimated_cost_usd)"
        $summary += "  Daily limit: $(if ($provider.daily_limit) { $provider.daily_limit } else { 0 })"
        $summary += "  Daily budget: $([double]$provider.daily_budget_usd)"
    }
    return ($summary -join "`n")
}
