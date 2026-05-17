# scripts/codex-cli/tools/run-visible-codex-session.ps1
# Runs a visible interactive Codex TUI session for scheduled Autopilot planning.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptPath,
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string]$SessionId,
    [string]$LogPath,
    [string]$StatusPath,
    [switch]$NonInteractiveExec
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

function Write-VisibleSessionLog {
    param([Parameter(Mandatory)][string]$Message)
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    $line = "{0} {1}" -f (Get-Date -Format o), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $PromptPath)) {
    throw "Prompt file not found: $PromptPath"
}

$prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
$codex = Get-Command codex -ErrorAction Stop

Set-Location -LiteralPath $RepositoryRoot
$host.UI.RawUI.WindowTitle = if ($NonInteractiveExec.IsPresent) { "Vorce Autopilot Codex Monitoring" } else { "Vorce Autopilot Codex Planning" }
Write-Host "=====================================" -ForegroundColor Green
if ($NonInteractiveExec.IsPresent) {
    Write-Host " VORCE AUTOPILOT MONITORING SESSION" -ForegroundColor Green
} else {
    Write-Host " VORCE AUTOPILOT PLANNING SESSION" -ForegroundColor Green
}
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Model: $Model" -ForegroundColor Cyan
Write-Host "Repository: $RepositoryRoot" -ForegroundColor Cyan
if ($NonInteractiveExec.IsPresent -and -not [string]::IsNullOrWhiteSpace($SessionId)) {
    Write-Host "Resume Exec Session: $SessionId" -ForegroundColor Cyan
} elseif ($NonInteractiveExec.IsPresent) {
    Write-Host "New Exec Session" -ForegroundColor Cyan
} elseif (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    Write-Host "Resume Interactive Session: $SessionId" -ForegroundColor Cyan
} else {
    Write-Host "New Interactive Planning Session" -ForegroundColor Cyan
}
if (-not [string]::IsNullOrWhiteSpace($StatusPath)) {
    Write-Host "Status: $StatusPath" -ForegroundColor DarkGray
}
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

Write-VisibleSessionLog "START model=$Model session_id=$SessionId"

$args = @("--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "--no-alt-screen")
if ($NonInteractiveExec.IsPresent) {
    $args = @("exec", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "-")
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $args = @("exec", "resume", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, $SessionId, "-")
    }
} elseif (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $args = @("resume", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "--no-alt-screen", $SessionId)
}

try {
    if ($NonInteractiveExec.IsPresent) {
        $prompt | & $codex.Source @args
    } else {
        & $codex.Source @args $prompt
    }
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    Write-VisibleSessionLog "EXIT code=$exitCode"
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "[VORCE] Codex Planning Session failed with exit code $exitCode." -ForegroundColor Red
        Write-Host "[VORCE] Log: $LogPath" -ForegroundColor Yellow
        Read-Host "Press Enter to close this Codex window"
    }
    exit $exitCode
} catch {
    Write-VisibleSessionLog "ERROR $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[VORCE] Codex Planning Session threw an exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "[VORCE] Log: $LogPath" -ForegroundColor Yellow
    Read-Host "Press Enter to close this Codex window"
    exit 1
}
