# Test-RunTopology.ps1 (Vorce 3.0)
[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Split-Path -Parent $PSScriptRoot } else { $ProjectRoot }
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $PSScriptRoot 'RunTopology.Common.ps1')

$test = New-VorceTestContext -Name 'RunTopology'
$manifestPath = Join-Path $ProjectRoot 'web/Dashboard/src/run-topology.manifest.json'
$expectedTotals = [pscustomobject]@{
    main = 5
    sub = 17
    part = 18
}

function New-TopologyFixtureRoot {
    param(
        [Parameter(Mandatory)][string]$FixtureName
    )

    $fixtureRoot = Join-Path $ProjectRoot "var/tmp/test-run-topology/$FixtureName"
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'var') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'web/Dashboard/src') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'src/runs') -Destination (Join-Path $fixtureRoot 'src/runs') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'var/config') -Destination (Join-Path $fixtureRoot 'var/config') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'var/run-states') -Destination (Join-Path $fixtureRoot 'var/run-states') -Recurse -Force
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -Force
    return $fixtureRoot
}

function Assert-TopologyReport {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][object]$ExpectedTotals,
        [string]$MessagePrefix = 'Topologie'
    )

    Write-VorceTestResult -Context $test -Message "${MessagePrefix}: Report vorhanden" -Passed ($null -ne $Report)
    Write-VorceTestResult -Context $test -Message "${MessagePrefix}: exakt 5 MAIN-RUNs" -Passed (@($Report.main_runs).Count -eq $ExpectedTotals.main)
    Write-VorceTestResult -Context $test -Message "${MessagePrefix}: exakt 17 SUB-RUNs" -Passed ((@($Report.main_runs | ForEach-Object { @($_.sub_runs).Count }) | Measure-Object -Sum).Sum -eq $ExpectedTotals.sub)
    Write-VorceTestResult -Context $test -Message "${MessagePrefix}: exakt 18 PART-RUNs" -Passed ((@($Report.main_runs | ForEach-Object { $_.sub_runs } | ForEach-Object { @($_.parts).Count }) | Measure-Object -Sum).Sum -eq $ExpectedTotals.part)
    Write-VorceTestResult -Context $test -Message "${MessagePrefix}: keine kanonischen PART-States als Legacy-Orphans" -Passed (-not (@($Report.legacy_orphan_states | Where-Object { $_.source_file -like 'PART_PART-RUN-*' }).Count))
}

try {
    $report = Get-VorceRunTopologyReport -ProjectRoot $ProjectRoot -ManifestPath $manifestPath -ExpectedManifestPath $manifestPath

    Assert-TopologyReport -Report $report -ExpectedTotals $expectedTotals -MessagePrefix 'Soll'
    Write-VorceTestResult -Context $test -Message 'Validierung ohne Fehler' -Passed ($report.passed -eq $true)
    Write-VorceTestResult -Context $test -Message 'Keine Topologie-Fehler gemeldet' -Passed (@($report.errors).Count -eq 0)

    # Negativfixture 1: fehlender Router
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'missing-router'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1') -Force
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'Fehlender Router erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'Router')

    # Negativfixture 2: zusaetzlicher MAIN-RUN
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'extra-main'
    $extraMainDir = Join-Path $fixtureRoot 'src/runs/MAIN-RUN-06_Experimental'
    New-Item -ItemType Directory -Path $extraMainDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $extraMainDir 'Experimental-Router.ps1') -Value '# experimental router' -Encoding UTF8
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'Zusätzlicher MAIN-RUN erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'MAIN-RUN-06_Experimental')

    # Negativfixture 3: falscher Config-Scriptpfad
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'wrong-config-script'
    $configFile = Join-Path $fixtureRoot 'var/config/autopilot-config.json'
    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    $config.router_rules.Planning[0].script = 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/BROKEN/BROKEN.ps1'
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configFile -Encoding UTF8
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'Falscher Config-Scriptpfad erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'Konfigurationsregel')

    # Negativfixture 4: SUB ohne gleichnamige Skriptdatei
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'missing-sub-script'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-02_MR-01_Planning__Triage/SUB-RUN-02_MR-01_Planning__Triage.ps1') -Force
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'SUB ohne gleichnamige Skriptdatei erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'SUB-Skript fehlt oder ist falsch')

    # Negativfixture 5: PART mit falschem Parentnamen
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'wrong-part-parent'
    $partPath = Join-Path $fixtureRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-02_MR-01_Planning__Triage/PART-RUNS/PART-RUN-01_MR-01_Planning__Triage__FilterIssues.ps1'
    Rename-Item -LiteralPath $partPath -NewName 'PART-RUN-01_MR-01_Planning__WrongParent__FilterIssues.ps1'
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'PART mit falschem Parentnamen erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'PART-RUN fehlt')

    # Negativfixture 6: vorhandene, aber nicht intern registrierte PART-Datei
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'unregistered-part'
    $extraPartPath = Join-Path $fixtureRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-01_MR-01_Planning__DataSync/PART-RUNS/PART-RUN-99_MR-01_Planning__DataSync__Unregistered.ps1'
    Set-Content -LiteralPath $extraPartPath -Value '# unregistered part' -Encoding UTF8
    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath (Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json') -ExpectedManifestPath $manifestPath
    Write-VorceTestResult -Context $test -Message 'Nicht registrierte PART-Datei erkannt' -Passed (-not $fixtureReport.passed -and ($fixtureReport.errors -join "`n") -match 'Unerwartete PART-Datei|PART nicht intern registriert')

    # Negativfixture 7: BROKEN-ID im Manifest plus unbekannter PART_PART-RUN-State
    $fixtureRoot = New-TopologyFixtureRoot -FixtureName 'broken-part-id'
    $brokenManifestPath = Join-Path $fixtureRoot 'web/Dashboard/src/run-topology.manifest.json'
    $brokenManifest = Get-Content -LiteralPath $brokenManifestPath -Raw | ConvertFrom-Json
    $brokenManifest.main_runs[0].sub_runs[0].parts[0].id = 'BROKEN-ID'
    $brokenManifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $brokenManifestPath -Encoding UTF8

    $unknownPartStatePath = Join-Path $fixtureRoot 'var/run-states/PART_PART-RUN-99_MR-01_Planning__Strategy__CreateProposal.json'
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'var/run-states/PART_PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.json') -Destination $unknownPartStatePath -Force

    $fixtureReport = Get-VorceRunTopologyReport -ProjectRoot $fixtureRoot -ManifestPath $brokenManifestPath -ExpectedManifestPath $manifestPath
    $brokenPartError = @($fixtureReport.errors | Where-Object { $_ -match 'BROKEN-ID|MANIFEST-PART mismatch' }).Count -gt 0
    $unknownPartLegacy = @($fixtureReport.legacy_orphan_states | Where-Object { $_.source_file -eq 'PART_PART-RUN-99_MR-01_Planning__Strategy__CreateProposal.json' }).Count -eq 1
    Write-VorceTestResult -Context $test -Message 'BROKEN-ID im Manifest erkannt' -Passed (-not $fixtureReport.passed -and $brokenPartError)
    Write-VorceTestResult -Context $test -Message 'Unbekannter PART_PART-RUN-State bleibt Legacy-Orphan' -Passed ($unknownPartLegacy)
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    $tempRoot = Join-Path $ProjectRoot 'var/tmp/test-run-topology'
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n--- ERGEBNIS ---" -ForegroundColor Green
Write-Host "Ergebnis: $($test.PassCount)/$($test.TotalCount) Checks bestanden"

if ($test.FailCount -eq 0) {
    Write-Host "✅ Run-Topologie validiert" -ForegroundColor Green
    exit 0
}

Write-Host "❌ Run-Topologie fehlerhaft" -ForegroundColor Red
exit 1
