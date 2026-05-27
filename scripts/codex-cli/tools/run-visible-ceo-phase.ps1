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
    [string]$WorkingDirectory
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

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
    # Tee-Object writes to file AND passes through to console
    & $cmdInfo.Source @cliArgs 2>&1 | Tee-Object -FilePath $OutputFile
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
} catch {
    $errMsg = $_.Exception.Message
    Write-Host ""
    Write-Host "[CEO] FEHLER: $errMsg" -ForegroundColor Red
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    $exitCode = 1
}

# --- Write exit code ---
Set-Content -Path $StatusFile -Value "$exitCode" -Encoding UTF8

# --- Footer ---
Write-Host ""
Write-Host ("=" * 50) -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
if ($exitCode -eq 0) {
    Write-Host "[CEO] Phase '$PhaseName' erfolgreich abgeschlossen." -ForegroundColor Green
} else {
    Write-Host "[CEO] Phase '$PhaseName' fehlgeschlagen (Exit-Code: $exitCode)." -ForegroundColor Red
}
Write-Host "[CEO] Output gespeichert: $OutputFile" -ForegroundColor DarkGray
Write-Host ("=" * 50) -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })

# Keep window open for 5 seconds (or until Enter) so user can see result
if ($exitCode -ne 0) {
    Read-Host "Druecke Enter zum Schliessen"
} else {
    Write-Host "[CEO] Fenster schliesst in 5 Sekunden..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 5
}

exit $exitCode
