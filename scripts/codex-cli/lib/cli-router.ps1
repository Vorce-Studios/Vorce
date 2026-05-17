# scripts/codex-cli/lib/cli-router.ps1
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

function Build-CliArgs {
    <#
    .SYNOPSIS
    Builds the argument list for a CLI provider, substituting {PROMPT} and {MODEL}.
    #>
    param(
        [Parameter(Mandatory)][object]$ProviderConfig,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelName
    )

    $hasCliArgs = $ProviderConfig.PSObject.Properties.Name -contains "cli_args"
    if (-not $hasCliArgs -or -not $ProviderConfig.cli_args) {
        # Fallback: generic -p invocation
        return @("-p", $Prompt)
    }

    $args = @()
    foreach ($arg in $ProviderConfig.cli_args) {
        $replaced = $arg -replace '\{PROMPT\}', $Prompt
        if ($ModelName) {
            $replaced = $replaced -replace '\{MODEL\}', $ModelName
        }
        $args += $replaced
    }
    return $args
}

function Parse-CliStats {
    <#
    .SYNOPSIS
    Parses real usage stats from CLI JSON output or Telemetry JSONL.
    #>
    param(
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$RawOutput,
        [string]$TelemetryFile
    )

    $stats = [ordered]@{
        real_cost_usd    = $null
        input_tokens     = $null
        output_tokens    = $null
        cached_tokens    = $null
        reasoning_tokens = $null
        tool_tokens      = $null
        total_duration_ms= $null
        premium_requests = $null
        model_used       = $null
    }

    if ([string]::IsNullOrWhiteSpace($RawOutput) -and (-not $TelemetryFile -or -not (Test-Path $TelemetryFile))) { return $stats }

    $json = $null
    try {
        $firstBrace = $RawOutput.IndexOf('{')
        $lastBrace = $RawOutput.LastIndexOf('}')
        if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
            $jsonStr = $RawOutput.Substring($firstBrace, $lastBrace - $firstBrace + 1)
            $json = $jsonStr | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
    } catch { }

    try {
        switch ($ProviderName) {
            "gemini_cli" {
                # First, parse standard stdout for model name and basic stats if no telemetry
                if ($json -and $json.stats -and $json.stats.models) {
                    $totalInput = 0; $totalOutput = 0;
                    foreach ($modelProp in $json.stats.models.PSObject.Properties) {
                        $stats.model_used = $modelProp.Name
                        if ($modelProp.Value.tokens) {
                            $totalInput += [int]$modelProp.Value.tokens.input
                            $totalOutput += [int]$modelProp.Value.tokens.candidates
                        }
                    }
                    $stats.input_tokens = $totalInput
                    $stats.output_tokens = $totalOutput
                }

                # Overwrite with precise OpenTelemetry data if available
                if ($TelemetryFile -and (Test-Path $TelemetryFile)) {
                    $lines = Get-Content $TelemetryFile -ReadCount 0
                    # Read backwards to find the latest api_response
                    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                        if ($lines[$i] -match "gemini_cli.api_response") {
                            $otlp = $lines[$i] | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($otlp -and $otlp.attributes) {
                                $attr = $otlp.attributes
                                if ($attr.model) { $stats.model_used = $attr.model }
                                if ($attr.input_token_count) { $stats.input_tokens = [int]$attr.input_token_count }
                                if ($attr.output_token_count) { $stats.output_tokens = [int]$attr.output_token_count }
                                if ($attr.cached_content_token_count) { $stats.cached_tokens = [int]$attr.cached_content_token_count }
                                if ($attr.thoughts_token_count) { $stats.reasoning_tokens = [int]$attr.thoughts_token_count }
                                if ($attr.tool_token_count) { $stats.tool_tokens = [int]$attr.tool_token_count }
                                if ($attr.duration_ms) { $stats.total_duration_ms = [int]$attr.duration_ms }
                            }
                            break
                        }
                    }
                    # Clean up telemetry file so it doesn't grow indefinitely
                    Remove-Item $TelemetryFile -Force -ErrorAction SilentlyContinue
                }
            }
            "claude_code" {
                if ($json) {
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
            }
            "copilot_cli" {
                # Copilot outputs JSONL; look for the "result" line
                $lines = $RawOutput -split "`n"
                foreach ($line in $lines) {
                    if ($line -match '"type"\s*:\s*"result"') {
                        $cJson = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($cJson.usage) {
                            $stats.premium_requests = [int]$cJson.usage.premiumRequests
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
                            $cJson = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($cJson.modelInfo -and $cJson.modelInfo.modelId) {
                                $stats.model_used = $cJson.modelInfo.modelId
                            }
                        } catch { }
                        break
                    }
                }
            }
        }
    } catch {
        # Stats parsing is best-effort, don't fail the task
        Write-Host "[DEBUG] Exception during stats parsing: $($_.Exception.Message)" -ForegroundColor Red
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
        [switch]$DryRun
    )

    $route = Resolve-CliProvider -QuotaRegistry $QuotaRegistry -TaskType $TaskType
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
    $hasModels = Test-ObjectProperty -Object $providerConfig -Name "models"
    if ($hasModels -and $providerConfig.models -and $providerConfig.models.$modelTier) {
        $modelName = $providerConfig.models.$modelTier.name
    }

    # Build args
    $cliArgs = Build-CliArgs -ProviderConfig $providerConfig -Prompt $Prompt -ModelName $modelName

    # Add model arg for providers that support it
    if ($modelName -and $modelName -ne "default") {
        switch ($providerName) {
            "gemini_cli" {
                $cliArgs += @("--model", $modelName)
            }
            "claude_code" {
                $cliArgs += @("--model", $modelName)
            }
        }
    }

    $output = $null
    $exitCode = 0
    $telemetryFile = $null

    try {
        $pushDir = $null
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
            $pushDir = $WorkingDirectory
        }

        if ($providerName -eq "gemini_cli") {
            $env:GEMINI_TELEMETRY_ENABLED = "true"
            $env:GEMINI_TELEMETRY_TARGET = "local"
            $telemetryFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\tmp\gemini-telemetry.jsonl"))
            $env:GEMINI_TELEMETRY_OUTFILE = $telemetryFile
            if (-not (Test-Path (Split-Path $telemetryFile))) {
                New-Item -ItemType Directory -Path (Split-Path $telemetryFile) -Force | Out-Null
            }
        }

        if ($pushDir) { Push-Location $pushDir }
        try {
            $output = & $command @cliArgs 2>&1 | Out-String
        }
        finally {
            if ($pushDir) { Pop-Location }
        }
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    } finally {
        if ($providerName -eq "gemini_cli") {
            # Unset env vars
            Remove-Item Env:\GEMINI_TELEMETRY_ENABLED -ErrorAction SilentlyContinue
            Remove-Item Env:\GEMINI_TELEMETRY_TARGET -ErrorAction SilentlyContinue
            Remove-Item Env:\GEMINI_TELEMETRY_OUTFILE -ErrorAction SilentlyContinue
        }
    }

    # Parse real stats from output
    $parsedStats = Parse-CliStats -ProviderName $providerName -RawOutput $output -TelemetryFile $telemetryFile

    $provider = $QuotaRegistry.providers.$providerName
    Ensure-ProviderUsageToday -Provider $provider
    $estimatedCost = Get-EstimatedCost -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier

    # Register the call with real cost if available, otherwise use estimate
    if ($parsedStats.real_cost_usd -or $parsedStats.input_tokens) {
        $modelUsedKey = "unknown"
        if ($parsedStats.model_used) { $modelUsedKey = $parsedStats.model_used }
        elseif ($modelName) { $modelUsedKey = $modelName }

        $modUsage = Ensure-ModelUsageBucket -Provider $provider -ModelName $modelUsedKey
        $modUsage.calls = [int]$modUsage.calls + 1

        $provider.usage_today.calls = [int]$provider.usage_today.calls + 1

        $costToAdd = $estimatedCost
        if ($parsedStats.real_cost_usd) {
            $costToAdd = [double]$parsedStats.real_cost_usd
        }
        $modUsage.estimated_cost_usd = [Math]::Round([double]$modUsage.estimated_cost_usd + $costToAdd, 4)
        $provider.usage_today.estimated_cost_usd = [Math]::Round([double]$provider.usage_today.estimated_cost_usd + $costToAdd, 4)

        if ($parsedStats.input_tokens) { $modUsage.total_input_tokens = [int]$modUsage.total_input_tokens + [int]$parsedStats.input_tokens }
        if ($parsedStats.output_tokens) { $modUsage.total_output_tokens = [int]$modUsage.total_output_tokens + [int]$parsedStats.output_tokens }
        if ($parsedStats.cached_tokens) { $modUsage.cached_tokens = [int]$modUsage.cached_tokens + [int]$parsedStats.cached_tokens }
        if ($parsedStats.reasoning_tokens) { $modUsage.reasoning_tokens = [int]$modUsage.reasoning_tokens + [int]$parsedStats.reasoning_tokens }
        if ($parsedStats.tool_tokens) { $modUsage.tool_tokens = [int]$modUsage.tool_tokens + [int]$parsedStats.tool_tokens }
        if ($parsedStats.total_duration_ms) { $modUsage.total_duration_ms = [int]$modUsage.total_duration_ms + [int]$parsedStats.total_duration_ms }
        Save-QuotaRegistry -Registry $QuotaRegistry
        Write-Host ("[ROUTER] Stats verarbeitet fuer Modell: $modelUsedKey") -ForegroundColor DarkGray
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
