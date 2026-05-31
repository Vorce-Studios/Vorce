# scripts/codex-cli/lib/deliberation-engine.ps1
# Dual-CEO Deliberation Engine
# Orchestrates structured dialogue between two AI agents (Alpha + Beta)
# for higher-quality decisions on critical tasks.

Set-StrictMode -Version Latest

$script:DelibLogDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "logs\deliberations"

function Resolve-DualCeos {
    <#
    .SYNOPSIS
    Resolves CEO and Auditor providers from their respective fallback chains.
    Returns hashtable with ceo/auditor provider info.
    #>
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [string]$TaskType
    )

    $dualCfg = $Config.dual_ceo

    $ceoChain = @()
    $auditorChain = @()

    if ($TaskType -and $QuotaRegistry.routing_rules -and $QuotaRegistry.routing_rules.$TaskType) {
        $rules = @($QuotaRegistry.routing_rules.$TaskType)
        if ($rules.Count -gt 0) {
            $ceoChain = $rules + @($dualCfg.ceo_alpha_chain)
            $auditorChain = $rules + @($dualCfg.ceo_beta_chain)
        }
    }

    if ($ceoChain.Count -eq 0) {
        $ceoChain = @($dualCfg.ceo_alpha_chain)
    }
    if ($auditorChain.Count -eq 0) {
        $auditorChain = @($dualCfg.ceo_beta_chain)
    }

    # --- Resolve CEO ---
    $ceo = $null
    foreach ($route in $ceoChain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            # Use the original command name as-is. Do NOT rewrite to .cmd/.exe —
            # Windows .cmd files have an ~8191 char argument limit and escaping
            # issues that break long deliberation prompts.
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

    # --- Resolve Auditor ---
    $auditor = $null
    foreach ($route in $auditorChain) {
        $parts = $route -split ":"
        $provName = $parts[0]
        $modelTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }

        # Auditor must be different from CEO
        if ($ceo -and $provName -eq $ceo.provider) {
            Write-Host "[DELIB] Auditor-Kandidat '$provName' identisch mit CEO, ueberspringe." -ForegroundColor DarkGray
            continue
        }

        if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $provName) {
            $cmdName = $QuotaRegistry.providers.$provName.command
            # Use the original command name as-is (see Alpha comment above)
            $auditor = [ordered]@{
                provider   = $provName
                model_tier = $modelTier
                command    = $cmdName
                label      = "Auditor"
            }
            break
        }
        Write-Host "[DELIB] Auditor-Kandidat '$provName' nicht verfuegbar, naechster..." -ForegroundColor DarkGray
    }

    return [ordered]@{
        ceo     = $ceo
        auditor = $auditor
    }
}

function Format-DeliberationPrompt {
    <#
    .SYNOPSIS
    Builds phase-specific prompts for the deliberation dialogue.
    Optionally appends a memory block for context at the end.
    #>
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$OriginalPrompt,
        [string]$CeoProposal,
        [string]$AuditorCritique,
        [string]$MemoryBlock
    )

    $memSuffix = if (-not [string]::IsNullOrWhiteSpace($MemoryBlock)) {
        "`n`n" + $MemoryBlock
    } else {
        ""
    }

    switch ($Phase) {
        "proposal" {
            $p = @"
[DELIBERATION - PHASE: PROPOSAL]

AUFGABE:
$OriginalPrompt

ANWEISUNGEN:
- Erstelle einen gruendlichen, gut begruendeten Vorschlag.
- Erklaere deine Entscheidungslogik transparent.
- Benenne moegliche Risiken or Trade-offs.
- Sei praezise und strukturiert.
- Wenn du nach Dateien oder bestimmten Code-Stellen sucht, verwende entweder spezifische Filter or lass die spezifische Suche von einem der CLI-Tools ausführen. Versuche allgemein den Tokenverbrauch möglichst gering zu halten bzw. nicht unnötig für einfache Tasks wie Code-Analysen oder einer Suche zu verbrauchen.

Antworte im JSON-Format:
{
  "proposal": "<dein konkreter Vorschlag/Ergebnis>",
  "reasoning": "<Begruendung deiner Entscheidungen>",
  "risks": ["<Risiko 1>", "<Risiko 2>"],
  "confidence": "<high|medium|low>"
}$memSuffix
"@
            return $p
        }
        "critique" {
            $p = @"
[DELIBERATION - PHASE: AUDIT-CRITIQUE]
Der CEO hat einen Vorschlag zu folgender Aufgabe gemacht.
Deine Rolle als Auditor is kritischer Gegenpart: Hinterfrage, verbessere, zeige Alternativen auf.

ORIGINAL-AUFGABE:
$OriginalPrompt

VORSCHLAG VOM CEO:
$CeoProposal

DEINE AUFGABEN:
1. Pruefe den Vorschlag kritisch auf Schwachstellen und Luecken.
2. Identifiziere uebersehene Aspekte or bessere Alternativen.
3. Bewerte die genannten Risiken - sind sie vollstaendig?
4. Gib eine klare Empfehlung: Annehmen, Modifizieren or Ablehnen.
- Wenn du nach Dateien oder bestimmten Code-Stellen sucht, verwende entweder spezifische Filter or lass die spezifische Suche von einem der CLI-Tools ausführen. Versuche allgemein den Tokenverbrauch möglichst gering zu halten bzw. nicht unnötig für einfache Tasks wie Code-Analysen oder einer Suche zu verbrauchen.

Antworte im JSON-Format:
{
  "assessment": "<Gesamtbewertung des Vorschlags>",
  "strengths": ["<Staerke 1>", "<Staerke 2>"],
  "weaknesses": ["<Schwaeche 1>", "<Schwaeche 2>"],
  "alternatives": ["<Alternative 1>"],
  "recommendation": "approve|modify|reject",
  "suggested_changes": "<konkrete Aenderungsvorschlaege falls modify/reject>"
}$memSuffix
"@
            return $p
        }
        "synthesis" {
            $p = @"
[DELIBERATION - PHASE: CEO-SYNTHESIS]
Du bist der CEO. Du hast einen Vorschlag gemacht und der Auditor hat kritisches Feedback gegeben.
Erstelle jetzt eine FINALE SYNTHESE, die das Beste beider Perspektiven vereint.

ORIGINAL-AUFGABE:
$OriginalPrompt

DEIN URSPRUENGLICHER VORSCHLAG:
$CeoProposal

FEEDBACK VOM AUDITOR:
$AuditorCritique

ANWEISUNGEN:
- Integriere berechtigte Kritikpunkte in deine finale Loesung.
- Begruende, welche Kritik du annimmst und welche du begruendet ablehnst.
- Das Ergebnis soll besser sein als dein urspruenglicher Vorschlag allein.
- Liefere eine klare, umsetzbare Entscheidung.
- Wenn du nach Dateien oder bestimmten Code-Stellen sucht, verwende entweder spezifische Filter or lass die spezifische Suche von einem der CLI-Tools ausführen. Versuche allgemein den Tokenverbrauch möglichst gering zu halten bzw. nicht unnötig für einfache Tasks wie Code-Analysen oder einer Suche zu verbrauchen.

Antworte im selben Format wie die Original-Aufgabe es verlangt.
Falls die Original-Aufgabe JSON verlangt, antworte in diesem JSON-Format.
Falls nicht, antworte in klarem, strukturiertem Text.$memSuffix
"@
            return $p
        }
    }
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
            $parsed = $jsonMatch.Value | ConvertFrom-Json
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
        try { $parsed = $jsonMatch.Value | ConvertFrom-Json } catch {}
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
    For Codex providers: Uses Invoke-AutopilotCodexSession with -VisibleExecTerminal.
    For other providers (Gemini, Claude, etc.): Opens a visible pwsh window with the CLI command.
    Returns the output text and success status.
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
        Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier
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
            -VisibleTerminal `
            -DryRun:$DryRun

        Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier

        $finalOutput = ""
        $isSuccess = [bool]((Test-ObjectProperty -Object $result -Name "Success") -and $result.Success)
        if ($isSuccess) {
            if ($result.OutputPath -and (Test-Path -LiteralPath $result.OutputPath)) {
                $finalOutput = Get-Content -LiteralPath $result.OutputPath -Raw -Encoding UTF8
            } else {
                $finalOutput = if (Test-ObjectProperty -Object $result -Name "Output") { $result.Output } else { "" }
            }
        }

        return [ordered]@{
            success = $isSuccess
            output  = $finalOutput
            stats   = $null
        }
    }

    # --- All other providers (Gemini, Claude, Kiro, etc.): Open visible terminal ---
    $scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $tmpDir = Join-Path $scriptRoot "tmp"
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $timestamp = Get-Date -Format "HHmmss"
    $cleanPhase = $PhaseName -replace '[^a-zA-Z0-9_-]', ''
    $argsFile = Join-Path $tmpDir "ceo-args-$cleanPhase-$timestamp.json"
    $outputFile = Join-Path $tmpDir "ceo-output-$cleanPhase-$timestamp.txt"
    $statusFile = Join-Path $tmpDir "ceo-status-$cleanPhase-$timestamp.txt"
    $promptFile = Join-Path $tmpDir "ceo-prompt-$cleanPhase-$timestamp.txt"

    # Write prompt to file for stdin piping (avoids CLI escaping issues in Windows child shells)
    Set-Content -Path $promptFile -Value $Prompt -Encoding UTF8

    # Build CLI args, filtering out prompt argument to let the runner pipe prompt via stdin
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

    # Serialize args to file (avoids escaping hell)
    $cliArgs | ConvertTo-Json -Depth 5 | Set-Content -Path $argsFile -Encoding UTF8

    # Determine working directory
    $workDir = if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
        $WorkingDirectory
    } else {
        Split-Path -Parent (Split-Path -Parent $scriptRoot)
    }

    $runnerScript = Join-Path $scriptRoot "tools\run-visible-ceo-phase.ps1"
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

    # Wait for the visible terminal to finish
    $process.WaitForExit()
    $exitCode = $process.ExitCode

    # Read output
    $output = ""
    if (Test-Path -LiteralPath $outputFile) {
        $output = Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8
    }

    # Parse stats
    $parsedStats = ConvertFrom-CliStats -ProviderName $providerName -RawOutput $output
    Register-ProviderCall -Registry $QuotaRegistry -ProviderName $providerName -ModelTier $modelTier

    # Cleanup temp files
    Remove-Item -Path $argsFile, $outputFile, $statusFile, $promptFile -Force -ErrorAction SilentlyContinue

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
}

function Invoke-Deliberation {
    <#
    .SYNOPSIS
    Orchestrates a structured 3-phase deliberation between two CEO agents.
    Each phase opens a VISIBLE terminal window so the user can observe the CEOs.
    Falls back to single-agent mode if one CEO is unavailable.
    Returns the same result format as Invoke-CliTask for compatibility.
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
    Write-Host "[DELIB] ====== Deliberation: $deliberationId ======" -ForegroundColor Magenta
    Write-Host "[DELIB] Task-Typ: $TaskType" -ForegroundColor Magenta
    Write-Host "[DELIB] Jede Phase oeffnet ein sichtbares Terminal-Fenster." -ForegroundColor Magenta

    # --- Resolve both CEOs ---
    $ceos = Resolve-DualCeos -QuotaRegistry $QuotaRegistry -Config $Config -TaskType $TaskType

    # --- Fallback to single agent if needed ---
    if ($null -eq $ceos.ceo -and $null -eq $ceos.auditor) {
        Write-Host "[DELIB] Kein CEO verfuegbar! Fallback auf Standard-Router." -ForegroundColor Red
        return Invoke-CliTask -QuotaRegistry $QuotaRegistry -TaskType $TaskType -Prompt $Prompt -WorkingDirectory $WorkingDirectory -MemoryBlock $MemoryBlock -DryRun:$DryRun
    }

    if ($null -eq $ceos.ceo -or $null -eq $ceos.auditor) {
        $available = if ($ceos.ceo) { $ceos.ceo } else { $ceos.auditor }
        Write-Host "[DELIB] Nur ein Agent verfuegbar ($($available.provider)). Single-Agent-Modus (Visible)." -ForegroundColor Yellow

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

    Write-Host "[DELIB] CEO:     $($ceos.ceo.provider) ($($ceos.ceo.model_tier))" -ForegroundColor Cyan
    Write-Host "[DELIB] Auditor: $($ceos.auditor.provider) ($($ceos.auditor.model_tier))" -ForegroundColor Cyan

    $protocol = [ordered]@{
        deliberation_id   = $deliberationId
        task_type         = $TaskType
        started_at        = (Get-Date -Format 'o')
        ceo               = [ordered]@{ provider = $ceos.ceo.provider; model_tier = $ceos.ceo.model_tier }
        auditor           = [ordered]@{ provider = $ceos.auditor.provider; model_tier = $ceos.auditor.model_tier }
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
    Write-Host "[DELIB] Oeffne sichtbares CEO Terminal..." -ForegroundColor Yellow

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
    $ceoProposal = Get-CleanCeoOutput -RawOutput $proposalResult.output -ProviderName $ceos.ceo.provider

    $protocol.rounds += @([ordered]@{
        phase       = "proposal"
        agent       = "ceo"
        provider    = $ceos.ceo.provider
        duration_ms = [int]$proposalDuration
        success     = $proposalResult.success
        content     = $ceoProposal
    })

    if (-not $proposalResult.success) {
        Write-Host "[DELIB] CEO-Proposal fehlgeschlagen! Fallback auf Auditor (Visible)." -ForegroundColor Red
        $protocol.final_output = "CEO failed, fell back to Auditor visible agent"

        $fallbackResult = Invoke-VisibleCeoPhase `
            -QuotaRegistry $QuotaRegistry `
            -CeoInfo $ceos.auditor `
            -Prompt $proposalPrompt `
            -PhaseName "Fallback-Proposal" `
            -WorkingDirectory $WorkingDirectory `
            -State $State `
            -DryRun:$DryRun

        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [pscustomobject]@{
            success = $fallbackResult.success
            output  = Get-CleanCeoOutput -RawOutput $fallbackResult.output -ProviderName $ceos.auditor.provider
        }
    }

    Write-Host "[DELIB] CEO-Proposal erhalten ($([int]$proposalDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Proposal" -AgentName $ceos.ceo.provider -Content $ceoProposal

    # ==========================================
    # PHASE 2: AUDIT (Auditor) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 2: Audit (Auditor: $($ceos.auditor.provider)) ---" -ForegroundColor Yellow
    Write-Host "[DELIB] Oeffne sichtbares Auditor Terminal..." -ForegroundColor Yellow

    $critiquePrompt = Format-DeliberationPrompt -Phase "critique" -OriginalPrompt $Prompt -CeoProposal $ceoProposal -MemoryBlock $MemoryBlock
    $critiqueStart = Get-Date

    $critiqueResult = Invoke-VisibleCeoPhase `
        -QuotaRegistry $QuotaRegistry `
        -CeoInfo $ceos.auditor `
        -Prompt $critiquePrompt `
        -PhaseName "Audit" `
        -WorkingDirectory $WorkingDirectory `
        -State $State `
        -DryRun:$DryRun

    $critiqueDuration = ((Get-Date) - $critiqueStart).TotalMilliseconds
    $auditorCritique = Get-CleanCeoOutput -RawOutput $critiqueResult.output -ProviderName $ceos.auditor.provider

    $protocol.rounds += @([ordered]@{
        phase       = "critique"
        agent       = "auditor"
        provider    = $ceos.auditor.provider
        duration_ms = [int]$critiqueDuration
        success     = $critiqueResult.success
        content     = $auditorCritique
    })

    if (-not $critiqueResult.success) {
        Write-Host "[DELIB] Auditor-Audit fehlgeschlagen! Verwende CEO-Proposal als Endergebnis." -ForegroundColor Yellow
        $protocol.final_output = $ceoProposal
        $protocol.consensus_reached = $false
        $protocol.completed_at = (Get-Date -Format 'o')
        Save-DeliberationProtocol -Protocol $protocol -Config $Config

        return [ordered]@{
            success        = $true
            provider       = $ceos.ceo.provider
            model          = $ceos.ceo.model_tier
            output         = $ceoProposal
            error          = $null
            stats          = $proposalResult.stats
            deliberation   = $protocol
        }
    }

    Write-Host "[DELIB] Auditor-Audit erhalten ($([int]$critiqueDuration)ms)" -ForegroundColor Green
    Format-CeoChatOutput -Role "Audit" -AgentName $ceos.auditor.provider -Content $auditorCritique

    # ==========================================
    # PHASE 3: SYNTHESIS (CEO) - VISIBLE TERMINAL
    # ==========================================
    Write-Host "" -ForegroundColor White
    Write-Host "[DELIB] --- Phase 3: Synthesis (CEO: $($ceos.ceo.provider)) ---" -ForegroundColor Yellow
    Write-Host "[DELIB] Oeffne sichtbares CEO Terminal (Synthese)..." -ForegroundColor Yellow

    $synthesisPrompt = Format-DeliberationPrompt -Phase "synthesis" -OriginalPrompt $Prompt -CeoProposal $ceoProposal -AuditorCritique $auditorCritique -MemoryBlock $MemoryBlock
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
        $protocol.final_output = $ceoProposal
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

    $finalOutput = if ($protocol.consensus_reached) { $ceoSynthesis } else { $ceoProposal }

    return [ordered]@{
        success        = $true
        provider       = "$($ceos.ceo.provider)+$($ceos.auditor.provider)"
        model          = "ceo-auditor"
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

function Invoke-DualCeoTask {
    <#
    .SYNOPSIS
    Smart wrapper that decides whether to use Dual-CEO deliberation or single-agent mode.
    Drop-in replacement for Invoke-CliTask at call sites that should support deliberation.
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

    # Standard single-agent path
    $result = Invoke-CliTask `
        -QuotaRegistry $QuotaRegistry `
        -TaskType $TaskType `
        -Prompt $Prompt `
        -WorkingDirectory $WorkingDirectory `
        -MemoryBlock $memoryBlock `
        -DryRun:$DryRun

    # Fallback to Beta CEO if the single-agent call failed and Dual-CEO is enabled
    if (-not $result.success -and $hasDualCeo -and $Config.dual_ceo.enabled) {
        $betaRoute = $Config.dual_ceo.ceo_beta_chain[0]
        if ($betaRoute) {
            $parts = $betaRoute -split ":"
            $betaProvider = $parts[0]
            $betaTier = if ($parts.Count -gt 1) { $parts[1] } else { $null }

            Write-Host "[DELIB] Standard-Agent fehlgeschlagen! Fallback auf Beta CEO ($betaRoute)." -ForegroundColor Red

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

    return $result
}
