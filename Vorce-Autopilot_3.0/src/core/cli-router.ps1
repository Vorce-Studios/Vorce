# Vorce-Autopilot/src/lib/cli-router.ps1
# Routes tasks to the best available CLI provider using fallback chain
# Parses real stats from CLI JSON output when available

Set-StrictMode -Version Latest

function Resolve-CliProvider {
    <#
    .SYNOPSIS
    Selects the best available CLI provider for a given task type.
    Returns provider name and model tier, or $null if all exhausted.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$TaskType,
        [string[]]$ExcludeProviders = @()
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

        if ($ExcludeProviders -contains $providerName) {
            Write-Host "[ROUTER] $providerName steht auf der Ausschlussliste, ueberspringe..." -ForegroundColor DarkGray
            continue
        }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $providerName) {
            $cmdName = $QuotaRegistry.providers.$providerName.command
            $resolvedCmd = Get-Command $cmdName -ErrorAction SilentlyContinue
            if ($resolvedCmd -and $resolvedCmd.CommandType -eq "ExternalScript" -and $resolvedCmd.Name -like "*.ps1") {
                $cmdNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($resolvedCmd.Name)
                $cmdDir = Split-Path $resolvedCmd.Source
                $cmdFile = Join-Path $cmdDir "$cmdNameWithoutExt.cmd"
                if (Test-Path $cmdFile) {
                    $cmdName = $cmdFile
                } else {
                    $cmdFile = Join-Path $cmdDir "$cmdNameWithoutExt.exe"
                    if (Test-Path $cmdFile) {
                        $cmdName = $cmdFile
                    }
                }
            }
            return [ordered]@{
                provider   = $providerName
                model_tier = $modelTier
                command    = $cmdName
            }
        }

        Write-Host "[ROUTER] $providerName nicht verfuegbar, versuche naechsten..." -ForegroundColor DarkGray
    }

    Write-Warning "[ROUTER] Alle Provider fuer '$TaskType' erschoepft!"
    return $null
}

function Build-CliArgs {
    <#
    .SYNOPSIS
    Builds the argument list for a CLI provider, substituting {PROMPT} and {MODEL}.
    #>
    param(
        [Parameter(Mandatory)][object]$ProviderConfig,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$ModelName
    )

    $hasCliArgs = $ProviderConfig.PSObject.Properties.Name -contains "cli_args"
    if (-not $hasCliArgs -or -not $ProviderConfig.cli_args) {
        # Fallback: generic invocation
        return @($Prompt)
    }

    $cliArgs = @()
    foreach ($arg in $ProviderConfig.cli_args) {
        $replaced = $arg -replace '\\{PROMPT\\}', $Prompt
        if ($ModelName) {
            $replaced = $replaced -replace '\\{MODEL\\}', $ModelName
        }
        $cliArgs += $replaced
    }
    return $cliArgs
}

function Parse-CliStats {
    <#
    .SYNOPSIS
    Parses real usage stats from CLI JSON output. Returns a hashtable with real cost/token data.
    #>
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$RawOutput
    )

    $stats = [ordered]@{
        real_cost_usd    = $null
        input_tokens     = $null
        output_tokens    = $null
        premium_requests = $null
        model_used       = $null
    }

    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return $stats }

    try {
        switch ($ProviderName) {
            "gemini_cli" {
                # Gemini outputs JSON with stats.models.{model}.tokens
                $json = $RawOutput | ConvertFrom-Json -ErrorAction Stop
                if ($json.stats -and $json.stats.models) {
                    $totalInput = 0
                    $totalOutput = 0
                    foreach ($modelProp in $json.stats.models.PSObject.Properties) {
                        $modelData = $modelProp.Value
                        $stats.model_used = $modelProp.Name
                        if ($modelData.tokens) {
                            $totalInput += [int]$modelData.tokens.input
                            $totalOutput += [int]$modelData.tokens.candidates
                        }
                    }
                    $stats.input_tokens = $totalInput
                    $stats.output_tokens = $totalOutput
                }
            }
            "claude_code" {
                # Claude outputs JSON with total_cost_usd and modelUsage
                $json = $RawOutput | ConvertFrom-Json -ErrorAction Stop
                if ($json.total_cost_usd) {
                    $stats.real_cost_usd = [double]$json.total_cost_usd
                }
                if ($json.modelUsage) {
                    $totalInput = 0
                    $totalOutput = 0
                    foreach ($modelProp in $json.modelUsage.PSObject.Properties) {
                        $modelData = $modelProp.Value
                        $stats.model_used = $modelProp.Name
                        if ($modelData.inputTokens) { $totalInput += [int]$modelData.inputTokens }
                        if ($modelData.outputTokens) { $totalOutput += [int]$modelData.outputTokens }
                    }
                    $stats.input_tokens = $totalInput
                    $stats.output_tokens = $totalOutput
                }
            }
            "copilot_cli" {
                # Copilot outputs JSONL; look for the "result" line
                $lines = $RawOutput -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '"type"\s*:\s*"result"') {
                        $json = $line | ConvertFrom-Json -ErrorAction Stop
                        if ($json.usage) {
                            $stats.premium_requests = [int]$json.usage.premiumRequests
                        }
                        break
                    }
                }
            }
            "cline_cli" {
                # Cline outputs JSONL; look for modelInfo
                $lines = $RawOutput -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '"modelInfo"' -and $line -match '"modelId"') {
                        try {
                            $json = $line | ConvertFrom-Json -ErrorAction Stop
                            if ($json.modelInfo -and $json.modelInfo.modelId) {
                                $stats.model_used = $json.modelInfo.modelId
                            }
                        } catch { }
                        break
                    }
                }
            }
        }
    } catch {
        # Stats parsing is best-effort, don't fail the task
    }

    return $stats
}

function Invoke-CliTask {
    <#
    .SYNOPSIS
    Executes a prompt via the selected CLI provider, tracks the call, and parses real stats.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [string]$MemoryBlock,
        [switch]$DryRun,
        [string]$ProviderOverride,
        [string]$ModelTierOverride
    )

    # Prepend memory block if provided
    if (-not [string]::IsNullOrWhiteSpace($MemoryBlock)) {
        $Prompt = $MemoryBlock + $Prompt
    }

    if ([string]::IsNullOrWhiteSpace($ProviderOverride)) {
        $route = Resolve-CliProvider -QuotaRegistry $QuotaRegistry -TaskType $TaskType
    } else {
        if (-not ($QuotaRegistry.providers.$ProviderOverride.PSObject.Properties.Name -contains "command")) {
            $cmdName = $null
        } else {
            $cmdName = $QuotaRegistry.providers.$ProviderOverride.command
            $resolvedCmd = Get-Command $cmdName -ErrorAction SilentlyContinue
            if ($resolvedCmd -and $resolvedCmd.CommandType -eq "ExternalScript" -and $resolvedCmd.Name -like "*.ps1") {
                $cmdNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($resolvedCmd.Name)
                $cmdDir = Split-Path $resolvedCmd.Source
                $cmdFile = Join-Path $cmdDir "$cmdNameWithoutExt.cmd"
                if (Test-Path $cmdFile) {
                    $cmdName = $cmdFile
                } elseif (Test-Path (Join-Path $cmdDir "$cmdNameWithoutExt.exe")) {
                    $cmdName = Join-Path $cmdDir "$cmdNameWithoutExt.exe"
                }
            }
        }
        $route = [ordered]@{
            provider   = $ProviderOverride
            model_tier = if ([string]::IsNullOrWhiteSpace($ModelTierOverride)) { "default" } else { $ModelTierOverride }
            command    = $cmdName
        }
    }

    if ($null -eq $route) {
        return [ordered]@{
            success  = $false
            provider = $null
            output   = "Kein Provider verfuegbar fuer '$TaskType'."
            error    = "ALL_PROVIDERS_EXHAUSTED"
            stats    = $null
        }
    }

    $providerName = $route.provider
    $modelTier = $route.model_tier
    $command = $route.command
    $providerConfig = $QuotaRegistry.providers.$providerName

    Write-Host "[ROUTER] Verwende $providerName ($modelTier) fuer '$TaskType'" -ForegroundColor Cyan

    if ($DryRun.IsPresent) {
        Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
        return [ordered]@{
            success  = $true
            provider = $providerName
            model    = $modelTier
            output   = "[DRY RUN] Wuerde ausfuehren: $command mit Prompt ($($Prompt.Length) chars)"
            error    = $null
            stats    = $null
        }
    }

    # Get model name for this tier
    $modelName = $null
    $hasModels = $providerConfig.PSObject.Properties.Name -contains "models"
    if ($hasModels -and $null -ne $providerConfig.models -and $providerConfig.models.PSObject.Properties.Name -contains $modelTier) {
        $modelName = $providerConfig.models.$modelTier.name
    }

    # Avoid Windows command-line length limits for providers that accept prompts via stdin.
    $usePromptStdin = $providerName -in @("gemini_cli", "claude_code")
    $promptForArgs = if ($usePromptStdin) { "" } else { $Prompt }
    $cliArgs = Build-CliArgs -ProviderConfig $providerConfig -Prompt $promptForArgs -ModelName $modelName

    $output = $null
    $exitCode = 0

    try {
        $pushDir = $null
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
            $pushDir = $WorkingDirectory
        }

        if ($pushDir) { Push-Location $pushDir }
        try {
            if ($usePromptStdin) {
                $output = $Prompt | & $command @cliArgs 2>&1 | Out-String
            } else {
                $output = & $command @cliArgs 2>&1 | Out-String
            }
        }
        finally {
            if ($pushDir) { Pop-Location }
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }

    # Parse real stats from output
    $parsedStats = Parse-CliStats -ProviderName $providerName -RawOutput $output

    # Register the call with real cost if available, otherwise use estimate
    if ($parsedStats.real_cost_usd) {
        # Use real cost
        $provider = $QuotaRegistry.providers.$providerName
        $provider.usage_today.calls = [int]$provider.usage_today.calls + 1
        $provider.usage_today.estimated_cost_usd = [Math]::Round([double]$provider.usage_today.estimated_cost_usd + [double]$parsedStats.real_cost_usd, 4)

        # Update token counters if available
        $hasInputTokens = $provider.usage_today.PSObject.Properties.Name -contains "total_input_tokens"
        if ($hasInputTokens -and $parsedStats.input_tokens) {
            $provider.usage_today.total_input_tokens = [int]$provider.usage_today.total_input_tokens + [int]$parsedStats.input_tokens
        }
        $hasOutputTokens = $provider.usage_today.PSObject.Properties.Name -contains "total_output_tokens"
        if ($hasOutputTokens -and $parsedStats.output_tokens) {
            $provider.usage_today.total_output_tokens = [int]$provider.usage_today.total_output_tokens + [int]$parsedStats.output_tokens
        }

        Save-QuotaRegistry -Registry $QuotaRegistry
        Write-Host ("[ROUTER] Echte Kosten: `${0}" -f [Math]::Round([double]$parsedStats.real_cost_usd, 4)) -ForegroundColor DarkGray
    } else {
        Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
    }

    return [ordered]@{
        success  = ($exitCode -eq 0)
        provider = $providerName
        model    = $modelTier
        output   = $output
        error    = if ($exitCode -ne 0) { "EXIT_CODE_$exitCode" } else { $null }
        stats    = $parsedStats
    }
}
