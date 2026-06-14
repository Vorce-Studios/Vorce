# Vorce-Autopilot/src/lib/quota-manager.ps1
# Verwaltung von API Quotas und Provider Routing

Set-StrictMode -Version Latest

function Get-QuotaRegistryPath {
    # Fester absoluter Pfad fuer V2
    return "C:\\Users\\Vinyl\\Desktop\\VJMapper\\VjMapper\\Vorce-Autopilot_2.0\\config\\quota-registry.json"
}

function Read-QuotaRegistry {
    $path = Get-QuotaRegistryPath
    Write-Host "[DEBUG] Read-QuotaRegistry lädt: $path" -ForegroundColor Yellow
    if (-not (Test-Path $path)) {
        throw "Quota-Registry nicht gefunden: $path"
    }

    try {
        $content = Get-Content $path -Raw -Encoding UTF8
        return ($content | ConvertFrom-Json)
    } catch {
        Write-Warning "Quota-Registry beschaedigt: $_"
        return $null
    }
}

function Save-QuotaRegistry {
    param([Parameter(Mandatory)][object]$Registry)
    $path = Get-QuotaRegistryPath

    # Reset exhausted providers on save
    $global:VorceAutopilotExhaustedProviders = @{}

    $json = $Registry | ConvertTo-Json -Depth 20 -Compress
    $json | Out-File -FilePath $path -Encoding UTF8 -Force
}

function Get-ProviderConfig {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName
    )

    if ($Registry.providers.PSObject.Properties.Name -contains $ProviderName) {
        return $Registry.providers.$ProviderName
    }
    return $null
}

function Test-ProviderAvailable {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName
    )

    if ($null -eq (Get-Variable -Name "VorceAutopilotExhaustedProviders" -Scope Global -ErrorAction SilentlyContinue)) {
        $global:VorceAutopilotExhaustedProviders = @{}
    }

    $provider = Get-ProviderConfig -Registry $Registry -ProviderName $ProviderName
    if ($null -eq $provider -or -not $provider.enabled) {
        return $false
    }

    # Check session-based exhaustion
    if ($global:VorceAutopilotExhaustedProviders.ContainsKey($ProviderName)) {
        return $false
    }

    # Check daily limit
    if ($provider.usage_today.calls -ge $provider.daily_limit) {
        Write-Host "[QUOTA] Provider $ProviderName hat Tageslimit erreicht ($($provider.daily_limit))." -ForegroundColor Yellow
        $global:VorceAutopilotExhaustedProviders[$ProviderName] = $true
        return $false
    }

    # Check daily budget
    if ($provider.PSObject.Properties.Name -contains "daily_budget_usd" -and $provider.daily_budget_usd -gt 0) {
        if ($provider.usage_today.estimated_cost_usd -ge $provider.daily_budget_usd) {
            Write-Host "[QUOTA] Provider $ProviderName hat Tagesbudget erreicht ($($provider.daily_budget_usd) USD)." -ForegroundColor Yellow
            $global:VorceAutopilotExhaustedProviders[$ProviderName] = $true
            return $false
        }
    }

    return $true
}

function Update-ProviderUsage {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [double]$Cost = 0
    )

    $provider = Get-ProviderConfig -Registry $Registry -ProviderName $ProviderName
    if ($null -ne $provider) {
        $provider.usage_today.calls++
        $provider.usage_today.estimated_cost_usd += $Cost
        $provider.usage_today | Add-Member -MemberType NoteProperty -Name "last_synced_at" -Value (Get-Date -Format 'o') -Force
        Save-QuotaRegistry -Registry $Registry
    }
}

function Get-QuotaSummary {
    param([Parameter(Mandatory)][object]$Registry)

    $summary = "[QUOTA] Status: "
    foreach ($pName in $Registry.providers.PSObject.Properties.Name) {
        $p = $Registry.providers.$pName
        if ($p.enabled) {
            $summary += "$($pName): $($p.usage_today.calls)/$($p.daily_limit) "
        }
    }
    return $summary
}

function Test-PrimaryProvidersAvailable {
    param([Parameter(Mandatory)][object]$Registry)

    $codexAvailable = Test-ProviderAvailable -Registry $Registry -ProviderName "codex_orchestrator"
    $geminiAvailable = Test-ProviderAvailable -Registry $Registry -ProviderName "gemini_cli"

    return $codexAvailable -or $geminiAvailable
}

function Register-ProviderCall {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$ModelTier = "default"
    )

    $provider = Get-ProviderConfig -Registry $Registry -ProviderName $ProviderName
    if ($null -ne $provider) {
        $provider.usage_today.calls++
        $provider.usage_today | Add-Member -MemberType NoteProperty -Name "last_synced_at" -Value (Get-Date -Format 'o') -Force
        Save-QuotaRegistry -Registry $Registry
    }
}

# Export-ModuleMember ist nur fuer .psm1 Module relevant.
# Export-ModuleMember -Function Read-QuotaRegistry, Save-QuotaRegistry, Get-ProviderConfig, Test-ProviderAvailable, Update-ProviderUsage, Get-QuotaSummary, Test-PrimaryProvidersAvailable, Register-ProviderCall
