# Vorce-Autopilot/src/lib/deliberation-engine.ps1
# Dual-CEO Deliberation Engine
# Orchestrates structured dialogue between two AI agents (ceo + qa_manager)
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
    Returns hashtable with ceo/qa_manager provider info, or $null for unavailable CEOs.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config
    )

    $dualCfg = $Config.dual_ceo

    # --- Resolve CEO ---
    $ceo = $null
    foreach ($route in $dualCfg.ceo_chain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            $ceo = [ordered]@{
                provider   = $provName
                model_tier = $modelTier
                command    = $cmdName
                label      = "CEO"
            }
            break
        }
        Write-Host "[DELIB] CEO-Kandidat '$provName' nicht verfuegbar, naechster..." -ForegroundColor DarkGray
    }

    # --- Resolve QA Manager ---
    $qa_manager = $null
    foreach ($route in $dualCfg.qa_manager_chain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        # qa_manager must be different from ceo
        if ($ceo -and $provName -eq $ceo.provider) {
            Write-Host "[DELIB] QA-Manager-Kandidat '$provName' identisch mit CEO, ueberspringe." -ForegroundColor DarkGray
            continue
        }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            $qa_manager = [ordered]@{
                provider   = $provName
                model_tier = $modelTier
                command    = $cmdName
                label      = "QA-Manager"
            }
            break
        }
        Write-Host "[DELIB] QA-Manager-Kandidat '$provName' nicht verfuegbar, naechster..." -ForegroundColor DarkGray
    }

    return [ordered]@{
        ceo = $ceo
        qa_manager  = $qa_manager
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
        [string]$CeoProposal,
        [string]$QaCritique,
        [string]$MemoryBlock
    )

    # Prepend memory block to original prompt if provided
    $contextPrompt = if (-not [string]::IsNullOrWhiteSpace($MemoryBlock)) {
        $MemoryBlock + $OriginalPrompt
    } else {
        $OriginalPrompt
    }

    $vars = @{ contextPrompt = $contextPrompt }
    if ($null -ne $CeoProposal) {
        $vars["CeoProposal"] = $CeoProposal
    }
    if ($null -ne $QaCritique) {
        $vars["QaCritique"] = $QaCritique
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

        $runnerScript = Join-Path $script:ScriptRoot "tools\run-hidden-ceo-phase.ps1"
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
    if ($null -eq $ceos.ceo -and $null -eq $ceos.qa_manager) {
        Write-Host "[DELIB] Kein CEO verfuegbar! Fallback auf Standard-Router." -ForegroundColor Red
        return Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType $TaskType -Prompt $Prompt -WorkingDirectory $WorkingDirectory -MemoryBlock $MemoryBlock -DryRun:$DryRun
    }

    if ($null -eq $ceos.ceo -or $null -eq $ceos.qa_manager) {
        $available = if ($ceos.ceo) { $ceos.ceo } else { $ceos.qa_manager }
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

    Write-Host "[DELIB] CEO: $($ceos.ceo.provider) ($($ceos.ceo.model_tier))" -ForegroundColor Cyan
    Write-Host "[DELIB] QA Manager:  $($ceos.qa_manager.provider) ($($ceos.qa_manager.model_tier))" -ForegroundColor Cyan

    $protocol = [ordered]@{
        deliberation_id   = $deliberationId
        task_type         = $TaskType
        started_at        = (Get-Date -Format 'o')
        ceo             = [ordered]@{ provider = $ceos.ceo.provider; model_tier = $ceos.ceo.model_tier }
        qa_manager              = [ordered]@{ provider = $ceos.qa_manager.provider; model_tier = $ceos.qa_manager.model_tier }
        rounds            = @()
        consensus_reached = $false
        final_output      = $null
        completed_at      = $null
    }

    # ==========================================
    # PHASE 1: PROPOSAL (CEO) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 1: Proposal (CEO: $($ceos.ceo.provider)) ---" -ForegroundColor Yellow

    $proposalPrompt = Format-DeliberationPrompt -Phase "proposal" -OriginalPrompt $Prompt -MemoryBlock $MemoryBlock
    $proposalStart = Get-Date

    $proposalResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.ceo `
        -Prompt $proposalPrompt `
        -PhaseName "Proposal" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $proposalDuration = ((Get-Date) - $proposalStart).TotalMilliseconds
    $CeoProposal = Get-CleanCeoOutput -RawOutput $proposalResult.output -ProviderName $ceos.ceo.provider

    $protocol.rounds += @([ordered]@{
        phase       = "proposal"
        agent       = "ceo"
        provider    = $ceos.ceo.provider
        duration_ms = [int]$proposalDuration
        success     = $proposalResult.success
        content     = $CeoProposal
    })

    if (-not $proposalResult.success) {
        Write-Host "[DELIB] CEO-Proposal (ceo) fehlgeschlagen! Versuche Fallback-Proposal durch QA-Manager (qa_manager)..." -ForegroundColor Yellow
        $fallbackStart = Get-Date
        $fallbackResult = Invoke-VisibleCeoPhase `
            -QuotaRegistry $QuotaRegistry `
            -CeoInfo $ceos.qa_manager `
            -Prompt $proposalPrompt `
            -PhaseName "Proposal (Fallback)" `
            -WorkingDirectory $WorkingDirectory `
            -State $State `
            -DryRun:$DryRun

        $fallbackDuration = ((Get-Date) - $fallbackStart).TotalMilliseconds
        $qaProposal = Get-CleanCeoOutput -RawOutput $fallbackResult.output -ProviderName $ceos.qa_manager.provider

        $protocol.rounds += @([ordered]@{
            phase       = "proposal_fallback"
            agent       = "qa_manager"
            provider    = $ceos.qa_manager.provider
            duration_ms = [int]$fallbackDuration
            success     = $fallbackResult.success
            content     = $qaProposal
        })

        if (-not $fallbackResult.success) {
            Write-Host "[DELIB] CEO-Proposal Fallback fehlgeschlagen! Breche Deliberation ab." -ForegroundColor Red
            $protocol.final_output = "ceo and qa_manager failed. Deliberation aborted."
            $protocol.consensus_reached = $false

            $protocol.completed_at = (Get-Date -Format 'o')
            Save-DeliberationProtocol -Protocol $protocol -Config $Config

            return [ordered]@{
                success        = $false
                provider       = $ceos.ceo.provider
                model          = $ceos.ceo.model_tier
                output         = $CeoProposal
                error          = "PROPOSAL_FAILED"
                stats          = $proposalResult.stats
                deliberation   = $protocol
            }
        }

        Write-Host "[DELIB] CEO-Proposal Fallback (qa_manager) erfolgreich." -ForegroundColor Green
        Format-CeoChatOutput -Role "Proposal (Fallback)" -AgentName $ceos.qa_manager.provider -Content $qaProposal

        $protocol.final_output = $qaProposal
        $protocol.consensus_reached = $false
        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [ordered]@{
            success        = $true
            provider       = $ceos.qa_manager.provider
            model          = $ceos.qa_manager.model_tier
            output         = $qaProposal
            error          = $null
            stats          = $fallbackResult.stats
            deliberation   = $protocol
        }
    }

    Write-Host "[DELIB] CEO-Proposal erhalten ($([int]$proposalDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Proposal" -AgentName $ceos.ceo.provider -Content $CeoProposal

    # ==========================================
    # PHASE 2: CRITIQUE (QA Manager) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 2: Critique (QA Manager: $($ceos.qa_manager.provider)) ---" -ForegroundColor Yellow

    $critiquePrompt = Format-DeliberationPrompt -Phase "critique" -OriginalPrompt $Prompt -CeoProposal $CeoProposal -MemoryBlock $MemoryBlock
    $critiqueStart = Get-Date

    $critiqueResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.qa_manager `
        -Prompt $critiquePrompt `
        -PhaseName "Critique" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $critiqueDuration = ((Get-Date) - $critiqueStart).TotalMilliseconds
    $QaCritique = Get-CleanCeoOutput -RawOutput $critiqueResult.output -ProviderName $ceos.qa_manager.provider

    $protocol.rounds += @([ordered]@{
        phase       = "critique"
        agent       = "qa_manager"
        provider    = $ceos.qa_manager.provider
        duration_ms = [int]$critiqueDuration
        success     = $critiqueResult.success
        content     = $QaCritique
    })

    if (-not $critiqueResult.success) {
        Write-Host "[DELIB] QA-Critique fehlgeschlagen! Verwende CEO-Proposal als Endergebnis." -ForegroundColor Yellow
        $protocol.final_output = $CeoProposal
        $protocol.consensus_reached = $false
        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [ordered]@{
            success        = $true
            provider       = $ceos.ceo.provider
            model          = $ceos.ceo.model_tier
            output         = $CeoProposal
            error          = $null
            stats          = $proposalResult.stats
            deliberation   = $protocol
        }
    }

    Write-Host "[DELIB] QA-Critique erhalten ($([int]$critiqueDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Critique" -AgentName $ceos.qa_manager.provider -Content $QaCritique

    # ==========================================
    # PHASE 3: SYNTHESIS (CEO) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 3: Synthesis (CEO: $($ceos.ceo.provider)) ---" -ForegroundColor Yellow

    $synthesisPrompt = Format-DeliberationPrompt -Phase "synthesis" -OriginalPrompt $Prompt -CeoProposal $CeoProposal -qa_managerCritique $QaCritique -MemoryBlock $MemoryBlock
    $synthesisStart = Get-Date

    $synthesisResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.ceo `
        -Prompt $synthesisPrompt `
        -PhaseName "Synthesis" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $synthesisDuration = ((Get-Date) - $synthesisStart).TotalMilliseconds
    $ceoSynthesis = Get-CleanCeoOutput -RawOutput $synthesisResult.output -ProviderName $ceos.ceo.provider

    $protocol.rounds += @([ordered]@{
        phase       = "synthesis"
        agent       = "ceo"
        provider    = $ceos.ceo.provider
        duration_ms = [int]$synthesisDuration
        success     = $synthesisResult.success
        content     = $ceoSynthesis
    })

    if (-not $synthesisResult.success) {
        Write-Host "[DELIB] Synthese fehlgeschlagen! Verwende CEO-Proposal." -ForegroundColor Yellow
        $protocol.final_output = $CeoProposal
        $protocol.consensus_reached = $false
    } else {
        $protocol.final_output = $ceoSynthesis
        $protocol.consensus_reached = $true
        Write-Host "[DELIB] Synthese abgeschlossen ($([int]$synthesisDuration)ms)" -ForegroundColor Green
        Format-CeoChatOutput -Role "Synthesis" -AgentName $ceos.ceo.provider -Content $ceoSynthesis
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

    $finalOutput = if ($protocol.consensus_reached) { $ceoSynthesis } else { $CeoProposal }

    return [ordered]@{
        success        = $true
        provider       = "$($ceos.ceo.provider)+$($ceos.qa_manager.provider)"
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
    if ($Config.PSObject.Properties.Name -contains "dual_ceo" -and $Config.dual_ceo.qa_manager_chain) {
        $candidates += @($Config.dual_ceo.qa_manager_chain)
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
