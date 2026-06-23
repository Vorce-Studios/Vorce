[CmdletBinding()]
param()

function Get-VorceRunTopologyManifest {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Run-Topologie-Manifest nicht gefunden: $ManifestPath"
    }

    Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
}

function Get-VorceRunTopologyReport {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$ManifestPath = $(Join-Path $ProjectRoot 'web/Dashboard/src/run-topology.manifest.json'),

        [string]$ExpectedManifestPath = $(Join-Path $ProjectRoot 'web/Dashboard/src/run-topology.manifest.json'),

        [string]$ConfigPath = $(Join-Path $ProjectRoot 'var/config/autopilot-config.json'),

        [string]$RunStatesPath = $(Join-Path $ProjectRoot 'var/run-states')
    )

    $manifest = Get-VorceRunTopologyManifest -ManifestPath $ManifestPath
    $expectedManifest = Get-VorceRunTopologyManifest -ManifestPath $ExpectedManifestPath
    $config = if (Test-Path -LiteralPath $ConfigPath) {
        Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }

    $errors = New-Object System.Collections.Generic.List[string]

    function Add-TopologyError {
        param([string]$Message)
        $null = $errors.Add($Message)
    }

    $expectedMainRuns = @($expectedManifest.main_runs)
    $expectedMainNames = @($expectedMainRuns | ForEach-Object { $_.name })
    $expectedSubSpecs = @($expectedMainRuns | ForEach-Object { $_.sub_runs } | ForEach-Object { $_ })
    $expectedPartSpecs = @($expectedSubSpecs | ForEach-Object { $_.parts } | ForEach-Object { $_ })

    $runsRoot = Join-Path $ProjectRoot 'src/runs'
    $actualMainDirs = if (Test-Path -LiteralPath $runsRoot) {
        Get-ChildItem -LiteralPath $runsRoot -Directory | Where-Object { $_.Name -like 'MAIN-RUN-*' }
    } else {
        @()
    }

    foreach ($actualMainDir in $actualMainDirs) {
        if ($actualMainDir.Name -notin $expectedMainNames) {
            Add-TopologyError "Unerwarteter MAIN-RUN: $($actualMainDir.FullName)"
        }
    }

    foreach ($expectedMain in $manifest.main_runs) {
        $expectedMainDefinition = $expectedMainRuns | Where-Object { $_.name -eq $expectedMain.name }
        if (@($expectedMainDefinition).Count -ne 1) {
            Add-TopologyError "MANIFEST-MAIN fehlt oder ist doppelt: $($expectedMain.name)"
            continue
        }
        $expectedMainDefinition = $expectedMainDefinition[0]

        foreach ($expectedMainField in @('label', 'router_key', 'interval_key', 'router_file')) {
            if (([string]$expectedMain.$expectedMainField) -ne ([string]$expectedMainDefinition.$expectedMainField)) {
                Add-TopologyError "MANIFEST-MAIN mismatch fuer $($expectedMain.name): $expectedMainField"
            }
        }

        $mainDir = Join-Path $runsRoot $expectedMain.name
        if (-not (Test-Path -LiteralPath $mainDir)) {
            Add-TopologyError "MAIN-RUN fehlt: $mainDir"
            continue
        }

        $routerFiles = @(Get-ChildItem -LiteralPath $mainDir -File -Filter '*-Router.ps1' -ErrorAction SilentlyContinue)
        if ($routerFiles.Count -ne 1) {
            Add-TopologyError "MAIN-RUN $($expectedMain.name) muss exakt einen Router haben: $mainDir"
        } elseif ($routerFiles[0].Name -ne (Split-Path $expectedMain.router_file -Leaf)) {
            Add-TopologyError "Falscher Router fuer $($expectedMain.name): erwartet $(Split-Path $expectedMain.router_file -Leaf), gefunden $($routerFiles[0].Name) in $($routerFiles[0].FullName)"
        }

        $subRoot = Join-Path $mainDir 'SUB-RUNS'
        $actualSubDirs = if (Test-Path -LiteralPath $subRoot) {
            Get-ChildItem -LiteralPath $subRoot -Directory | Where-Object { $_.Name -like 'SUB-RUN-*' }
        } else {
            @()
        }

        $expectedSubDirs = @($expectedMainDefinition.sub_runs | ForEach-Object { Split-Path $_.script -Parent | Split-Path -Leaf })
        foreach ($actualSubDir in $actualSubDirs) {
            if ($actualSubDir.Name -notin $expectedSubDirs) {
                Add-TopologyError "Unerwarteter SUB-RUN: $($actualSubDir.FullName)"
            }
        }

        foreach ($expectedSub in $expectedMain.sub_runs) {
            $expectedSubDefinition = $expectedMainDefinition.sub_runs | Where-Object { $_.id -eq $expectedSub.id -and $_.name -eq $expectedSub.name }
            if (@($expectedSubDefinition).Count -ne 1) {
                Add-TopologyError "MANIFEST-SUB fehlt oder ist doppelt: $($expectedMain.name) / $($expectedSub.name)"
                continue
            }
            $expectedSubDefinition = $expectedSubDefinition[0]

            $expectedSubDir = Split-Path $expectedSub.script -Parent | Split-Path -Leaf
            $subDir = Join-Path $subRoot $expectedSubDir
            if (-not (Test-Path -LiteralPath $subDir)) {
                Add-TopologyError "SUB-RUN fehlt: $subDir"
                continue
            }

            foreach ($expectedSubField in @('id', 'name', 'script', 'directory')) {
                if (([string]$expectedSub.$expectedSubField) -ne ([string]$expectedSubDefinition.$expectedSubField)) {
                    Add-TopologyError "MANIFEST-SUB mismatch fuer $($expectedMain.name) / $($expectedSub.name): $expectedSubField"
                }
            }

            $expectedSubScript = Split-Path $expectedSub.script -Leaf
            $subScripts = @(Get-ChildItem -LiteralPath $subDir -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
            $canonicalSubScript = @($subScripts | Where-Object { $_.Name -eq $expectedSubScript })
            if ($canonicalSubScript.Count -ne 1) {
                Add-TopologyError "SUB-Skript fehlt oder ist falsch: erwartet $expectedSubScript in $subDir"
            }

            $configRules = @($config.router_rules.$($expectedMain.router_key))
            if ($configRules.Count -ne $expectedMainDefinition.sub_runs.Count) {
                Add-TopologyError "Konfiguration fuer $($expectedMain.router_key) hat $($configRules.Count) statt $($expectedMainDefinition.sub_runs.Count) SUB-RUNs"
            }
            $matchingConfigRule = @($configRules | Where-Object {
                $_.id -eq $expectedSub.id -and $_.name -eq $expectedSub.name -and ($_.script -replace '\\', '/') -eq $expectedSub.script
            })
            if ($matchingConfigRule.Count -ne 1) {
                Add-TopologyError "Konfigurationsregel passt nicht fuer $($expectedMain.router_key) / $($expectedSub.script)"
            }

            foreach ($actualConfigRule in $configRules) {
                $actualScript = ($actualConfigRule.script -replace '\\', '/')
                $matchesExpected = $expectedMainDefinition.sub_runs | Where-Object {
                    $_.id -eq $actualConfigRule.id -and $_.name -eq $actualConfigRule.name -and $_.script -eq $actualScript
                }
                if (-not $matchesExpected) {
                    Add-TopologyError "Unerwartete Konfigurationsregel fuer $($expectedMain.router_key): $actualScript"
                }
            }

            $actualPartFiles = if (Test-Path -LiteralPath (Join-Path $subDir 'PART-RUNS')) {
                Get-ChildItem -LiteralPath (Join-Path $subDir 'PART-RUNS') -File -Filter 'PART-RUN-*.ps1'
            } else {
                @()
            }
            $expectedPartFiles = @($expectedSub.parts | ForEach-Object { Split-Path $_.script -Leaf })

            foreach ($actualPartFile in $actualPartFiles) {
                if ($actualPartFile.Name -notin $expectedPartFiles) {
                    Add-TopologyError "Unerwartete PART-Datei: $($actualPartFile.FullName)"
                }
            }

            $subScriptContent = if ($canonicalSubScript) {
                Get-Content -LiteralPath $canonicalSubScript[0].FullName -Raw
            } else {
                ''
            }

            foreach ($expectedPart in $expectedSub.parts) {
                $expectedPartDefinition = $expectedSubDefinition.parts | Where-Object { $_.name -eq $expectedPart.name -and $_.script -eq $expectedPart.script }
                if (@($expectedPartDefinition).Count -ne 1) {
                    Add-TopologyError "MANIFEST-PART fehlt oder ist doppelt: $($expectedMain.name) / $($expectedSub.name) / $($expectedPart.name)"
                    continue
                }
                $expectedPartDefinition = $expectedPartDefinition[0]

                $expectedPartFile = Split-Path $expectedPart.script -Leaf
                $expectedPartPath = Join-Path (Join-Path $subDir 'PART-RUNS') $expectedPartFile

                foreach ($expectedPartField in @('id', 'name', 'script', 'directory')) {
                    if (([string]$expectedPart.$expectedPartField) -ne ([string]$expectedPartDefinition.$expectedPartField)) {
                        Add-TopologyError "MANIFEST-PART mismatch fuer $($expectedMain.name) / $($expectedSub.name) / $($expectedPart.name): $expectedPartField = $($expectedPart.$expectedPartField) statt $($expectedPartDefinition.$expectedPartField)"
                    }
                }

                if (-not (Test-Path -LiteralPath $expectedPartPath)) {
                    Add-TopologyError "PART-RUN fehlt: $expectedPartPath"
                }

                if ($subScriptContent -notmatch [regex]::Escape($expectedPartFile)) {
                    Add-TopologyError "PART nicht intern registriert in $($canonicalSubScript[0].FullName): $expectedPartFile"
                }

                if ($subScriptContent -notmatch [regex]::Escape($expectedSub.name) -or $subScriptContent -notmatch [regex]::Escape($expectedPart.name)) {
                    Add-TopologyError "PART-Parent-Zuordnung unklar in $($canonicalSubScript[0].FullName): erwartet $($expectedSub.name) / $($expectedPart.name)"
                }
            }
        }
    }

    $allRunStates = if (Test-Path -LiteralPath $RunStatesPath) {
        Get-ChildItem -LiteralPath $RunStatesPath -File -Filter '*.json' | ForEach-Object {
            try {
                $state = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                $state | Add-Member -NotePropertyName source_file -NotePropertyValue $_.Name -Force
                $state
            } catch {
                $null
            }
        } | Where-Object { $_ }
    } else {
        @()
    }

    $canonicalMainNames = @($expectedManifest.main_runs | ForEach-Object { $_.name })
    $canonicalSubNames = @($expectedSubSpecs | ForEach-Object { $_.name })
    $canonicalPartNames = @($expectedPartSpecs | ForEach-Object { $_.name })
    $canonicalMainStateStems = @($expectedManifest.main_runs | ForEach-Object { "MAIN_$($_.name)" })
    $canonicalSubStateStems = @($expectedSubSpecs | ForEach-Object { "SUB_$([System.IO.Path]::GetFileNameWithoutExtension($_.script))" })
    $canonicalPartStateStems = @($expectedPartSpecs | ForEach-Object { "PART_$([System.IO.Path]::GetFileNameWithoutExtension($_.script))" })

    $legacyOrphans = @(
        $allRunStates | Where-Object {
            $fileStem = [System.IO.Path]::GetFileNameWithoutExtension($_.source_file)
            -not (
                $canonicalMainStateStems -contains $fileStem -or
                $canonicalSubStateStems -contains $fileStem -or
                $canonicalPartStateStems -contains $fileStem
            )
        } | Select-Object source_file, type, name, sub_run, status, timestamp, started_at, completed_at
    )

    $expectedMainCount = @($expectedManifest.main_runs).Count
    $expectedSubCount = @($expectedSubSpecs).Count
    $expectedPartCount = @($expectedPartSpecs).Count
    $actualMainCount = @($manifest.main_runs).Count
    $actualSubCount = if ($actualMainCount -gt 0) { (@($manifest.main_runs | ForEach-Object { @($_.sub_runs).Count }) | Measure-Object -Sum).Sum } else { 0 }
    $actualPartCount = if ($actualMainCount -gt 0) { (@($manifest.main_runs | ForEach-Object { $_.sub_runs } | ForEach-Object { @($_.parts).Count }) | Measure-Object -Sum).Sum } else { 0 }

    [pscustomobject]@{
        passed = $errors.Count -eq 0
        errors = @($errors)
        expected_counts = [pscustomobject]@{
            main = $expectedMainCount
            sub = $expectedSubCount
            part = $expectedPartCount
        }
        actual_counts = [pscustomobject]@{
            main = $actualMainCount
            sub = $actualSubCount
            part = $actualPartCount
        }
        main_runs = $manifest.main_runs
        legacy_orphan_states = $legacyOrphans
        manifest = $manifest
    }
}
