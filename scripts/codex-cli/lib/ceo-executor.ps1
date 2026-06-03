# scripts/codex-cli/lib/ceo-executor.ps1
# Single-CEO Execution Engine (Visible Terminal)
# Orchestrates task execution in a visible process window.

Set-StrictMode -Version Latest

# Load required libraries for argument building
$script:LibDir = Split-Path -Parent $PSCommandPath
. (Join-Path $script:LibDir "cli-router.ps1")

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

    $libRoot = Split-Path -Parent $PSCommandPath
    $scriptRoot = Split-Path -Parent $libRoot
    $tempDir = Join-Path $scriptRoot "tmp"
    if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

    $uniqueId = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $argsFile = Join-Path $tempDir "args-$uniqueId.json"
    $outputFile = Join-Path $tempDir "output-$uniqueId.txt"
    $statusFile = Join-Path $tempDir "status-$uniqueId.txt"
    $promptFile = Join-Path $tempDir "prompt-$uniqueId.txt"

    # Resolve actual model name from tier
    $providerConfig = $QuotaRegistry.providers.$providerName
    $modelName = if ($providerConfig.models.PSObject.Properties.Name -contains $modelTier) {
        $providerConfig.models.$modelTier.name
    } else {
        $modelTier
    }

    # Build arguments with placeholder for prompt to avoid length limits in JSON
    # run-visible-ceo-phase.ps1 will replace __V_PROMPT__ with actual prompt
    $cliArgs = @()
    if ($providerConfig.PSObject.Properties.Name -contains "cli_args" -and $providerConfig.cli_args) {
        foreach ($arg in $providerConfig.cli_args) {
            $replaced = if ($providerName -eq "codex_orchestrator" -and $arg -match '\{PROMPT\}') {
                $arg -replace '\{PROMPT\}', '-'
            } else {
                $arg -replace '\{PROMPT\}', '__V_PROMPT__'
            }
            $replaced = $replaced -replace '\{MODEL\}', $modelName
            $cliArgs += $replaced
        }
    } else {
        # Default fallback
        $cliArgs = @("-p", "__V_PROMPT__")
    }

    $cliArgs | ConvertTo-Json -Depth 5 | Set-Content -Path $argsFile -Encoding UTF8
    $Prompt | Set-Content -Path $promptFile -Encoding UTF8

    $workDir = if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) { $WorkingDirectory } else { $scriptRoot }
    $runnerScript = Join-Path $scriptRoot "tools\run-visible-ceo-phase.ps1"
    
    $powerShellHost = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($powerShellHost) { $powerShellHost = $powerShellHost.Source } else { $powerShellHost = (Get-Command powershell -ErrorAction Stop).Source }

    $runnerArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runnerScript, "-CliCommand", $CeoInfo.command, "-CliArgsFile", $argsFile, "-OutputFile", $outputFile, "-StatusFile", $statusFile, "-PromptFile", $promptFile, "-PhaseName", "$($CeoInfo.label): $PhaseName", "-ProviderName", $providerName, "-ModelName", "$modelTier ($modelName)", "-WorkingDirectory", $workDir)

    Write-Host "[CEO] Oeffne sichtbares Terminal: $($CeoInfo.label) - $PhaseName ($providerName)" -ForegroundColor Cyan
    $process = Start-Process -FilePath $powerShellHost -ArgumentList $runnerArgs -WindowStyle Normal -PassThru
    $process.WaitForExit()
    
    $output = if (Test-Path $outputFile) { Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 } else { "" }
    
    # Read status from status file if possible (more reliable than process exit code in some shells)
    $finalSuccess = ($process.ExitCode -eq 0)
    if (Test-Path $statusFile) {
        $statusVal = Get-Content -Path $statusFile -Raw | Out-String
        if ($statusVal.Trim() -eq "0") { $finalSuccess = $true }
        elseif ($statusVal.Trim() -ne "") { $finalSuccess = $false }
    }

    Remove-Item -Path $argsFile, $outputFile, $statusFile, $promptFile -Force -ErrorAction SilentlyContinue

    return [pscustomobject]@{ success = $finalSuccess; output = $output; stats = @{} }
}

function Invoke-HeadlessCeoPhase {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][object]$CeoInfo,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory,
        [switch]$DryRun
    )

    $providerName = $CeoInfo.provider
    $modelTier = $CeoInfo.model_tier
    $providerConfig = $QuotaRegistry.providers.$providerName
    $command = $CeoInfo.command

    if ($DryRun.IsPresent) {
        Write-Host "[DRY-RUN] Headless Phase: $providerName ($modelTier)" -ForegroundColor Yellow
        return [pscustomobject]@{ success = $true; output = "{`"dry_run`": true}"; stats = @{} }
    }

    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ success = $false; output = "CLI-Befehl '$command' nicht gefunden."; stats = @{} }
    }

    $modelName = $null
    if ($providerConfig.PSObject.Properties.Name -contains "models" -and $providerConfig.models -and ($providerConfig.models.PSObject.Properties.Name -contains $modelTier)) {
        $modelName = $providerConfig.models.$modelTier.name
    }

    $usePromptStdin = $providerName -eq "codex_orchestrator"
    $cliArgs = Build-CliArgs -ProviderConfig $providerConfig -Prompt $Prompt -ModelName $modelName -UsePromptStdin:($usePromptStdin)
    if ($modelName -and $modelName -ne "default") {
        switch ($providerName) {
            "gemini_cli" { $cliArgs += @("--model", $modelName) }
            "claude_code" { $cliArgs += @("--model", $modelName) }
        }
    }

    $output = ""
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
            $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        } finally {
            if ($pushDir) { Pop-Location }
        }
    } catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }

    if ($exitCode -ne 0) {
        $snippet = ([string]$output).Trim()
        if ($snippet.Length -gt 1200) { $snippet = $snippet.Substring(0, 1200) + "..." }
        Write-Warning "[CEO] Headless $providerName ($modelTier) fehlgeschlagen: EXIT_CODE_$exitCode. Ausgabe: $snippet"
    }

    return [pscustomobject]@{
        success = ($exitCode -eq 0)
        output  = $output
        stats   = @{}
    }
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
        $dualCeo = $Config.dual_ceo
        if (($dualCeo.PSObject.Properties.Name -contains "ceo_alpha_chain") -and $dualCeo.ceo_alpha_chain) {
            $parts = $dualCeo.ceo_alpha_chain[0] -split ":"
            $alphaProvider = $parts[0]
            $alphaTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
        if (($dualCeo.PSObject.Properties.Name -contains "ceo_beta_chain") -and $dualCeo.ceo_beta_chain) {
            $parts = $dualCeo.ceo_beta_chain[0] -split ":"
            $betaProvider = $parts[0]
            $betaTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
        # Migration from ceo_beta_chain to qa_auditor_chain
        if (($dualCeo.PSObject.Properties.Name -contains "qa_auditor_chain") -and $dualCeo.qa_auditor_chain) {
            $parts = $dualCeo.qa_auditor_chain[0] -split ":"
            $betaProvider = $parts[0]
            $betaTier = if ($parts.Count -gt 1) { $parts[1] } else { "default" }
        }
    }

    return [pscustomobject]@{
        alpha = [ordered]@{ provider = $alphaProvider; model_tier = $alphaTier; command = $QuotaRegistry.providers.$alphaProvider.command; label = "CEO Alpha" }
        beta  = [ordered]@{ provider = $betaProvider; model_tier = $betaTier; command = $QuotaRegistry.providers.$betaProvider.command; label = "QA-Auditor" }
    }
}

function Resolve-CeoModelTier {
    param(
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$RequestedTier,
        [Parameter(Mandatory)][string]$TaskType
    )

    $providerConfig = $QuotaRegistry.providers.$ProviderName
    if (-not $providerConfig -or -not ($providerConfig.PSObject.Properties.Name -contains "models") -or -not $providerConfig.models) {
        return $RequestedTier
    }

    $modelKeys = @($providerConfig.models.PSObject.Properties.Name)
    if ($modelKeys -contains $RequestedTier) { return $RequestedTier }

    if ($ProviderName -eq "codex_orchestrator") {
        if ($RequestedTier -in @("fast", "cheap", "monitoring") -and $modelKeys -contains "monitoring") { return "monitoring" }
        if ($modelKeys -contains "planning") { return "planning" }
    }

    if ($modelKeys -contains $TaskType) { return $TaskType }

    switch ($RequestedTier) {
        { $_ -in @("fast", "cheap") } {
            if ($modelKeys -contains "cheap") { return "cheap" }
            if ($modelKeys -contains "monitoring") { return "monitoring" }
            break
        }
        "balanced" {
            if ($modelKeys -contains "balanced") { return "balanced" }
            if ($modelKeys -contains "planning") { return "planning" }
            break
        }
        { $_ -in @("high", "premium") } {
            if ($modelKeys -contains "premium") { return "premium" }
            if ($modelKeys -contains "planning") { return "planning" }
            break
        }
    }

    if ($modelKeys.Count -gt 0) { return $modelKeys[0] }
    return $RequestedTier
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
    $useBeta = $TaskType -eq "audit"
    $ceoInfo = if ($useBeta) { $ceos.beta } else { $ceos.alpha }
    $requestedTier = if ($useBeta) {
        if (-not [string]::IsNullOrWhiteSpace($BetaTierOverride)) { $BetaTierOverride }
        elseif (-not [string]::IsNullOrWhiteSpace($AlphaTierOverride)) { $AlphaTierOverride }
        else { [string]$ceoInfo.model_tier }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($AlphaTierOverride)) { $AlphaTierOverride }
        else { [string]$ceoInfo.model_tier }
    }
    $ceoInfo.model_tier = Resolve-CeoModelTier -QuotaRegistry $QuotaRegistry -ProviderName $ceoInfo.provider -RequestedTier $requestedTier -TaskType $TaskType

    if ($requestedTier -ne $ceoInfo.model_tier) {
        Write-Host "[CEO] Provider: $($ceoInfo.provider) ($($ceoInfo.model_tier), gemappt von $requestedTier)" -ForegroundColor Cyan
    } else {
        Write-Host "[CEO] Provider: $($ceoInfo.provider) ($($ceoInfo.model_tier))" -ForegroundColor Cyan
    }

    $fullPrompt = Format-DeliberationPrompt -Phase "proposal" -OriginalPrompt $Prompt -MemoryBlock $MemoryBlock
    Write-Host "[CEO] Starte headless $($ceoInfo.provider) CLI fuer kurzen $TaskType-Schritt." -ForegroundColor Cyan
    $result = Invoke-HeadlessCeoPhase -QuotaRegistry $QuotaRegistry -CeoInfo $ceoInfo -Prompt $fullPrompt -WorkingDirectory $WorkingDirectory -DryRun:$DryRun

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

    $memoryBlock = Format-MemoryBlock -TaskType $TaskType -Prompt $Prompt -Store (Read-MemoryStore)

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
