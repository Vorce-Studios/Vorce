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
    [string]$OutputPath,
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

$codexArgs = @("--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "--no-alt-screen")
if ($NonInteractiveExec.IsPresent) {
    $codexArgs = @("exec", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "-")
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $codexArgs = @("exec", "resume", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, $SessionId, "-")
    }
} elseif (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $codexArgs = @("resume", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--cd", $RepositoryRoot, "--no-alt-screen", $SessionId)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $codexArgs += @("--output-last-message", $OutputPath)
}

try {
    $isInsideCodex = $false
    
    $runCmd = if ($NonInteractiveExec.IsPresent) {
        { $prompt | & $codex.Source @codexArgs *>&1 }
    } else {
        { & $codex.Source @codexArgs $prompt *>&1 }
    }

    $isInsideCodex = $false
    $expectCommandLine = $false
    $isInsideCommandOutput = $false
    $commandCount = 0
    $thoughtCount = 0
    $startTime = Get-Date

    # Execute and pipe through line-by-line processing
    & $runCmd | ForEach-Object {
        $line = ""
        if ($null -ne $_) {
            $line = $_.ToString().Trim()
        }
        
        # Always write raw line to log path if specified
        if (-not [string]::IsNullOrWhiteSpace($LogPath) -and -not [string]::IsNullOrWhiteSpace($line)) {
            Add-Content -Path $LogPath -Value $line -Encoding UTF8
        }
        
        # Skip empty lines to keep terminal neat
        if ([string]::IsNullOrWhiteSpace($line)) {
            return
        }
        
        # State machine for live terminal filtering
        if ($line -eq "codex") {
            $isInsideCodex = $true
            $isInsideCommandOutput = $false
            $expectCommandLine = $false
            $thoughtCount++
            return
        }
        
        if ($line -eq "exec") {
            $isInsideCodex = $false
            $expectCommandLine = $true
            $isInsideCommandOutput = $false
            $commandCount++
            return
        }
        
        if ($expectCommandLine) {
            $expectCommandLine = $false
            $isInsideCommandOutput = $true
            
            # Clean up the command line to make it readable
            $cleanCmd = $line
            if ($line -match '-Command\s+''(.*)''\s+in\s+(.*)') {
                $cleanCmd = $Matches[1]
            } elseif ($line -match '-Command\s+"(.*)"\s+in\s+(.*)') {
                $cleanCmd = $Matches[1]
            }
            $cleanCmd = $cleanCmd.Trim('"', "'")
            Write-Host "[BEFEHL] Führe aus: $cleanCmd" -ForegroundColor Yellow
            return
        }
        
        if ($line -match '^\s*(succeeded|failed)\s+in\s+(\d+ms|seconds|minutes)' -or $line -match '^\s*exited\s+\d+') {
            $isInsideCommandOutput = $false
            if ($line -match 'failed' -or $line -match 'exited\s+[^0]') {
                Write-Host "[ERGEBNIS] Fehlgeschlagen ($($line.Trim()))" -ForegroundColor Red
            } else {
                Write-Host "[ERGEBNIS] Erfolgreich ($($line.Trim()))" -ForegroundColor Gray
            }
            return
        }
        
        if ($isInsideCommandOutput) {
            # Suppress all command output (stdout/stderr) from cluttering the terminal
            return
        }
        
        if ($isInsideCodex -and -not [string]::IsNullOrWhiteSpace($line)) {
            # Print the clean comment/thought in German
            Write-Host "[CEO ALPHA] $line" -ForegroundColor Cyan
        }
    }

    # Print a clean overview summary when the session ends
    $elapsed = (Get-Date) - $startTime
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " ZUSAMMENFASSUNG DER LAUFENDEN SESSION" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "Status:        Abgeschlossen" -ForegroundColor Green
    Write-Host "Dauer:         $("{0:N1}s" -f $elapsed.TotalSeconds)" -ForegroundColor Cyan
    Write-Host "Gedankengänge: $thoughtCount" -ForegroundColor Cyan
    Write-Host "Befehle:       $commandCount ausgeführt" -ForegroundColor Cyan
    Write-Host "Logdatei:      $LogPath" -ForegroundColor DarkGray
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""

    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    Write-VisibleSessionLog "EXIT code=$exitCode"
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Host "[VORCE] Codex Planning Session failed with exit code $exitCode." -ForegroundColor Red
        Write-Host "[VORCE] Log: $LogPath" -ForegroundColor Yellow
        if (-not $NonInteractiveExec.IsPresent) {
            Read-Host "Press Enter to close this Codex window"
        }
    }
    exit $exitCode
} catch {
    Write-VisibleSessionLog "ERROR $($_.Exception.Message)"
    Write-Host ""
    Write-Host "[VORCE] Codex Planning Session threw an exception:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "[VORCE] Log: $LogPath" -ForegroundColor Yellow
    if (-not $NonInteractiveExec.IsPresent) {
        Read-Host "Press Enter to close this Codex window"
    }
    exit 1
}
