# StatusPrinter.ps1 (Vorce 3.0)
# Zentrales Modul für transparente und informative Terminal-Ausgaben

function Write-VorceHeader {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Icon = "🚀",
        [ConsoleColor]$Color = "Cyan"
    )
    $Line = "=" * 60
    Write-Host "`n$Line" -ForegroundColor $Color
    Write-Host "  $Icon $Title" -ForegroundColor $Color
    Write-Host "$Line" -ForegroundColor $Color
}

function Write-VorceStep {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Status = "INFO", # INFO, RUN, OK, WARN, ERROR
        [int]$Current = 0,
        [int]$Total = 0
    )

    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $prefix = switch($Status) {
        "RUN"   { "[ >> ]" }
        "OK"    { "[ OK ]" }
        "WARN"  { "[ !! ]" }
        "ERROR" { "[ XX ]" }
        default { "[ -- ]" }
    }

    $color = switch($Status) {
        "RUN"   { "Cyan" }
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }

    $progress = ""
    if ($Total -gt 0) { $progress = " ($Current/$Total)" }

    Write-Host "[$timestamp] $prefix $Message$progress" -ForegroundColor $color
}

function Write-VorceDivider {
    param([ConsoleColor]$Color = "DarkGray")
    Write-Host ("-" * 60) -ForegroundColor $Color
}

function Write-VorceFooter {
    param(
        [string]$Message = "Abgeschlossen",
        [ConsoleColor]$Color = "Cyan"
    )
    $Line = "=" * 60
    Write-Host "  DONE: $Message" -ForegroundColor $Color
    Write-Host "$Line`n" -ForegroundColor $Color
}

# Ende StatusPrinter
