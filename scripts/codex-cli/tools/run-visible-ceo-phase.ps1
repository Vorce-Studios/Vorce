# scripts/codex-cli/tools/run-visible-ceo-phase.ps1
# Runs a single CEO deliberation phase in a VISIBLE terminal window.
# The output is displayed live AND written to an output file for the caller.
#
# Used by deliberation-engine.ps1 to make CEO sessions visible to the user.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CliCommand,
    [Parameter(Mandatory)][string]$CliArgsFile,
    [Parameter(Mandatory)][string]$OutputFile,
    [Parameter(Mandatory)][string]$StatusFile,
    [Parameter(Mandatory)][string]$PhaseName,
    [string]$ProviderName = "unknown",
    [string]$ModelName = "",
    [string]$PromptFile = "",
    [string]$WorkingDirectory
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Show-CeoPhaseSummary {
    param(
        [string]$Content,
        [string]$Phase
    )

    # Try to parse content as JSON
    $jsonMatch = [regex]::Match($Content, '(?s)\{.*\}')
    $parsed = $null
    if ($jsonMatch.Success) {
        try { $parsed = $jsonMatch.Value | ConvertFrom-Json } catch {}
    }

    Write-Host "  CEO-ZUSAMMENFASSUNG: $Phase" -ForegroundColor Cyan
    Write-Host ("." * 40) -ForegroundColor Gray

    if ($null -ne $parsed) {
        if ($parsed.PSObject.Properties.Name -contains "assessment") {
            Write-Host "  Bewertung:    $($parsed.assessment)" -ForegroundColor Gray
            Write-Host "  Empfehlung:   $($parsed.recommendation)" -ForegroundColor $(if ($parsed.recommendation -eq "approve") { "Green" } else { "Yellow" })
        } elseif ($parsed.PSObject.Properties.Name -contains "proposal") {
            Write-Host "  Vorschläge:" -ForegroundColor Cyan
            foreach ($p in $parsed.proposal) {
                if ($null -ne $p -and $p.PSObject -and $p.PSObject.Properties -and $p.PSObject.Properties.Name -contains "title") {
                    Write-Host "    - $($p.title)" -ForegroundColor Gray
                } else {
                    Write-Host "    - $p" -ForegroundColor Gray
                }
            }
        } else {
            # Generic JSON formatting for other responses
            $propCount = 0
            $parsed.PSObject.Properties | ForEach-Object {
                if ($propCount -lt 10) {
                    $val = if ($_.Value -is [System.Array]) { "$($_.Value.Count) items" } else { $_.Value }
                    Write-Host "  $($_.Name): $val" -ForegroundColor Gray
                }
                $propCount++
            }
        }
    } else {
        $lines = $Content -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
        $lines | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    Write-Host ("-" * 60) -ForegroundColor Gray
    Write-Host ""
}

# --- Window Title ---
$host.UI.RawUI.WindowTitle = "Vorce CEO: $PhaseName"

# --- Banner ---
Write-Host " [VORCE CEO] Phase: $PhaseName | Provider: $ProviderName" -ForegroundColor Magenta
Write-Host " $(Get-Date -Format 'HH:mm:ss') | Mode: $(if (-not [string]::IsNullOrWhiteSpace($ModelName)) { $ModelName } else { 'default' })" -ForegroundColor DarkGray
Write-Host ("-" * 60) -ForegroundColor DarkGray

# --- Read CLI args from file ---
if (-not (Test-Path -LiteralPath $CliArgsFile)) {
    $errMsg = "CLI-Args-Datei nicht gefunden: $CliArgsFile"
    Write-Host "[FEHLER] $errMsg" -ForegroundColor Red
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    Read-Host "Druecke Enter zum Schliessen"
    exit 1
}

$rawCliArgs = @(Get-Content -LiteralPath $CliArgsFile -Raw -Encoding UTF8 | ConvertFrom-Json)
$promptText = if (Test-Path $PromptFile) { Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 } else { "" }

# Replace placeholder with actual prompt
$finalArgs = @()
foreach ($arg in $rawCliArgs) {
    if ($arg -eq "__V_PROMPT__") {
        $finalArgs += $promptText
    } else {
        $finalArgs += $arg
    }
}

# --- Resolve CLI command ---
$cmdInfo = Get-Command $CliCommand -ErrorAction SilentlyContinue
if (-not $cmdInfo) {
    $errMsg = "CLI-Befehl '$CliCommand' nicht gefunden."
    Write-Host "[FEHLER] $errMsg" -ForegroundColor Red
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    Read-Host "Druecke Enter zum Schliessen"
    exit 1
}

# --- Change to working directory ---
if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
    Set-Location -LiteralPath $WorkingDirectory
}

Write-Host "[CEO] Starte $ProviderName..." -ForegroundColor Green
Write-Host ""

# --- Execute CLI command with live output + file capture ---
$exitCode = 0
try {
    $errorLogFile = $OutputFile + ".err.log"

    # Execute and stream output. Codex receives the prompt via stdin to avoid
    # Windows command-line length limits in visible CEO phases.
    if ($ProviderName -eq "codex_orchestrator" -and ($finalArgs -contains "-")) {
        $promptText | & $CliCommand @finalArgs 2> $errorLogFile | Tee-Object -FilePath $OutputFile
    } else {
        & $CliCommand @finalArgs 2> $errorLogFile | Tee-Object -FilePath $OutputFile
    }

    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }

    # Robustness check: if output contains JSON but exit code is non-zero (common in some CLI tools)
    if ($exitCode -ne 0) {
        $outContent = Get-Content -LiteralPath $OutputFile -Raw -ErrorAction SilentlyContinue
        if ($outContent -match '(?s)\{.*\}' -or $outContent -match '```json') {
            $exitCode = 0
        }
    }
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "[CEO] FEHLER: $errMsg" -ForegroundColor Red
    Add-Content -Path $OutputFile -Value "`nFEHLER: $errMsg" -Encoding UTF8
    $exitCode = 1
}

# --- Write exit code ---
Set-Content -Path $StatusFile -Value "$exitCode" -Encoding UTF8

# --- Footer ---
if ($exitCode -eq 0) {
    if (Test-Path -LiteralPath $OutputFile) {
        $content = Get-Content -LiteralPath $OutputFile -Raw -Encoding UTF8
        Show-CeoPhaseSummary -Content $content -Phase $PhaseName
    }
    Write-Host "[OK] Phase abgeschlossen." -ForegroundColor Green
    Start-Sleep -Seconds 3
} else {
    Write-Host "[FEHLER] Phase fehlgeschlagen (Exit: $exitCode)." -ForegroundColor Red
    if (Test-Path -LiteralPath $OutputFile) {
        Write-Host "--- LOG ---" -ForegroundColor DarkRed
        Get-Content -LiteralPath $OutputFile -Tail 20 | Write-Host -ForegroundColor DarkRed
    }
    Read-Host "Druecke Enter zum Schliessen"
}

exit $exitCode
