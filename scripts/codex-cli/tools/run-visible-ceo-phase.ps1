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

    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor Gray
    Write-Host "  ZUSAMMENFASSUNG DER CEO-PHASE: $Phase" -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor Gray

    if ($null -ne $parsed) {
        if ($parsed.PSObject.Properties.Name -contains "assessment") {
            Write-Host "  Bewertung:    $($parsed.assessment)" -ForegroundColor Gray
            Write-Host "  Empfehlung:   $($parsed.recommendation)" -ForegroundColor $(if ($parsed.recommendation -eq "approve") { "Green" } else { "Yellow" })
            if ($parsed.PSObject.Properties.Name -contains "strengths") {
                Write-Host "  Stärken:" -ForegroundColor Cyan
                foreach ($s in $parsed.strengths) { Write-Host "    - $s" -ForegroundColor Gray }
            }
            if ($parsed.PSObject.Properties.Name -contains "weaknesses" -and $parsed.weaknesses.Count -gt 0) {
                Write-Host "  Schwächen:" -ForegroundColor Yellow
                foreach ($w in $parsed.weaknesses) { Write-Host "    - $w" -ForegroundColor Gray }
            }
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
            # Generic JSON formatting
            $parsed.PSObject.Properties | ForEach-Object {
                $name = $_.Name
                $val = $_.Value
                $displayName = @($name -split '_' | ForEach-Object { 
                    if ($_.Length -gt 0) { $_.Substring(0,1).ToUpper() + $_.Substring(1) } else { "" }
                }) -join " "
                
                if ($val -is [System.Array] -or $val -is [System.Collections.IList]) {
                    Write-Host "  $displayName`:" -ForegroundColor Cyan
                    foreach ($v in $val) { Write-Host "    - $v" -ForegroundColor Gray }
                } else {
                    Write-Host "  $displayName`: $val" -ForegroundColor Gray
                }
            }
        }
    } else {
        # Clean plain text
        $lines = $Content -split "`r?`n" | Where-Object {
            $_ -notmatch '^Warning: 256-color' -and
            $_ -notmatch '^YOLO mode is enabled' -and
            $_ -notmatch '^Ripgrep is not available'
        }
        $lines | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        if ($lines.Count -gt 15) { Write-Host "  ... (weitere $($lines.Count - 15) Zeilen)" -ForegroundColor DarkGray }
    }
    Write-Host ("-" * 60) -ForegroundColor Gray
    Write-Host ""
}

# --- Window Title ---
$host.UI.RawUI.WindowTitle = "Vorce CEO: $PhaseName"

# --- Banner ---
Write-Host "" -ForegroundColor White
Write-Host "======================================================" -ForegroundColor Magenta
Write-Host "  VORCE AUTOPILOT - CEO SESSION" -ForegroundColor Magenta
Write-Host "======================================================" -ForegroundColor Magenta
Write-Host "  Phase:    $PhaseName" -ForegroundColor Cyan
Write-Host "  Provider: $ProviderName" -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
    Write-Host "  Model:    $ModelName" -ForegroundColor Cyan
}
Write-Host "  Command:  $CliCommand" -ForegroundColor DarkGray
Write-Host "  Output:   $OutputFile" -ForegroundColor DarkGray
Write-Host "  Zeit:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "======================================================" -ForegroundColor Magenta
Write-Host ""

# --- Read CLI args from file ---
if (-not (Test-Path -LiteralPath $CliArgsFile)) {
    $errMsg = "CLI-Args-Datei nicht gefunden: $CliArgsFile"
    Write-Host "[FEHLER] $errMsg" -ForegroundColor Red
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    Read-Host "Druecke Enter zum Schliessen"
    exit 1
}

$cliArgs = @(Get-Content -LiteralPath $CliArgsFile -Raw -Encoding UTF8 | ConvertFrom-Json)

# --- Resolve CLI command ---
$cmdInfo = Get-Command $CliCommand -ErrorAction SilentlyContinue
if (-not $cmdInfo) {
    $errMsg = "CLI-Befehl '$CliCommand' nicht gefunden. Ist er installiert und im PATH?"
    Write-Host "[FEHLER] $errMsg" -ForegroundColor Red
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    Read-Host "Druecke Enter zum Schliessen"
    exit 1
}

$cmdSource = $cmdInfo.Source
# Keep original .ps1 or other command source. Forcing .cmd breaks multiline arguments due to Windows batch file limitations.

# --- Change to working directory ---
if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
    Set-Location -LiteralPath $WorkingDirectory
    Write-Host "[CEO] Arbeitsverzeichnis: $WorkingDirectory" -ForegroundColor DarkGray
}

Write-Host "[CEO] Starte $ProviderName Session..." -ForegroundColor Green
Write-Host "[CEO] Argumente: $($cliArgs.Count) Parameter" -ForegroundColor DarkGray
Write-Host ("=" * 50) -ForegroundColor DarkGray
Write-Host ""

# --- Execute CLI command with live output + file capture ---
$exitCode = 0
try {
    $hasPromptFile = -not [string]::IsNullOrWhiteSpace($PromptFile) -and (Test-Path $PromptFile)
    
    $cliBaseName = [System.IO.Path]::GetFileNameWithoutExtension($cmdSource).ToLower()
    $needsPromptArg = $cliBaseName -in @("gemini", "claude")

    if ($hasPromptFile -and $needsPromptArg) {
        $promptText = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8
        $cliArgs += @("-p", $promptText)
    }

    Write-Host "[CEO] Analysiere und verarbeite Phase...$(if ($needsPromptArg) { ' (Headless -p Modus)' } else { '' })" -ForegroundColor Cyan
    
    # Start transcript to capture output to file while still showing it in the visible terminal
    Start-Transcript -Path $OutputFile -Append:$false -Force | Out-Null
    
    if ($hasPromptFile -and -not $needsPromptArg) {
        Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 | & $cmdSource @cliArgs
    } else {
        & $cmdSource @cliArgs
    }
    
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    
    Stop-Transcript | Out-Null
} catch {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    $errMsg = $_.Exception.Message
    Write-Host ""
    Write-Host "[CEO] FEHLER: $errMsg" -ForegroundColor Red
    Add-Content -Path $OutputFile -Value "`nFEHLER: $errMsg" -Encoding UTF8
    $exitCode = 1
}

# --- Write exit code ---
Set-Content -Path $StatusFile -Value "$exitCode" -Encoding UTF8

# --- Footer ---
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
if ($exitCode -eq 0) {
    Write-Host "[CEO] Phase '$PhaseName' erfolgreich abgeschlossen." -ForegroundColor Green
    
    # Read output and show clean summary
    if (Test-Path -LiteralPath $OutputFile) {
        $content = Get-Content -LiteralPath $OutputFile -Raw -Encoding UTF8
        Show-CeoPhaseSummary -Content $content -Phase $PhaseName
    }
} else {
    Write-Host "[CEO] Phase '$PhaseName' fehlgeschlagen (Exit-Code: $exitCode)." -ForegroundColor Red
    
    # Print the raw error logs on failure so the user knows exactly what failed
    Write-Host ""
    Write-Host "--- FEHLERPROTOKOLL (RAW LOG) ---" -ForegroundColor Red
    if (Test-Path -LiteralPath $OutputFile) {
        Get-Content -LiteralPath $OutputFile -Raw -Encoding UTF8 | Write-Host -ForegroundColor DarkRed
    }
    Write-Host "---------------------------------" -ForegroundColor Red
}
Write-Host ("=" * 60) -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

# Keep window open for 5 seconds (or until Enter) on error so user can see diagnostics
if ($exitCode -ne 0) {
    Read-Host "Druecke Enter zum Schliessen"
} else {
    Write-Host "[CEO] Fenster schliesst in 5 Sekunden..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

exit $exitCode
