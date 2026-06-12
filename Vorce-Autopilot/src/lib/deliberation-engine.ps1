# Vorce-Autopilot/src/lib/deliberation-engine.ps1
# Dual-CEO Deliberation Engine
# Orchestrates structured dialogue between two AI agents (Alpha + Beta)
# for higher-quality decisions on critical tasks.

Set-StrictMode -Version Latest

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:DelibLogDir = Join-Path $script:ScriptRoot "var/log/deliberations"

# Ensure var/log/deliberations exists
if (-not (Test-Path -Path $script:DelibLogDir)) {
    New-Item -ItemType Directory -Path $script:DelibLogDir -Force | Out-Null
}

function Resolve-DualCeos {
    <#
    .SYNOPSIS
    Resolves two CEO providers from their respective fallback chains.
    Returns hashtable with alpha/beta provider info, or $null for unavailable CEOs.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config
    )

    $dualCfg = $Config.dual_ceo

    # --- Resolve CEO ---
    $alpha = $null
    foreach ($route in $dualCfg.ceo_alpha_chain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            $alpha = [ordered]@{
                provider   = $provName
                model_tier = $modelTier
                command    = $cmdName
                label      = "CEO"
            }
            break
        }
        Write-Host "[DELIB] Alpha-Kandidat '$provName' nicht verfuegbar, naechster..." -ForegroundColor DarkGray
    }

    # --- Resolve QA Manager ---
    $beta = $null
    foreach ($route in $dualCfg.ceo_beta_chain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        # Beta must be different from Alpha
        if ($alpha -and $provName -eq $alpha.provider) {
            Write-Host "[DELIB] Beta-Kandidat '$provName' identisch mit Alpha, ueberspringe." -ForegroundColor DarkGray
            continue
        }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            $beta = [ordered]@{
                provider   = $provName
                model_tier = $modelTier
                command    = $cmdName
                label      = "QA Manager"
            }
            break
        }
        Write-Host "[DELIB] Beta-Kandidat '$provName' nicht verfuegbar, naechster..." -ForegroundColor DarkGray
    }

    return [ordered]@{
        alpha = $alpha
        beta  = $beta
    }
}

function Format-DeliberationPrompt {
    <#
    .SYNOPSIS
    Builds phase-specific prompts for the deliberation dialogue from Markdown files.
    Optionally prepends a memory block for context.
    #>
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$OriginalPrompt,
        [string]$AlphaProposal,
        [string]$BetaCritique,
        [string]$MemoryBlock
    )

    # Prepend memory block to original prompt if provided
    $contextPrompt = if (-not [string]::IsNullOrWhiteSpace($MemoryBlock)) {
        $MemoryBlock + $OriginalPrompt
    } else {
        $OriginalPrompt
    }

    $vars = @{ contextPrompt = $contextPrompt }
    if ($null -ne $AlphaProposal) {
        $vars["AlphaProposal"] = $AlphaProposal
    }
    if ($null -ne $BetaCritique) {
        $vars["BetaCritique"] = $BetaCritique
    }

    # Load prompt template dynamically from Markdown files
    return Get-VorceConfigPrompt -Config $null -PromptKey $Phase -Variables $vars
}

function Get-CleanCeoOutput {
    param(
        [string]$RawOutput,
        [string]$ProviderName
    )

    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return "" }

    # Try to extract a JSON object from the raw output
    $jsonMatch = [regex]::Match($RawOutput, '(?s)\{.*\}')
    if ($jsonMatch.Success) {
        try {
            $parsed = $jsonMatch.Value | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $parsed) {
                # If it's a wrapper JSON from the CLI router/provider
                if ($parsed.PSObject.Properties.Name -contains "response") {
                    return $parsed.response
                }
                if ($parsed.PSObject.Properties.Name -contains "output") {
                    return $parsed.output
                }
                return $jsonMatch.Value
            }
        } catch {}
    }

    # Clean up warnings and non-content lines
    $lines = $RawOutput -split "`r?`n" | Where-Object {
        $_ -notmatch '^Warning: 256-color' -and
        $_ -notmatch '^YOLO mode is enabled' -and
        $_ -notmatch '^Ripgrep is not available' -and
        $_ -notmatch '^\[CEO\]' -and
        $_ -notmatch '^======================'
    }
    return ($lines -join "`n").Trim()
}

function Format-CeoChatOutput {
    param(
        [string]$Role,
        [string]$AgentName,
        [string]$Content
    )

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host "  CEO CHAT - $Role ($AgentName)" -ForegroundColor Magenta
    Write-Host ("=" * 60) -ForegroundColor Magenta

    # Try to parse content as JSON
    $jsonMatch = [regex]::Match($Content, '(?s)\{.*\}')
    $parsed = $null
    if ($jsonMatch.Success) {
        try { $parsed = $jsonMatch.Value | ConvertFrom-Json -ErrorAction Stop } catch {}
    }

    if ($null -ne $parsed) {
        $props = $parsed.PSObject.Properties
        foreach ($prop in $props) {
            $name = $prop.Name
            $val = $prop.Value

            # Format property name cleanly (capitalize each word)
            $displayName = @($name -split '_' | ForEach-Object {
                if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { "" }
            }) -join " "

            if ($val -is [System.Array] -or $val -is [System.Collections.IList]) {
                Write-Host "  $displayName`:" -ForegroundColor Cyan
                foreach ($item in $val) {
                    if ($null -ne $item -and $item.PSObject -and $item.PSObject.Properties) {
                        # Format PSCustomObject properties cleanly
                        $itemProps = @()
                        foreach ($prop in $item.PSObject.Properties) {
                            if ($prop.Name -ne "labels") {
                                $itemProps += "$($prop.Name): $($prop.Value)"
                            }
                        }
                        $itemLine = $itemProps -join " | "
                        Write-Host "    - $itemLine" -ForegroundColor Gray
                    } else {
                        Write-Host "    - $item" -ForegroundColor Gray
                    }
                }
            } else {
                if ($null -ne $val -and $val.ToString().Contains("`n")) {
                    Write-Host "  $displayName`:" -ForegroundColor Cyan
                    $val.ToString() -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
                } else {
                    Write-Host "  $displayName`: $val" -ForegroundColor Gray
                }
            }
        }
    } else {
        $Content -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host ""
}

function Invoke-VisibleCeoPhase {
    <#
    .SYNOPSIS
    Runs a single CEO deliberation phase in a visible terminal window.
    Supports robust cleanup of temp files in var/db using try/finally block.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$CeoInfo,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$PhaseName,
        [string]$WorkingDirectory,
        [object]$State,
        [switch]$DryRun
    )

    $providerName = $CeoInfo.provider
    $modelTier = $CeoInfo.model_tier
    $providerConfig = $QuotaRegistry.providers.$providerName

    if ($DryRun.IsPresent) {
        return [ordered]@{
            success = $true
            output  = "[DRY RUN] Wuerde $PhaseName ausfuehren mit $providerName ($modelTier)"
            stats   = $null
        }
    }

    # Resolve model name
    $modelName = $null
    $hasModels = $providerConfig.PSObject.Properties.Name -contains "models"
    if ($hasModels -and $providerConfig.models -and $providerConfig.models.$modelTier) {
        $modelName = $providerConfig.models.$modelTier.name
    }

    # --- Codex provider: Use the original visible session manager ---
    if ($providerName -eq "codex_orchestrator") {
        $codexModel = if ($modelName) { $modelName } else { "gpt-5.4-mini" }
        Write-Host "[DELIB] Starte sichtbare Codex-Session: $PhaseName (Model: $codexModel)" -ForegroundColor Cyan

        $result = Invoke-AutopilotCodexSession `
            -SessionType "deliberation-$PhaseName" `
            -Prompt $Prompt `
            -State $State `
            -Model $codexModel `
            -VisibleExecTerminal `
            -DryRun:$DryRun

        if (-not $DryRun.IsPresent) {
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
        }

        $finalOutput = ""
        $isSuccess = [bool]((Test-ObjectProperty -Object $result -Name "Success") -and $result.Success)
        if ($isSuccess) {
            if ((Test-ObjectProperty -Object $result -Name "OutputPath") -and $result.OutputPath -and (Test-Path -LiteralPath $result.OutputPath)) {
                $finalOutput = Get-Content -LiteralPath $result.OutputPath -Raw -Encoding UTF8
            } else {
                $finalOutput = if (Test-ObjectProperty -Object $result -Name "Output") { $result.Output } else { "" }
            }
        } else {
            $finalOutput = if (Test-ObjectProperty -Object $result -Name "Output") { [string]$result.Output } else { "" }
            if ($finalOutput -match "(?i)(usage limit|quota|limit reached)") {
                if (Get-Command Set-ProviderExhausted -ErrorAction SilentlyContinue) {
                    Set-ProviderExhausted -ProviderName $providerName
                }
            }
        }

        return [ordered]@{
            success = $isSuccess
            output  = $finalOutput
            stats   = $null
        }
    }

    # --- All other providers (Gemini, Claude, Kiro, etc.): Open visible terminal ---
    $tmpDir = Join-Path $script:ScriptRoot "var/db"
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $timestamp = Get-Date -Format "HHmmss"
    $cleanPhase = $PhaseName -replace '[^a-zA-Z0-9_-]', ''
    $argsFile = Join-Path $tmpDir "ceo-args-$cleanPhase-$timestamp.json"
    $outputFile = Join-Path $tmpDir "ceo-output-$cleanPhase-$timestamp.txt"
    $statusFile = Join-Path $tmpDir "ceo-status-$cleanPhase-$timestamp.txt"
    $promptFile = Join-Path $tmpDir "ceo-prompt-$cleanPhase-$timestamp.txt"

    try {
        # Write prompt to file for stdin piping
        Set-Content -Path $promptFile -Value $Prompt -Encoding UTF8

        # Build CLI args
        $cliArgs = @()
        $skipNext = $false
        foreach ($arg in $providerConfig.cli_args) {
            if ($skipNext) { $skipNext = $false; continue }
            if ($arg -eq "-p" -or $arg -eq "--prompt" -or $arg -eq "{PROMPT}") {
                if ($arg -eq "-p" -or $arg -eq "--prompt") { $skipNext = $true }
                continue
            }
            $replaced = $arg
            if ($modelName) {
                $replaced = $replaced -replace '\{MODEL\}', $modelName
            }
            $cliArgs += $replaced
        }

        if ($modelName -and $modelName -ne "default") {
            switch ($providerName) {
                "gemini_cli"  { $cliArgs += @("--model", $modelName) }
                "claude_code" { $cliArgs += @("--model", $modelName) }
            }
        }

        # Serialize args to file
        $cliArgs | ConvertTo-Json -Depth 5 | Set-Content -Path $argsFile -Encoding UTF8

        # Determine working directory
        $workDir = if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
            $WorkingDirectory
        } else {
            Split-Path -Parent $script:ScriptRoot
        }

        $runnerScript = Join-Path $script:ScriptRoot "tools\run-visible-ceo-phase.ps1"
        $powerShellHost = (Get-Command pwsh -ErrorAction SilentlyContinue)
        if ($powerShellHost) { $powerShellHost = $powerShellHost.Source } else { $powerShellHost = (Get-Command powershell -ErrorAction Stop).Source }

        $runnerArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $runnerScript,
            "-CliCommand", $CeoInfo.command,
            "-CliArgsFile", $argsFile,
            "-OutputFile", $outputFile,
            "-StatusFile", $statusFile,
            "-PromptFile", $promptFile,
            "-PhaseName", "$($CeoInfo.label): $PhaseName",
            "-ProviderName", $providerName,
            "-ModelName", $(if ($modelName) { $modelName } else { "default" }),
            "-WorkingDirectory", $workDir
        )

        Write-Host "[DELIB] Oeffne sichtbares Terminal: $($CeoInfo.label) - $PhaseName ($providerName)" -ForegroundColor Cyan

        $process = Start-Process -FilePath $powerShellHost -ArgumentList $runnerArgs -WindowStyle Normal -PassThru
        Write-Host "[DELIB] PID=$($process.Id) - Warte auf Abschluss..." -ForegroundColor DarkGray

        $process.WaitForExit()
        $exitCode = $process.ExitCode

        # Read output
        $output = ""
        if (Test-Path -LiteralPath $outputFile) {
            $output = Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8
        }

        # Parse stats
        $parsedStats = Parse-CliStats -ProviderName $providerName -RawOutput $output
        if (-not $DryRun.IsPresent) {
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
        }

        Write-Host "[DELIB] $PhaseName abgeschlossen. Exit=$exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
        if ($exitCode -ne 0) {
            Write-Warning "[DELIB] Phase '$PhaseName' fehlgeschlagen mit Exit-Code $exitCode. Output/Fehlerdetails:"
            Write-Host $output -ForegroundColor Red
        }

        return [ordered]@{
            success = ($exitCode -eq 0)
            output  = $output
            stats   = $parsedStats
        }
    } finally {
        # ABSOLUT sicheres Cleanup verzoegerter/intermediärer Dateien
        Remove-Item -Path $argsFile, $outputFile, $statusFile, $promptFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Deliberation {
    <#
    .SYNOPSIS
    Orchestrates a structured 3-phase deliberation between two CEO agents.
    Each phase opens a VISIBLE terminal window so the user can observe the CEOs.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [string]$MemoryBlock,
        [switch]$DryRun,
        [object]$State
    )

    $deliberationId = "delib-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"

    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] ====== Dual-CEO Deliberation: $deliberationId ======" -ForegroundColor Magenta
    Write-Host "[DELIB] Task-Typ: $TaskType" -ForegroundColor Magenta
    Write-Host "[DELIB] Jede Phase oeffnet ein sichtbares Terminal-Fenster." -ForegroundColor Magenta

    # --- Resolve both CEOs ---
    $ceos = Resolve-DualCeos -QuotaRegistry $QuotaRegistry -Config $Config

    # --- Fallback to single agent if needed ---
    if ($null -eq $ceos.alpha -and $null -eq $ceos.beta) {
        Write-Host "[DELIB] Kein CEO verfuegbar! Fallback auf Standard-Router." -ForegroundColor Red
        return Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType $TaskType -Prompt $Prompt -WorkingDirectory $WorkingDirectory -MemoryBlock $MemoryBlock -DryRun:$DryRun
    }

    if ($null -eq $ceos.alpha -or $null -eq $ceos.beta) {
        $available = if ($ceos.alpha) { $ceos.alpha } else { $ceos.beta }
        Write-Host "[DELIB] Nur ein CEO verfuegbar ($($available.provider)). Single-Agent-Modus (Visible)." -ForegroundColor Yellow

        $singleResult = Invoke-VisibleCeoPhase `
            -QuotaRegistry $QuotaRegistry `
            -CeoInfo $available `
            -Prompt $Prompt `
            -PhaseName "Single-Agent" `
            -WorkingDirectory $WorkingDirectory `
            -State $State `
            -DryRun:$DryRun

        return [pscustomobject]@{
            success = $singleResult.success
            output  = Get-CleanCeoOutput -RawOutput $singleResult.output -ProviderName $available.provider
        }
    }

    Write-Host "[DELIB] Alpha: $($ceos.alpha.provider) ($($ceos.alpha.model_tier))" -ForegroundColor Cyan
    Write-Host "[DELIB] Beta:  $($ceos.beta.provider) ($($ceos.beta.model_tier))" -ForegroundColor Cyan

    $protocol = [ordered]@{
        deliberation_id   = $deliberationId
        task_type         = $TaskType
        started_at        = (Get-Date -Format 'o')
        alpha             = [ordered]@{ provider = $ceos.alpha.provider; model_tier = $ceos.alpha.model_tier }
        beta              = [ordered]@{ provider = $ceos.beta.provider; model_tier = $ceos.beta.model_tier }
        rounds            = @()
        consensus_reached = $false
        final_output      = $null
        completed_at      = $null
    }

    # ==========================================
    # PHASE 1: PROPOSAL (CEO) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 1: Proposal (Alpha: $($ceos.alpha.provider)) ---" -ForegroundColor Yellow

    $proposalPrompt = Format-DeliberationPrompt -Phase "proposal" -OriginalPrompt $Prompt -MemoryBlock $MemoryBlock
    $proposalStart = Get-Date

    $proposalResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.alpha `
        -Prompt $proposalPrompt `
        -PhaseName "Proposal" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $proposalDuration = ((Get-Date) - $proposalStart).TotalMilliseconds
    $alphaProposal = Get-CleanCeoOutput -RawOutput $proposalResult.output -ProviderName $ceos.alpha.provider

    $protocol.rounds += @([ordered]@{
        phase       = "proposal"
        agent       = "alpha"
        provider    = $ceos.alpha.provider
        duration_ms = [int]$proposalDuration
        success     = $proposalResult.success
        content     = $alphaProposal
    })

    if (-not $proposalResult.success) {
        Write-Host "[DELIB] CEO-Proposal (Alpha) fehlgeschlagen! Versuche Fallback-Proposal durch QA-Manager (Beta)..." -ForegroundColor Yellow
        $fallbackStart = Get-Date
        $fallbackResult = Invoke-VisibleCeoPhase `
            -QuotaRegistry $QuotaRegistry `
            -CeoInfo $ceos.beta `
            -Prompt $proposalPrompt `
            -PhaseName "Proposal (Fallback)" `
            -WorkingDirectory $WorkingDirectory `
            -State $State `
            -DryRun:$DryRun

        $fallbackDuration = ((Get-Date) - $fallbackStart).TotalMilliseconds
        $betaProposal = Get-CleanCeoOutput -RawOutput $fallbackResult.output -ProviderName $ceos.beta.provider

        $protocol.rounds += @([ordered]@{
            phase       = "proposal_fallback"
            agent       = "beta"
            provider    = $ceos.beta.provider
            duration_ms = [int]$fallbackDuration
            success     = $fallbackResult.success
            content     = $betaProposal
        })

        if (-not $fallbackResult.success) {
            Write-Host "[DELIB] CEO-Proposal Fallback fehlgeschlagen! Breche Deliberation ab." -ForegroundColor Red
            $protocol.final_output = "Alpha and Beta failed. Deliberation aborted."
            $protocol.consensus_reached = $false

            $protocol.completed_at = (Get-Date -Format 'o')
            Save-DeliberationProtocol -Protocol $protocol -Config $Config

            return [ordered]@{
                success        = $false
                provider       = $ceos.alpha.provider
                model          = $ceos.alpha.model_tier
                output         = $alphaProposal
                error          = "PROPOSAL_FAILED"
                stats          = $proposalResult.stats
                deliberation   = $protocol
            }
        }

        Write-Host "[DELIB] CEO-Proposal Fallback (Beta) erfolgreich." -ForegroundColor Green
        Format-CeoChatOutput -Role "Proposal (Fallback)" -AgentName $ceos.beta.provider -Content $betaProposal

        $protocol.final_output = $betaProposal
        $protocol.consensus_reached = $false
        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [ordered]@{
            success        = $true
            provider       = $ceos.beta.provider
            model          = $ceos.beta.model_tier
            output         = $betaProposal
            error          = $null
            stats          = $fallbackResult.stats
            deliberation   = $protocol
        }
    }

    Write-Host "[DELIB] CEO-Proposal erhalten ($([int]$proposalDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Proposal" -AgentName $ceos.alpha.provider -Content $alphaProposal

    # ==========================================
    # PHASE 2: CRITIQUE (QA Manager) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 2: Critique (Beta: $($ceos.beta.provider)) ---" -ForegroundColor Yellow

    $critiquePrompt = Format-DeliberationPrompt -Phase "critique" -OriginalPrompt $Prompt -AlphaProposal $alphaProposal -MemoryBlock $MemoryBlock
    $critiqueStart = Get-Date

    $critiqueResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.beta `
        -Prompt $critiquePrompt `
        -PhaseName "Critique" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $critiqueDuration = ((Get-Date) - $critiqueStart).TotalMilliseconds
    $betaCritique = Get-CleanCeoOutput -RawOutput $critiqueResult.output -ProviderName $ceos.beta.provider

    $protocol.rounds += @([ordered]@{
        phase       = "critique"
        agent       = "beta"
        provider    = $ceos.beta.provider
        duration_ms = [int]$critiqueDuration
        success     = $critiqueResult.success
        content     = $betaCritique
    })

    if (-not $critiqueResult.success) {
        Write-Host "[DELIB] QA-Critique fehlgeschlagen! Verwende CEO-Proposal als Endergebnis." -ForegroundColor Yellow
        $protocol.final_output = $alphaProposal
        $protocol.consensus_reached = $false
        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [ordered]@{
            success        = $true
            provider       = $ceos.alpha.provider
            model          = $ceos.alpha.model_tier
            output         = $alphaProposal
            error          = $null
            stats          = $proposalResult.stats
            deliberation   = $protocol
        }
    }

    Write-Host "[DELIB] QA-Critique erhalten ($([int]$critiqueDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Critique" -AgentName $ceos.beta.provider -Content $betaCritique

    # ==========================================
    # PHASE 3: SYNTHESIS (CEO) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 3: Synthesis (Alpha: $($ceos.alpha.provider)) ---" -ForegroundColor Yellow

    $synthesisPrompt = Format-DeliberationPrompt -Phase "synthesis" -OriginalPrompt $Prompt -AlphaProposal $alphaProposal -BetaCritique $betaCritique -MemoryBlock $MemoryBlock
    $synthesisStart = Get-Date

    $synthesisResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.alpha `
        -Prompt $synthesisPrompt `
        -PhaseName "Synthesis" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $synthesisDuration = ((Get-Date) - $synthesisStart).TotalMilliseconds
    $alphaSynthesis = Get-CleanCeoOutput -RawOutput $synthesisResult.output -ProviderName $ceos.alpha.provider

    $protocol.rounds += @([ordered]@{
        phase       = "synthesis"
        agent       = "alpha"
        provider    = $ceos.alpha.provider
        duration_ms = [int]$synthesisDuration
        success     = $synthesisResult.success
        content     = $alphaSynthesis
    })

    if (-not $synthesisResult.success) {
        Write-Host "[DELIB] Synthese fehlgeschlagen! Verwende CEO-Proposal." -ForegroundColor Yellow
        $protocol.final_output = $alphaProposal
        $protocol.consensus_reached = $false
    } else {
        $protocol.final_output = $alphaSynthesis
        $protocol.consensus_reached = $true
        Write-Host "[DELIB] Synthese abgeschlossen ($([int]$synthesisDuration)ms)" -ForegroundColor Green
        Format-CeoChatOutput -Role "Synthesis" -AgentName $ceos.alpha.provider -Content $alphaSynthesis
    }

    $protocol.completed_at = (Get-Date -Format 'o')

    # --- Calculate total duration ---
    $totalMs = ($protocol.rounds | ForEach-Object { $_.duration_ms } | Measure-Object -Sum).Sum
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] ====== Deliberation abgeschlossen ======" -ForegroundColor Magenta
    Write-Host "[DELIB] Konsens: $(if ($protocol.consensus_reached) { 'JA' } else { 'NEIN (Fallback)' })" -ForegroundColor $(if ($protocol.consensus_reached) { "Green" } else { "Yellow" })
    Write-Host "[DELIB] Gesamtdauer: $([Math]::Round($totalMs / 1000, 1))s ($($protocol.rounds.Count) Phasen)" -ForegroundColor DarkGray

    # --- Save protocol ---
    Save-DeliberationProtocol -Protocol $protocol -Config $Config

    # --- Log to state ---
    if ($State) {
        Add-DeliberationLog -State $State -Protocol $protocol
    }

    $finalOutput = if ($protocol.consensus_reached) { $alphaSynthesis } else { $alphaProposal }

    return [ordered]@{
        success        = $true
        provider       = "$($ceos.alpha.provider)+$($ceos.beta.provider)"
        model          = "dual-ceo"
        output         = $finalOutput
        error          = $null
        stats          = $synthesisResult.stats
        deliberation   = $protocol
    }
}

function Save-DeliberationProtocol {
    <#
    .SYNOPSIS
    Saves the deliberation protocol as a JSON file to the logs directory.
    #>
    param(
        [Parameter(Mandatory)][object]$Protocol,
        [Parameter(Mandatory)][object]$Config
    )

    $dualCfg = $Config.dual_ceo
    $hasLogFlag = $dualCfg.PSObject.Properties.Name -contains "log_deliberations"
    if ($hasLogFlag -and -not $dualCfg.log_deliberations) { return }

    if (-not (Test-Path $script:DelibLogDir)) {
        New-Item -ItemType Directory -Path $script:DelibLogDir -Force | Out-Null
    }

    $fileName = "$($Protocol.deliberation_id).json"
    $filePath = Join-Path $script:DelibLogDir $fileName

    try {
        if (Get-Command Write-SafeJson -ErrorAction SilentlyContinue) {
            Write-SafeJson -FilePath $filePath -Data $Protocol
        } else {
            $Protocol | ConvertTo-Json -Depth 10 | Set-Content $filePath -Encoding UTF8
        }
        Write-Host "[DELIB] Protokoll gespeichert: $fileName" -ForegroundColor DarkGray
    } catch {
        Write-Warning "[DELIB] Protokoll konnte nicht gespeichert werden: $_"
    }
}

function Get-AutopilotFallbackRoute {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$TaskType,
        [string[]]$ExcludeProviders = @()
    )

    $candidates = @()
    if ($QuotaRegistry.routing_rules -and $QuotaRegistry.routing_rules.$TaskType) {
        $candidates += @($QuotaRegistry.routing_rules.$TaskType)
    }
    if ($Config.PSObject.Properties.Name -contains "dual_ceo" -and $Config.dual_ceo.ceo_beta_chain) {
        $candidates += @($Config.dual_ceo.ceo_beta_chain)
    }

    foreach ($candidate in $candidates) {
        $parts = [string]$candidate -split ":"
        $providerName = $parts[0]
        if ([string]::IsNullOrWhiteSpace($providerName) -or $ExcludeProviders -contains $providerName) { continue }
        if (-not (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $providerName)) { continue }

        $providerConfig = $QuotaRegistry.providers.$providerName
        if ($null -eq $providerConfig -or -not (Test-ObjectProperty -Object $providerConfig -Name "command") -or -not $providerConfig.command) { continue }
        if (-not (Get-Command $providerConfig.command -ErrorAction SilentlyContinue)) { continue }

        return [ordered]@{
            provider   = $providerName
            model_tier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
    }

    return $null
}

function Format-AutopilotTaskFailure {
    param([AllowNull()][object]$Result)

    if ($null -eq $Result) { return "Kein Ergebnisobjekt erhalten." }
    $provider = if (Test-ObjectProperty -Object $Result -Name "provider") { [string]$Result.provider } else { "unbekannt" }
    $errorCode = if (Test-ObjectProperty -Object $Result -Name "error") { [string]$Result.error } else { "UNKNOWN_ERROR" }
    $output = if (Test-ObjectProperty -Object $Result -Name "output") { [string]$Result.output } else { "" }
    $lines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $relevant = @($lines | Where-Object { $_ -match '(?i)\b(error|failed|failure|limit|quota|exceeded|exception|denied)\b' })
    $details = if ($relevant.Count -gt 0) { ($relevant | Select-Object -Last 4) -join " | " } else { ($lines | Select-Object -Last 6) -join " | " }
    $details = ($details -replace '\s+', ' ').Trim()
    if ($details.Length -gt 800) { $details = "..." + $details.Substring($details.Length - 800) }
    if ([string]::IsNullOrWhiteSpace($details)) { $details = "Keine Fehlerdetails vom Provider erhalten." }
    return "Provider=$provider; Fehler=$errorCode; Details=$details"
}

function Invoke-DualCeoTask {
    <#
    .SYNOPSIS
    Smart wrapper that decides whether to use Dual-CEO deliberation or single-agent mode.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [switch]$DryRun,
        [switch]$ForceDeliberation,
        [object]$State
    )

    # --- Fetch relevant memories for this task type ---
    $memoryBlock = Format-MemoryBlock -TaskType $TaskType

    $shouldDeliberate = $false

    # Check if dual_ceo is configured and enabled
    $hasDualCeo = $Config.PSObject.Properties.Name -contains "dual_ceo"
    if ($hasDualCeo -and $Config.dual_ceo.enabled) {
        # Check if this task type is in the deliberation list
        $delibTasks = @($Config.dual_ceo.deliberation_tasks)
        if ($delibTasks -contains $TaskType) {
            $shouldDeliberate = $true
        }
    }

    # Manual override via ForceDeliberation switch (Dashboard toggle)
    if ($ForceDeliberation.IsPresent) {
        $shouldDeliberate = $true
    }

    if ($shouldDeliberate) {
        return Invoke-Deliberation `
            -QuotaRegistry $QuotaRegistry `
            -Config $Config `
            -TaskType $TaskType `
            -Prompt $Prompt `
            -WorkingDirectory $WorkingDirectory `
            -MemoryBlock $memoryBlock `
            -DryRun:$DryRun `
            -State $State
    }

    # Resolve the preferred provider for the task first
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

    # --- Codex provider: Use the original visible session manager ---
    if ($providerName -eq "codex_orchestrator") {
        # Resolve model name
        $modelName = $null
        $providerConfig = $QuotaRegistry.providers.$providerName
        $hasModels = $providerConfig.PSObject.Properties.Name -contains "models"
        if ($hasModels -and $providerConfig.models -and $providerConfig.models.$modelTier) {
            $modelName = $providerConfig.models.$modelTier.name
        }
        $codexModel = if ($modelName) { $modelName } else { "gpt-5.4-mini" }

        Write-Host "[DELIB] Starte sichtbare Codex-Session (Single-Agent): $TaskType (Model: $codexModel)" -ForegroundColor Cyan

        $result = Invoke-AutopilotCodexSession `
            -SessionType $TaskType `
            -Prompt $Prompt `
            -State $State `
            -Model $codexModel `
            -VisibleExecTerminal `
            -DryRun:$DryRun

        if (-not $DryRun.IsPresent) {
            Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
        }

        $finalOutput = if (Test-ObjectProperty -Object $result -Name "Output") { [string]$result.Output } else { "" }
        $isSuccess = [bool]((Test-ObjectProperty -Object $result -Name "Success") -and $result.Success)
        if ($isSuccess) {
            if ((Test-ObjectProperty -Object $result -Name "OutputPath") -and $result.OutputPath -and (Test-Path -LiteralPath $result.OutputPath)) {
                $finalOutput = Get-Content -LiteralPath $result.OutputPath -Raw -Encoding UTF8
            } else {
                $finalOutput = if (Test-ObjectProperty -Object $result -Name "Output") { $result.Output } else { "" }
            }
        } else {
            if ($finalOutput -match "(?i)(usage limit|quota|limit reached)") {
                if (Get-Command Set-ProviderExhausted -ErrorAction SilentlyContinue) {
                    Set-ProviderExhausted -ProviderName $providerName
                }
            }
        }

        $codexTaskResult = [ordered]@{
            success  = $isSuccess
            provider = $providerName
            model    = $modelTier
            output   = $finalOutput
            error    = if (-not $isSuccess) { "CODEX_SESSION_FAILED" } else { $null }
            stats    = $null
        }
        if ($isSuccess) { return $codexTaskResult }

        $fallbackRoute = Get-AutopilotFallbackRoute -QuotaRegistry $QuotaRegistry -Config $Config -TaskType $TaskType -ExcludeProviders @($providerName)
        if ($null -eq $fallbackRoute) { return $codexTaskResult }

        Write-Host "[DELIB] Codex-Session fehlgeschlagen. Fallback auf $($fallbackRoute.provider):$($fallbackRoute.model_tier)." -ForegroundColor Yellow
        return Invoke-CliTask `
            -QuotaRegistry $QuotaRegistry `
            -TaskType $TaskType `
            -Prompt $Prompt `
            -WorkingDirectory $WorkingDirectory `
            -MemoryBlock $memoryBlock `
            -DryRun:$DryRun `
            -ProviderOverride $fallbackRoute.provider `
            -ModelTierOverride $fallbackRoute.model_tier
    }

    # Standard single-agent path for other providers
    $result = Invoke-CliTask `
        -QuotaRegistry $QuotaRegistry `
        -TaskType $TaskType `
        -Prompt $Prompt `
        -WorkingDirectory $WorkingDirectory `
        -MemoryBlock $memoryBlock `
        -DryRun:$DryRun `
        -ProviderOverride $providerName `
        -ModelTierOverride $modelTier

    # Fallback to QA Manager if the single-agent call failed and deliberation mode is enabled
    if (-not $result.success) {
        $fallbackRoute = Get-AutopilotFallbackRoute -QuotaRegistry $QuotaRegistry -Config $Config -TaskType $TaskType -ExcludeProviders @($providerName)
        if ($fallbackRoute) {
            $betaProvider = $fallbackRoute.provider
            $betaTier = $fallbackRoute.model_tier
            $betaRoute = "$betaProvider`:$betaTier"

            Write-Host "[DELIB] Standard-Agent fehlgeschlagen. Fallback auf anderen Provider ($betaRoute)." -ForegroundColor Yellow

            # If QA Manager is Codex, handle using Invoke-AutopilotCodexSession
            if ($betaProvider -eq "codex_orchestrator") {
                $codexModel = "gpt-5.4-mini"
                $betaProviderConfig = $QuotaRegistry.providers.$betaProvider
                if (
                    $betaTier -and
                    (Test-ObjectProperty -Object $betaProviderConfig -Name "models") -and
                    $betaProviderConfig.models -and
                    $betaProviderConfig.models.$betaTier
                ) {
                    $codexModel = [string]$betaProviderConfig.models.$betaTier.name
                }
                Write-Host "[DELIB] Starte sichtbare Codex-Session (QA Manager Fallback): $TaskType (Model: $codexModel)" -ForegroundColor Cyan

                $betaResult = Invoke-AutopilotCodexSession `
                    -SessionType $TaskType `
                    -Prompt $Prompt `
                    -State $State `
                    -Model $codexModel `
                    -VisibleExecTerminal `
                    -DryRun:$DryRun

                if (-not $DryRun.IsPresent) {
                    Register-ProviderCall -Registry $QuotaRegistry -ProviderName $betaProvider -ModelTier $betaTier
                }

                $finalOutput = if (Test-ObjectProperty -Object $betaResult -Name "Output") { [string]$betaResult.Output } else { "" }
                $isSuccess = [bool]((Test-ObjectProperty -Object $betaResult -Name "Success") -and $betaResult.Success)
                if ($isSuccess) {
                    if ((Test-ObjectProperty -Object $betaResult -Name "OutputPath") -and $betaResult.OutputPath -and (Test-Path -LiteralPath $betaResult.OutputPath)) {
                        $finalOutput = Get-Content -LiteralPath $betaResult.OutputPath -Raw -Encoding UTF8
                    } else {
                        $finalOutput = if (Test-ObjectProperty -Object $betaResult -Name "Output") { $betaResult.Output } else { "" }
                    }
                } else {
                    if ($finalOutput -match "(?i)(usage limit|quota|limit reached)") {
                        if (Get-Command Set-ProviderExhausted -ErrorAction SilentlyContinue) {
                            Set-ProviderExhausted -ProviderName $betaProvider
                        }
                    }
                }

                return [ordered]@{
                    success  = $isSuccess
                    provider = $betaProvider
                    model    = $betaTier
                    output   = $finalOutput
                    error    = if (-not $isSuccess) { "CODEX_SESSION_FAILED" } else { $null }
                    stats    = $null
                }
            } else {
                $result = Invoke-CliTask `
                    -QuotaRegistry $QuotaRegistry `
                    -TaskType $TaskType `
                    -Prompt $Prompt `
                    -WorkingDirectory $WorkingDirectory `
                    -MemoryBlock $memoryBlock `
                    -DryRun:$DryRun `
                    -ProviderOverride $betaProvider `
                    -ModelTierOverride $betaTier
            }
        }
    }

    return $result
}
