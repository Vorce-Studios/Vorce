# scripts/codex-cli/lib/cli-router.ps1
# Routes tasks to the best available CLI provider using fallback chain

Set-StrictMode -Version Latest

function Resolve-CliProvider {
    <#
    .SYNOPSIS
    Selects the best available CLI provider for a given task type.
    Returns provider name and model tier, or $null if all exhausted.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$TaskType
    )

    $routes = $QuotaRegistry.routing_rules.$TaskType
    if (-not $routes) {
        Write-Warning "[ROUTER] Kein Routing fuer Task-Typ '$TaskType' definiert."
        return $null
    }

    foreach ($route in $routes) {
        $parts = $route -split ":"
        $providerName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $providerName) {
            return [ordered]@{
                provider   = $providerName
                model_tier = $modelTier
                command    = $QuotaRegistry.providers.$providerName.command
            }
        }

        Write-Host "[ROUTER] $providerName nicht verfuegbar, versuche naechsten..." -ForegroundColor DarkGray
    }

    Write-Warning "[ROUTER] Alle Provider fuer '$TaskType' erschoepft!"
    return $null
}

function Invoke-CliTask {
    <#
    .SYNOPSIS
    Executes a prompt via the selected CLI provider and tracks the call.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [switch]$DryRun
    )

    $route = Resolve-CliProvider -QuotaRegistry $QuotaRegistry -TaskType $TaskType
    if ($null -eq $route) {
        return [ordered]@{
            success  = $false
            provider = $null
            output   = "Kein Provider verfuegbar fuer '$TaskType'."
            error    = "ALL_PROVIDERS_EXHAUSTED"
        }
    }

    $provider = $route.provider
    $modelTier = $route.model_tier
    $command = $route.command

    Write-Host "[ROUTER] Verwende $provider ($modelTier) fuer '$TaskType'" -ForegroundColor Cyan

    if ($DryRun.IsPresent) {
        Register-ProviderCall -Registry $QuotaRegistry -ProviderName $provider -ModelTier $modelTier
        return [ordered]@{
            success  = $true
            provider = $provider
            model    = $modelTier
            output   = "[DRY RUN] Wuerde ausfuehren: $command mit Prompt ($(($Prompt).Length) chars)"
            error    = $null
        }
    }

    # Build command based on provider
    $output = $null
    $exitCode = 0

    try {
        $pushDir = $null
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
            $pushDir = $WorkingDirectory
        }

        $modelArg = $null
        $providerConfig = $QuotaRegistry.providers.$provider
        if ($providerConfig.models -and $providerConfig.models.$modelTier) {
            $modelArg = $providerConfig.models.$modelTier.name
        }

        $output = switch ($provider) {
            "gemini_cli" {
                $args = @("-p", $Prompt, "--approval-mode=yolo", "--sandbox", "false", "--output-format", "text")
                if ($modelArg -and $modelArg -ne "default") { $args += @("--model", $modelArg) }
                if ($pushDir) { Push-Location $pushDir }
                try { & $command @args 2>&1 | Out-String }
                finally { if ($pushDir) { Pop-Location } }
            }
            "claude_code" {
                $args = @("-p", $Prompt, "--dangerously-skip-permissions")
                if ($modelArg -and $modelArg -ne "default") { $args += @("--model", $modelArg) }
                if ($pushDir) { Push-Location $pushDir }
                try { & $command @args 2>&1 | Out-String }
                finally { if ($pushDir) { Pop-Location } }
            }
            "kiro_cli" {
                if ($pushDir) { Push-Location $pushDir }
                try { & $command $Prompt 2>&1 | Out-String }
                finally { if ($pushDir) { Pop-Location } }
            }
            "cline_cli" {
                $args = @("-p", $Prompt, "-y")
                if ($pushDir) { Push-Location $pushDir }
                try { & $command @args 2>&1 | Out-String }
                finally { if ($pushDir) { Pop-Location } }
            }
            "copilot_cli" {
                if ($pushDir) { Push-Location $pushDir }
                try { & $command $Prompt 2>&1 | Out-String }
                finally { if ($pushDir) { Pop-Location } }
            }
            default {
                "Unbekannter Provider: $provider"
            }
        }

        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }

    Register-ProviderCall -Registry $QuotaRegistry -ProviderName $provider -ModelTier $modelTier

    return [ordered]@{
        success  = ($exitCode -eq 0)
        provider = $provider
        model    = $modelTier
        output   = $output
        error    = if ($exitCode -ne 0) { "EXIT_CODE_$exitCode" } else { $null }
    }
}
