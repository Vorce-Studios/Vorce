# StatusPrinter.ps1 (Vorce 3.0)
# Zentrales Modul für transparente und informative Terminal-Ausgaben

$script:Colors = @{
    Main = "Cyan"
    Sub  = "Yellow"
    Part = "White"
}

$script:RunIcons = @{
    Main = "H"
    Sub  = "S"
    Part = "P"
}

function Write-VorceHeader {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle = "",
        [string]$Icon = "!",
        [ConsoleColor]$Color = "Cyan"
    )
    $lineWidth = if ($Subtitle) { 70 } else { 60 }
    $line = "=" * $lineWidth

    Write-Host ""
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host "  $Icon $Title" -ForegroundColor $Color
    if ($Subtitle) { Write-Host "  -- $Subtitle" -ForegroundColor $Color }
    Write-Host "  $line" -ForegroundColor $Color
}

function Write-VorceRunStart {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][ValidateSet("Main", "Sub", "Part")]$Level,
        [int]$Index = 0,
        [int]$Total = 0
    )
    $icon = $script:RunIcons[$Level]
    $color = $script:Colors[$Level]
    $indent = switch($Level) { "Main" { "" } ; "Sub" { "  " } ; "Part" { "    " } }
    $counter = if ($Total -gt 0) { " [$Index/$Total]" } else { "" }
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host ""
    Write-Host "${indent}+-- $icon START $RunName$counter [$ts]" -ForegroundColor $color
}

function Write-VorceRunEnd {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][ValidateSet("Main", "Sub", "Part")]$Level,
        [ValidateSet("completed", "failed")]$Status = "completed",
        [int]$DurationMs = 0
    )
    $color = if ($Status -eq "completed") { "Green" } else { "Red" }
    $icon = $script:RunIcons[$Level]
    $indent = switch($Level) { "Main" { "" } ; "Sub" { "  " } ; "Part" { "    " } }
    $ts = Get-Date -Format "HH:mm:ss"
    $duration = if ($DurationMs -gt 0) { " (${DurationMs}ms)" } else { "" }
    Write-Host "${indent}+-- $icon END $RunName [$ts]${duration}" -ForegroundColor $color
}

function Write-VorceStep {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "RUN", "OK", "WARN", "ERROR")]$Status = "INFO",
        [int]$Current = 0,
        [int]$Total = 0,
        [string]$LevelPrefix = ""
    )
    $statusIndicator = switch($Status) {
        "RUN"   { "[ >>> ]" }
        "OK"    { "[ OK  ]" }
        "WARN"  { "[ !!  ]" }
        "ERROR" { "[ XX  ]" }
        default { "[ --  ]" }
    }
    $color = switch($Status) {
        "RUN"   { "Cyan" }
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    $progress = if ($Total -gt 0) { " [$Current/$Total]" } else { "" }
    $statusCol = "$statusIndicator".PadRight(10)
    Write-Host "  $LevelPrefix $statusCol $Message$progress" -ForegroundColor $color
}

function Write-VorceDivider {
    param([ConsoleColor]$Color = "DarkGray", [string]$Style = "single")
    $line = switch($Style) { "single" { "-" * 70 } ; default { "=" * 70 } }
    Write-Host ""
    Write-Host "  $line" -ForegroundColor $Color
}

function Write-VorceFooter {
    param([string]$Message = "Abgeschlossen", [ConsoleColor]$Color = "Cyan", [ValidateSet("completed", "failed")]$Status = "completed")
    $icon = if ($Status -eq "completed") { "OK" } else { "ERR" }
    $line = "=" * 60
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host ""
    Write-Host "  $icon $Message [$ts]" -ForegroundColor $Color
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host ""
}

# Ende StatusPrinter
