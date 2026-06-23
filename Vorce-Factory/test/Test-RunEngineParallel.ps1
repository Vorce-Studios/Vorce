[CmdletBinding()]
param(
    [switch]$InjectDuplicateMarker
)

$passCount = 0
$totalChecks = 0

function Write-TestResult {
    param([string]$Message, [bool]$Passed)
    $status = if ($Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Host "$status $Message"
    if ($Passed) { $script:passCount++ }
    $script:totalChecks++
}

function Get-LiteralOccurrenceCount {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Marker
    )

    return ([regex]::Matches($Text, [regex]::Escape($Marker))).Count
}

function Write-MarkerExactlyOnceResult {
    param(
        [Parameter(Mandatory)][string]$TerminalText,
        [Parameter(Mandatory)][string]$Marker,
        [Parameter(Mandatory)][string]$Description
    )

    $occurrenceCount = Get-LiteralOccurrenceCount -Text $TerminalText -Marker $Marker
    Write-TestResult "$Description erscheint exakt einmal (gefunden: $occurrenceCount)" ($occurrenceCount -eq 1)
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$tempVarDir = Join-Path $projectRoot 'var/tmp/test-runengine-parallel'

if (Test-Path $tempVarDir) {
    Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
}

$null = New-Item -ItemType Directory -Path $tempVarDir -Force

$global:VorceRoot = $projectRoot
$global:VarDir = $tempVarDir
$global:LibDir = Join-Path $projectRoot 'src/lib'

. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'state/StateManager.ps1')
. (Join-Path $global:LibDir 'engines/RunEngine.ps1')

$fixtureDir = Join-Path $tempVarDir 'fixtures'
$null = New-Item -ItemType Directory -Path $fixtureDir -Force

function New-VorceParallelFixture {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [switch]$EmitFinalState,
        [switch]$DuplicateFirstMarker
    )

    $fixtureMarkers = @(
        "FIXTURE_${Name}_TEXT_MARKER_1",
        "FIXTURE_${Name}_TEXT_MARKER_2"
    )

    $lines = @(
        'param([hashtable]$ConfigBag)'
        "Write-Host '$($fixtureMarkers[0])'"
        "Write-Host '$($fixtureMarkers[1])'"
    )

    if ($DuplicateFirstMarker) {
        $lines += "Write-Host '$($fixtureMarkers[0])'"
    }

    if ($EmitFinalState) {
        $lines += @(
            '[pscustomobject]@{'
            '    schema_version = 2'
            "    id = '$([guid]::NewGuid().ToString('N'))'"
            "    name = '$Name'"
            "    type = 'PART'"
            "    status = 'completed'"
            '}'
        )
    }

    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Path
}

$fixture1 = New-VorceParallelFixture -Name 'Alpha' -Path (Join-Path $fixtureDir 'Alpha.ps1') -EmitFinalState -DuplicateFirstMarker:$InjectDuplicateMarker
$fixture2 = New-VorceParallelFixture -Name 'Beta' -Path (Join-Path $fixtureDir 'Beta.ps1') -EmitFinalState
$fixture3 = New-VorceParallelFixture -Name 'Gamma' -Path (Join-Path $fixtureDir 'Gamma.ps1') -EmitFinalState
$missingFixture = New-VorceParallelFixture -Name 'Delta' -Path (Join-Path $fixtureDir 'Delta.ps1')

$configBag = @{
    Config = [pscustomobject]@{
        run_settings = [pscustomobject]@{
            sub_runs = [pscustomobject]@{
                ParallelFixture = [pscustomobject]@{ max_parallel = 2 }
                MissingFixture = [pscustomobject]@{ max_parallel = 1 }
            }
            part_runs = [pscustomobject]@{}
        }
    }
}

$parentState = [pscustomobject]@{
    schema_version = 2
    id = 'main-test-001'
    main_run_id = 'main-test-001'
    parent_run_id = $null
    name = 'MAIN-RUN-Test'
    type = 'MAIN'
    status = 'running'
    started_at = (Get-Date).AddMinutes(-10).ToString('o')
    completed_at = $null
    duration_ms = $null
    input_fingerprint = $null
    metadata = @{}
    results = @()
}

$parallelParts = @(
    [pscustomobject]@{ name = 'Alpha'; script = $fixture1; arguments = @{} },
    [pscustomobject]@{ name = 'Beta'; script = $fixture2; arguments = @{} },
    [pscustomobject]@{ name = 'Gamma'; script = $fixture3; arguments = @{} }
)

$parallelTerminalOutput = @()
$parallelResult = Invoke-VorceSubRunParallel `
    -SubRunName 'ParallelFixture' `
    -PartRuns $parallelParts `
    -ParentState $parentState `
    -ConfigBag $configBag `
    -MaxParallel 2 `
    -InformationVariable parallelTerminalOutput

$parallelTerminalText = @($parallelTerminalOutput | ForEach-Object { [string]$_ }) -join "`n"

$parallelFinalStates = @($parallelResult.parts | Where-Object { Test-VorceFinalStateObject -InputObject $_ })
$parallelNames = @($parallelFinalStates | ForEach-Object { $_.name })

Write-TestResult 'Drei finale Objekte im Sub-Aggregat' ($parallelFinalStates.Count -eq 3)
Write-TestResult 'Jedes finale Objekt genau einmal' ((@($parallelNames | Sort-Object -Unique).Count -eq 3) -and ($parallelNames.Count -eq 3))
Write-TestResult 'Sub-Run nicht als fehlgeschlagen markiert' ($parallelResult.status -eq 'completed')

foreach ($fixtureName in @('Alpha', 'Beta', 'Gamma')) {
    foreach ($markerIndex in 1..2) {
        $fixtureMarker = "FIXTURE_${fixtureName}_TEXT_MARKER_$markerIndex"
        Write-MarkerExactlyOnceResult `
            -TerminalText $parallelTerminalText `
            -Marker $fixtureMarker `
            -Description "$fixtureName Fixture-Textmarker $markerIndex"
    }

    $lifecycleMarkers = [ordered]@{
        'Queue-Startmarker' = "Queue -> Job: $fixtureName"
        'PART-Startmarker' = "P START $fixtureName"
        'PART-Ausfuehrungsmarker' = "Fuehre Part-Run aus: $fixtureName"
        'PART-Abschlussmarker' = "Part-Run $fixtureName abgeschlossen."
        'PART-Endmarker' = "P END $fixtureName"
        'Job-Abschlussmarker' = "Job abgeschlossen: $fixtureName"
    }

    foreach ($lifecycleMarker in $lifecycleMarkers.GetEnumerator()) {
        Write-MarkerExactlyOnceResult `
            -TerminalText $parallelTerminalText `
            -Marker $lifecycleMarker.Value `
            -Description "$fixtureName $($lifecycleMarker.Key)"
    }
}

$missingResult = Invoke-VorceSubRunParallel `
    -SubRunName 'MissingFixture' `
    -PartRuns @([pscustomobject]@{ name = 'Delta'; script = $missingFixture; arguments = @{} }) `
    -ParentState $parentState `
    -ConfigBag $configBag `
    -MaxParallel 1 `
    -JobFactory {
        param($part, $pConfigBag, $pParentState, $pLibDir, $pVarDir, $pRoot)

        Start-Job -Name $part.name -ScriptBlock {
            param($scriptPath, $arguments, $libDir, $varDir, $root, $configBag, $parentState)

            $global:VorceRoot = $root
            $global:VarDir = $varDir
            $global:LibDir = $libDir

            . (Join-Path $libDir 'utils/StatusPrinter.ps1')
            . (Join-Path $libDir 'state/StateManager.ps1')
            . (Join-Path $libDir 'engines/RunEngine.ps1')

            & $scriptPath @arguments | Out-Null
            return $null
        } -ArgumentList $part.script, $part.arguments, $pLibDir, $pVarDir, $pRoot, $pConfigBag, $pParentState
    }

$missingPart = @($missingResult.parts)[0]
Write-TestResult 'Fixture ohne finales Objekt wird als failed gespeichert' ($missingPart.status -eq 'failed' -and $missingPart.error_class -eq 'missing_final_state')
Write-TestResult 'Sub-Run ohne finales Objekt wird als failed markiert' ($missingResult.status -eq 'failed')

Write-Host "`nErgebnis: $passCount/$totalChecks Checks bestanden"

$exitCode = if ($passCount -eq $totalChecks) { 0 } else { 1 }

if (Test-Path $tempVarDir) {
    Remove-Item -LiteralPath $tempVarDir -Recurse -Force -ErrorAction SilentlyContinue
}

exit $exitCode
