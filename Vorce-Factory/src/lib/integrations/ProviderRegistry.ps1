# ProviderRegistry.ps1
# Zentrale Provider-IDs und Legacy-Aliase.

function Get-VorceProviderIds {
    return @(
        'gemini_cli'
        'claude_code'
        'codex_orchestrator'
        'kiro_cli'
        'cline_cli'
        'copilot_cli'
        'cursor_agent'
        'jules'
    )
}

function Get-VorceProviderAliases {
    return [ordered]@{
        gemini = 'gemini_cli'
        claude = 'claude_code'
        codex = 'codex_orchestrator'
        codex_cli = 'codex_orchestrator'
        kiro = 'kiro_cli'
        cline = 'cline_cli'
        copilot = 'copilot_cli'
        cursor = 'cursor_agent'
        'cursor-agent' = 'cursor_agent'
        jules_cli = 'jules'
        jules_extern = 'jules'
    }
}

function Write-VorceProviderAliasWarning {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$ProviderId
    )

    if (-not $global:VorceProviderAliasWarnings) {
        $global:VorceProviderAliasWarnings =
            [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    if (-not $global:VorceProviderAliasWarnings.Add($Alias)) {
        return
    }

    $message = "Legacy-Provideralias '$Alias' wird als '$ProviderId' verwendet."
    if (Get-Command Write-VorceLogEntry -ErrorAction SilentlyContinue) {
        Write-VorceLogEntry `
            -Level 'WARN' `
            -Message $message `
            -Component 'ProviderRegistry' `
            -EventType 'provider_alias_normalized' `
            -Provider $ProviderId `
            -Data @{ alias = $Alias; provider_id = $ProviderId } | Out-Null
        return
    }

    Write-Warning $message
}

function Resolve-VorceProviderId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ProviderName)

    $normalized = $ProviderName.Trim().ToLowerInvariant()
    $canonicalIds = @(Get-VorceProviderIds)
    if ($canonicalIds -contains $normalized) {
        return $normalized
    }

    $aliases = Get-VorceProviderAliases
    if ($aliases.Contains($normalized)) {
        $providerId = [string]$aliases[$normalized]
        Write-VorceProviderAliasWarning -Alias $normalized -ProviderId $providerId
        return $providerId
    }

    return [pscustomobject]@{
        success = $false
        provider_id = $null
        requested_provider = $ProviderName
        normalized_provider = $normalized
        error_class = 'unknown_provider'
        retryable = $false
        fallback_recommended = $true
    }
}
