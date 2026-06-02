# scripts/codex-cli/lib/deliberation-engine.ps1
# Single-CEO Execution Engine (Visible Terminal)
# Orchestrates task execution in a visible process window.

Set-StrictMode -Version Latest

function Format-DeliberationPrompt {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$OriginalPrompt,
        [string]$MemoryBlock
    )

    $contextPrompt = if (-not [string]::IsNullOrWhiteSpace($MemoryBlock)) {
        $MemoryBlock + $OriginalPrompt
    } else {
        $OriginalPrompt
    }

    return @"
Du bist CEO ALPHA des Vorce-Autopiloten.

AUFGABE:
$contextPrompt

ANWEISUNGEN:
- Erstelle ein präzises Ergebnis.
- Sei transparent und strukturiert.
- HALTE DEINE TERMINAL-AUSGABEN UND DEINE BEFEHLSAUSFÜHRUNGEN EXTREM KOMPAKT.
- Schreibe vor der Ausführung eines Befehls immer eine kurze, verständliche Erklärung auf Deutsch.
"@
}

function Get-CleanCeoOutput {
    param([string]$RawOutput, [string]$ProviderName)
    if ([string]::IsNullOrWhiteSpace($RawOutput)) { return "" }
    return $RawOutput.Trim()
}

function Invoke-VisibleCeoPhase {
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

    if ($DryRun.IsPresent) {
        Write-Host "[DRY-RUN] Visible Phase: $PhaseName ($providerName)" -ForegroundColor Yellow
        return [pscustomobject]@{ success = $true; output = "{`"dry_run`": true}"; stats = @{} }
    }

    # FIX: Path to runner script is one level up from lib
    $libRoot = Split-Path -Parent $PSCommandPath
    $scriptRoot = Split-Path -Parent $libRoot
    $tempDir = Join-Path $scriptRoot "tmp"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

    $uniqueId = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $argsFile = Join-Path $tempDir "args-$uniqueId.json"
    $outputFile = Join-Path $tempDir "output-$uniqueId.txt"
    $statusFile = Join-Path $tempDir "status-$uniqueId.txt"
    $promptFile = Join-Path $tempDir "prompt-$uniqueId.txt"

    # Important: Do not include prompt in args file, as run-visible-ceo-phase.ps1 adds it from prompt file
    $cliArgs = @()
    $cliArgs | ConvertTo-Json -Depth 5 | Set-Content -Path $argsFile -Encoding UTF8
    $Prompt | Set-Content -Path $promptFile -Encoding UTF8

    $workDir = if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) { $WorkingDirectory } else { $scriptRoot }
    $runnerScript = Join-Path $scriptRoot "tools\run-visible-ceo-phase.ps1"
    
    $powerShellHost = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($powerShellHost) { $powerShellHost = $powerShellHost.Source } else { $powerShellHost = (Get-Command powershell -ErrorAction Stop).Source }

    $runnerArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runnerScript, "-CliCommand", $CeoInfo.command, "-CliArgsFile", $argsFile, "-OutputFile", $outputFile, "-StatusFile", $statusFile, "-PromptFile", $promptFile, "-PhaseName", "$($CeoInfo.label): $PhaseName", "-ProviderName", $providerName, "-ModelName", $modelTier, "-WorkingDirectory", $workDir)

    Write-Host "[CEO] Oeffne sichtbares Terminal: $($CeoInfo.label) - $PhaseName ($providerName)" -ForegroundColor Cyan
    $process = Start-Process -FilePath $powerShellHost -ArgumentList $runnerArgs -WindowStyle Normal -PassThru
    $process.WaitForExit()
    
    $output = if (Test-Path $outputFile) { Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 } else { "" }
    Remove-Item -Path $argsFile, $outputFile, $statusFile, $promptFile -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{ success = ($process.ExitCode -eq 0); output = $output; stats = @{} }
}

function Resolve-DualCeos {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config
    )

    $alphaProvider = "gemini_cli"
    $alphaTier = "balanced"
    $betaProvider = "gemini_cli"
    $betaTier = "cheap"

    if ($Config.PSObject.Properties.Name -contains "dual_ceo") {
        if ($Config.dual_ceo.ceo_alpha_chain) {
            $parts = $Config.dual_ceo.ceo_alpha_chain[0] -split ":"
            $alphaProvider = $parts[0]
            $alphaTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
        if ($Config.dual_ceo.ceo_beta_chain) {
            $parts = $Config.dual_ceo.ceo_beta_chain[0] -split ":"
            $betaProvider = $parts[0]
            $betaTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
    }

    return [pscustomobject]@{
        alpha = [ordered]@{ provider = $alphaProvider; model_tier = $alphaTier; command = $QuotaRegistry.providers.$alphaProvider.command; label = "CEO Alpha" }
        beta  = [ordered]@{ provider = $betaProvider; model_tier = $betaTier; command = $QuotaRegistry.providers.$betaProvider.command; label = "CEO Beta" }
    }
}

function Invoke-Deliberation {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [string]$MemoryBlock,
        [switch]$DryRun,
        [object]$State,
        [string]$AlphaTierOverride = $null,
        [string]$BetaTierOverride = $null
    )

    $ceos = Resolve-DualCeos -QuotaRegistry $QuotaRegistry -Config $Config
    $ceoInfo = $ceos.alpha
    if (-not [string]::IsNullOrWhiteSpace($AlphaTierOverride)) { $ceoInfo.model_tier = $AlphaTierOverride }

    Write-Host "[CEO] Provider: $($ceoInfo.provider) ($($ceoInfo.model_tier))" -ForegroundColor Cyan

    $fullPrompt = Format-DeliberationPrompt -Phase "proposal" -OriginalPrompt $Prompt -MemoryBlock $MemoryBlock
    $result = Invoke-VisibleCeoPhase -QuotaRegistry $QuotaRegistry -CeoInfo $ceoInfo -Prompt $fullPrompt -PhaseName "Execution" -WorkingDirectory $WorkingDirectory -State $State -DryRun:$DryRun

    return [pscustomobject]@{
        success = $result.success
        output  = Get-CleanCeoOutput -RawOutput $result.output -ProviderName $ceoInfo.provider
        stats   = $result.stats
        provider = $ceoInfo.provider
    }
}

function Invoke-DualCeoTask {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [switch]$DryRun,
        [switch]$ForceDeliberation,
        [object]$State,
        [string]$AlphaTierOverride = $null,
        [string]$BetaTierOverride = $null
    )

    $memoryBlock = Format-MemoryBlock -TaskType $TaskType -Store (Read-MemoryStore)

    return Invoke-Deliberation `
        -QuotaRegistry $QuotaRegistry `
        -Config $Config `
        -TaskType $TaskType `
        -Prompt $Prompt `
        -WorkingDirectory $WorkingDirectory `
        -MemoryBlock $memoryBlock `
        -DryRun:$DryRun `
        -State $State `
        -AlphaTierOverride $AlphaTierOverride `
        -BetaTierOverride $BetaTierOverride
}
