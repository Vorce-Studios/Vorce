# Vorce-Autopilot/src/lib/utils/logging-utils.ps1
# Global logging helpers for structured terminal output

Set-StrictMode -Version Latest

function Write-VorceStatus {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan,
        [string]$SubPhase = ""
    )
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $phaseStr = if ($SubPhase) { "$Phase/$SubPhase" } else { $Phase }
    $prefix = "[$timestamp] [$($phaseStr.PadRight(20))] "
    Write-Host "$prefix$Message" -ForegroundColor $Color
}

function Write-VorceBanner {
    param(
        [Parameter(Mandatory)][string]$Title,
        [ConsoleColor]$Color = [ConsoleColor]::Magenta
    )
    $line = "=" * 74
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host " >>> $Title" -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
    Write-Host ""
}
