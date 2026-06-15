# scripts/codex-cli/tools/run-hidden-ceo-phase.ps1
# Runs a single CEO deliberation phase in a HIDDEN process.
# Loads $PROFILE to ensure custom commands like gemini_cli are available.
# Writes a debug log to var/log/deliberations for troubleshooting.
#
# Used by deliberation-engine.ps1 to make CEO sessions non-interactive.

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

# --- Debug log directory ---
$scriptDir = Split-Path -Parent $PSCommandPath
$delibLogDir = Join-Path $scriptDir "../../../var/log/deliberations"
if (-not (Test-Path $delibLogDir)) { New-Item -ItemType Directory -Path $delibLogDir -Force | Out-Null }
$debugLogFile = Join-Path $delibLogDir "CEO-debug-$(Get-Date -Format 'HHmmss-fff').log"
function Write-Debug { param([string]$Msg); $Msg | Add-Content -Path $debugLogFile }

Write-Debug "=== CEO Phase Debug Log ==="
Write-Debug "Phase: $PhaseName"
Write-Debug "Provider: $ProviderName"
Write-Debug "Model: $ModelName"
Write-Debug "CliCommand: $CliCommand"
Write-Debug "CliArgsFile: $CliArgsFile"
Write-Debug "OutputFile: $OutputFile"
Write-Debug "StatusFile: $StatusFile"
Write-Debug "PromptFile: $PromptFile"
Write-Debug "WorkingDirectory: $WorkingDirectory"

# --- Read CLI args from file ---
if (-not (Test-Path -LiteralPath $CliArgsFile)) {
    $errMsg = "CLI-Args-Datei nicht gefunden: $CliArgsFile"
    Write-Debug "[ERROR] $errMsg"
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    exit 1
}

$cliArgs = @(Get-Content -LiteralPath $CliArgsFile -Raw -Encoding UTF8 | ConvertFrom-Json)
Write-Debug "CliArgs loaded: $($cliArgs.Count) args"

# --- Load $PROFILE to ensure custom commands are available ---
$profilePath = $PROFILE
if (-not [string]::IsNullOrWhiteSpace($profilePath) -and (Test-Path -LiteralPath $profilePath)) {
    try {
        . $profilePath
        Write-Debug "Profile loaded: $profilePath"
    } catch {
        Write-Debug "[WARNING] Could not load profile: $_"
    }
} else {
    Write-Debug "No profile found at: $profilePath"
}

# --- Resolve CLI command again after loading profile ---
$cmdInfo = Get-Command $CliCommand -ErrorAction SilentlyContinue
if (-not $cmdInfo) {
    $errMsg = "CLI-Befehl '$CliCommand' nicht gefunden nach Laden des Profile. Ist er installiert und im PATH?"
    Write-Debug "[ERROR] $errMsg"
    Set-Content -Path $OutputFile -Value $errMsg -Encoding UTF8
    Set-Content -Path $StatusFile -Value "1" -Encoding UTF8
    exit 1
}
Write-Debug "CLI command resolved: $($cmdInfo.Source)"

# --- Change to working directory ---
if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path $WorkingDirectory)) {
    Set-Location -LiteralPath $WorkingDirectory
    Write-Debug "Working directory changed to: $WorkingDirectory"
}

# --- Execute CLI command (no visible window) ---
$exitCode = 0
try {
    $hasPromptFile = -not [string]::IsNullOrWhiteSpace($PromptFile) -and (Test-Path $PromptFile)
    Write-Debug "HasPromptFile: $hasPromptFile"

    $cliBaseName = [System.IO.Path]::GetFileNameWithoutExtension($CliCommand).ToLower()
    $needsPromptArg = $cliBaseName -in @("gemini", "claude")
    Write-Debug "cliBaseName: $cliBaseName, needsPromptArg: $needsPromptArg"

    $useStdinPipe = $false
    if ($hasPromptFile -and $needsPromptArg) {
        $promptText = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8
        $promptBytes = [System.Text.Encoding]::UTF8.GetByteCount($promptText)
        Write-Debug "PromptFile content loaded: $promptBytes bytes"
        if ($promptBytes -gt 30000) {
            $useStdinPipe = $true
            $cliArgs += @("-p", ".")
            Write-Debug "Using stdin pipe for long prompt"
        } else {
            $cliArgs += @("-p", $promptText)
            Write-Debug "Prompt added as -p argument"
        }
    } elseif ($hasPromptFile -and -not $needsPromptArg) {
        $promptText = Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8
        $cliArgs += @($promptText)
        Write-Debug "Prompt added as positional argument"
    } else {
        Write-Debug "No prompt file or no needsPromptArg"
    }

    $errorLogFile = $OutputFile + ".err.log"
    Write-Debug "Running: $CliCommand with args: $($cliArgs -join ' ')"

    if ($useStdinPipe) {
        Get-Content -LiteralPath $PromptFile -Raw -Encoding UTF8 | & $CliCommand @cliArgs 2> $errorLogFile | Set-Content -Path $OutputFile -Encoding UTF8
    } else {
        & $CliCommand @cliArgs 2> $errorLogFile | Set-Content -Path $OutputFile -Encoding UTF8
    }

    $exitCode = $LASTEXITCODE
    Write-Debug "Exit code: $exitCode"

    if (Test-Path $errorLogFile) {
        $errContent = Get-Content -LiteralPath $errorLogFile -Raw -Encoding UTF8
        Write-Debug "Error log content: $errContent"
    }

    if (Test-Path $OutputFile) {
        $outContent = Get-Content -LiteralPath $OutputFile -Raw -Encoding UTF8
        Write-Debug "Output file content (first 500 chars): $($outContent.Substring(0, [Math]::Min(500, $outContent.Length)))"
    }

} catch {
    $errMsg = $_.Exception.Message
    Write-Debug "[ERROR] $_"
    Add-Content -Path $OutputFile -Value "`nFEHLER: $errMsg" -Encoding UTF8
    $exitCode = 1
}

# --- Write exit code ---
Set-Content -Path $StatusFile -Value "$exitCode" -Encoding UTF8
Write-Debug "=== End of CEO Phase Debug Log ==="

exit $exitCode
