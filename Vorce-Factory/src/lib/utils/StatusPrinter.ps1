# StatusPrinter.ps1 (Vorce 3.0)
# Central terminal output with exactly one structured event per run boundary.

$loggingModule = Join-Path $PSScriptRoot '..\logging\Write-Log.ps1'
if (-not (Get-Command Write-VorceLogEntry -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $loggingModule)) {
    . $loggingModule
}

$script:Colors = @{
    Main = 'Cyan'
    Sub = 'Yellow'
    Part = 'White'
}

$script:RunIcons = @{
    Main = 'H'
    Sub = 'S'
    Part = 'P'
}

if ($null -eq $global:VorceStatusRunContexts) {
    $global:VorceStatusRunContexts = @{}
}

function Get-VorceStatusRunKey {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$Level
    )

    return ('{0}|{1}' -f $Level, $RunName).ToLowerInvariant()
}

function Add-VorceStatusRunContext {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][object]$Context
    )

    $key = Get-VorceStatusRunKey -RunName $RunName -Level $Level
    $stack = @($global:VorceStatusRunContexts[$key])
    $global:VorceStatusRunContexts[$key] = @($stack + @($Context))
}

function Remove-VorceStatusRunContext {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][string]$Level
    )

    $key = Get-VorceStatusRunKey -RunName $RunName -Level $Level
    $stack = @($global:VorceStatusRunContexts[$key])
    if ($stack.Count -eq 0) {
        return $null
    }

    $context = $stack[$stack.Count - 1]
    if ($stack.Count -eq 1) {
        $global:VorceStatusRunContexts.Remove($key)
    } else {
        $global:VorceStatusRunContexts[$key] = @($stack[0..($stack.Count - 2)])
    }

    return $context
}

function New-VorceStatusRunContext {
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][ValidateSet('Main', 'Sub', 'Part')][string]$Level,
        [Alias('Context')][object]$RunContext,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$RunId,
        [string]$ParentRunId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$Component
    )

    if ($RunContext) {
        return $RunContext
    }

    $runType = $Level.ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($Component)) {
        $Component = if ($Level -eq 'Main') { 'orchestrator' } else { 'run-engine' }
    }

    return New-VorceRunContext `
        -RunType $runType `
        -RunName $RunName `
        -SessionId $SessionId `
        -CorrelationId $CorrelationId `
        -RunId $RunId `
        -ParentRunId $ParentRunId `
        -MainRunId $MainRunId `
        -SubRunId $SubRunId `
        -PartRunId $PartRunId `
        -Component $Component
}

function Write-VorceHeader {
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle = '',
        [string]$Icon = '!',
        [ConsoleColor]$Color = 'Cyan'
    )

    $lineWidth = if ($Subtitle) { 70 } else { 60 }
    $line = '=' * $lineWidth

    Write-Host ''
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host "  $Icon $Title" -ForegroundColor $Color
    if ($Subtitle) {
        Write-Host "  -- $Subtitle" -ForegroundColor $Color
    }
    Write-Host "  $line" -ForegroundColor $Color
}

function Write-VorceRunStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][ValidateSet('Main', 'Sub', 'Part')][string]$Level,
        [int]$Index = 0,
        [int]$Total = 0,
        [Alias('Context')][object]$RunContext,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$RunId,
        [string]$ParentRunId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$Component,
        [object]$Data = @{},
        [switch]$PassThru
    )

    $context = New-VorceStatusRunContext `
        -RunName $RunName `
        -Level $Level `
        -RunContext $RunContext `
        -SessionId $SessionId `
        -CorrelationId $CorrelationId `
        -RunId $RunId `
        -ParentRunId $ParentRunId `
        -MainRunId $MainRunId `
        -SubRunId $SubRunId `
        -PartRunId $PartRunId `
        -Component $Component
    Add-VorceStatusRunContext -RunName $RunName -Level $Level -Context $context

    $icon = $script:RunIcons[$Level]
    $color = $script:Colors[$Level]
    $indent = switch ($Level) {
        'Main' { '' }
        'Sub' { '  ' }
        'Part' { '    ' }
    }
    $counter = if ($Total -gt 0) { " [$Index/$Total]" } else { '' }
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ''
    Write-Host "${indent}+-- $icon START $RunName$counter [$ts]" -ForegroundColor $color

    $eventData = [ordered]@{
        run_type = $Level.ToUpperInvariant()
        run_id = Get-VorceContextValue -Context $context -Name 'run_id'
        parent_run_id = Get-VorceContextValue -Context $context -Name 'parent_run_id'
        index = if ($Index -gt 0) { $Index } else { $null }
        total = if ($Total -gt 0) { $Total } else { $null }
        detail = $Data
    }
    $eventComponent = [string](Get-VorceContextValue -Context $context -Name 'component')
    $null = Write-VorceRunEvent -State started -Message "Run started: $RunName" -Context $context -Component $eventComponent -Data $eventData -SkipTerminal

    if ($PassThru) {
        return $context
    }
}

function Write-VorceRunEnd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunName,
        [Parameter(Mandatory)][ValidateSet('Main', 'Sub', 'Part')][string]$Level,
        [ValidateSet('completed', 'failed', 'skipped', 'reused', 'waiting_provider')][string]$Status = 'completed',
        [int]$DurationMs = 0,
        [Alias('Context')][object]$RunContext,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$RunId,
        [string]$ParentRunId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$Component,
        [object]$Data = @{},
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [switch]$PassThru
    )

    $storedContext = Remove-VorceStatusRunContext -RunName $RunName -Level $Level
    $context = if ($RunContext) {
        $RunContext
    } elseif ($storedContext) {
        $storedContext
    } else {
        New-VorceStatusRunContext `
            -RunName $RunName `
            -Level $Level `
            -SessionId $SessionId `
            -CorrelationId $CorrelationId `
            -RunId $RunId `
            -ParentRunId $ParentRunId `
            -MainRunId $MainRunId `
            -SubRunId $SubRunId `
            -PartRunId $PartRunId `
            -Component $Component
    }

    $color = switch ($Status) {
        'completed' { 'Green' }
        'reused' { 'Cyan' }
        'waiting_provider' { 'Yellow' }
        'skipped' { 'DarkYellow' }
        default { 'Red' }
    }
    $icon = $script:RunIcons[$Level]
    $indent = switch ($Level) {
        'Main' { '' }
        'Sub' { '  ' }
        'Part' { '    ' }
    }
    $ts = Get-Date -Format 'HH:mm:ss'
    $duration = if ($DurationMs -gt 0) { " (${DurationMs}ms)" } else { '' }
    Write-Host "${indent}+-- $icon END $RunName [$ts]${duration}" -ForegroundColor $color

    $eventData = [ordered]@{
        run_type = $Level.ToUpperInvariant()
        run_id = Get-VorceContextValue -Context $context -Name 'run_id'
        parent_run_id = Get-VorceContextValue -Context $context -Name 'parent_run_id'
        detail = $Data
    }
    $eventComponent = [string](Get-VorceContextValue -Context $context -Name 'component')
    $null = Write-VorceRunEvent -State $Status -Message "Run $Status`: $RunName" -Context $context -Component $eventComponent -Data $eventData -DurationMs $DurationMs -ErrorRecord $ErrorRecord -ErrorClass $ErrorClass -SkipTerminal

    if ($PassThru) {
        return $context
    }
}

function Write-VorceStep {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'RUN', 'OK', 'WARN', 'ERROR')][string]$Status = 'INFO',
        [int]$Current = 0,
        [int]$Total = 0,
        [string]$LevelPrefix = ''
    )

    $statusIndicator = switch ($Status) {
        'RUN' { '[ >>> ]' }
        'OK' { '[ OK  ]' }
        'WARN' { '[ !!  ]' }
        'ERROR' { '[ XX  ]' }
        default { '[ --  ]' }
    }
    $color = switch ($Status) {
        'RUN' { 'Cyan' }
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'White' }
    }
    $progress = if ($Total -gt 0) { " [$Current/$Total]" } else { '' }
    $statusCol = "$statusIndicator".PadRight(10)
    Write-Host "  $LevelPrefix $statusCol $Message$progress" -ForegroundColor $color
}

function Write-VorceDivider {
    param(
        [ConsoleColor]$Color = 'DarkGray',
        [string]$Style = 'single'
    )

    $line = switch ($Style) {
        'single' { '-' * 70 }
        default { '=' * 70 }
    }
    Write-Host ''
    Write-Host "  $line" -ForegroundColor $Color
}

function Write-VorceFooter {
    param(
        [string]$Message = 'Abgeschlossen',
        [ConsoleColor]$Color = 'Cyan',
        [ValidateSet('completed', 'failed', 'skipped', 'reused', 'waiting_provider')][string]$Status = 'completed'
    )

    $icon = switch ($Status) {
        'completed' { 'OK' }
        'reused' { 'REUSED' }
        'waiting_provider' { 'WAIT' }
        'skipped' { 'SKIP' }
        default { 'ERR' }
    }
    $line = '=' * 60
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ''
    Write-Host "  $icon $Message [$ts]" -ForegroundColor $Color
    Write-Host "  $line" -ForegroundColor $Color
    Write-Host ''
}
