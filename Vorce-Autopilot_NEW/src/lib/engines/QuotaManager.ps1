# QuotaManager.ps1 (Vorce 3.0)
# Quota-Management für alle AI-Provider und CLI-Kommandos

function Read-VorceQuotaRegistry {
    # Liest aus: $global:VarDir/config/quota-registry.json
    param()

    $registryPath = Join-Path $global:VarDir "config/quota-registry.json"
    if (Test-Path $registryPath) {
        try {
            $content = Get-Content $registryPath -Raw
            if ([string]::IsNullOrWhiteSpace($content) -or $content -eq "null") {
                # Datei existiert aber enthält ungültige Daten
                return @{}
            }
            return $content | ConvertFrom-Json
        } catch {
            Write-Warning "Fehler beim Lesen der Quota Registry: $($_.Exception.Message)"
            return $null
        }
    } else {
        # Datei existiert nicht, leere Registry zurückgeben
        return @{}
    }
}

function Save-VorceQuotaRegistry {
    param(
        [Parameter(Mandatory)][object]$Registry
    )

    # Speichert nach: $global:VarDir/config/quota-registry.json
    $registryPath = Join-Path $global:VarDir "config/quota-registry.json"
    $registryDir = Split-Path $registryPath

    if (-not (Test-Path $registryDir)) {
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    }

    try {
        $Registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath -Encoding UTF8

        # Setzt $global:VorceExhaustedProviders zurück
        if (Test-Path "Variable:global:VorceExhaustedProviders") {
            $global:VorceExhaustedProviders = @{}
        }
    } catch {
        Write-Warning "Fehler beim Speichern der Quota Registry: $($_.Exception.Message)"
    }
}

function Test-VorceQuota {
    param(
        [string]$AgentName,
        [string]$ModelTier = "default"
    )

    # Prüft ob Provider enabled, nicht erschöpft, unter daily_limit, unter daily_budget_usd
    # Prüft ob CLI-Command verfügbar (Get-Command)

    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry) { return $false }

    $providers = $registry.providers
    if ($null -eq $providers -or $providers.PSObject.Properties.Name -notcontains $AgentName) {
        Write-Warning "Provider $AgentName nicht in Quota Registry gefunden"
        return $false
    }
    $providerConfig = $providers.$AgentName

    # Prüfe ob Provider enabled ist
    if ($providerConfig.enabled -ne $true) {
        return $false
    }

    # Prüfe CLI-Command Verfügbarkeit
    $commandName = $providerConfig.command
    if ($commandName) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            return $false
        }
    }

    # Prüfe Daily Limit
    if ($providerConfig.daily_limit -and $null -ne $providerConfig.usage_today.calls) {
        if ($providerConfig.usage_today.calls -ge $providerConfig.daily_limit) {
            return $false
        }
    }

    # Prüfe Daily Budget
    if ($providerConfig.daily_budget_usd -and $null -ne $providerConfig.usage_today.estimated_cost_usd) {
        if ($providerConfig.usage_today.estimated_cost_usd -ge $providerConfig.daily_budget_usd) {
            return $false
        }
    }

    return $true
}

function Register-VorceQuotaUsage {
    param(
        [string]$AgentName,
        [string]$ModelTier = "default",
        [double]$Cost = 0
    )

    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry) {
        $registry = @{}
    }

    if (-not $registry.providers) {
        $registry | Add-Member -MemberType NoteProperty -Name "providers" -Value ([pscustomobject]@{}) -Force
    }
    if ($registry.providers.PSObject.Properties.Name -notcontains $AgentName) {
        $registry.providers | Add-Member -MemberType NoteProperty -Name $AgentName -Value ([pscustomobject]@{
            model_tier = $ModelTier;
            enabled = $true;
            command = "";
            daily_limit = 0;
            daily_budget_usd = 0;
            usage_today = [pscustomobject]@{ calls = 0; estimated_cost_usd = 0; last_synced_at = (Get-Date).ToString("o") }
        }) -Force
    }
    $providerConfig = $registry.providers.$AgentName

    if (-not $providerConfig.usage_today) {
        $providerConfig | Add-Member -MemberType NoteProperty -Name "usage_today" -Value ([pscustomobject]@{ calls = 0; estimated_cost_usd = 0 }) -Force
    }
    $providerConfig.usage_today.calls = [int]$providerConfig.usage_today.calls + 1

    $providerConfig.usage_today.estimated_cost_usd = [double]$providerConfig.usage_today.estimated_cost_usd + $Cost
    $providerConfig.usage_today.last_synced_at = (Get-Date).ToString("o")

    # Speichere Registry
    Save-VorceQuotaRegistry -Registry $registry
}

function Get-VorceQuotaSummary {
    param(
        [object]$Registry
    )

    # Gibt Zusammenfassung aller Provider als String zurück

    if ($null -eq $Registry) {
        $Registry = Read-VorceQuotaRegistry
        if ($null -eq $Registry) { return "Keine Quota Registry gefunden" }
    }

    $summary = @()
    $summary += "=== QUOTA SUMMARY ==="

    foreach ($providerName in $Registry.providers.PSObject.Properties.Name) {
        $provider = $Registry.providers.$providerName
        $status = if ($provider.enabled) { "ENABLED" } else { "DISABLED" }

        $summary += "`n[$status] $providerName"
        $summary += "  Calls today: $($provider.usage_today.calls ?? 0)"
        $summary += "  Est. cost: $([double]$provider.usage_today.estimated_cost_usd)"
        $summary += "  Daily limit: $($provider.daily_limit ?? 0)"
        $summary += "  Daily budget: $([double]$provider.daily_budget_usd)"
    }

    return ($summary -join "`n")
}

# QuotaManager
