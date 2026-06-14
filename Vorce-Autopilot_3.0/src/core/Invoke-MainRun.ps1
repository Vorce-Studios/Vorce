# Invoke-MainRun.ps1
# Zentraler Orchestrator fuer hierarchische Ausfuehrungen (V2.0)
# Unterstuetzt MAIN-RUN -> ROUTER -> SUB-RUN -> PART-RUN

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

function Invoke-MainRun {
    param(
        [Parameter(Mandatory)][string]$MainRunName, # z.B. MAIN-RUN-01_Planning
        [object]$GlobalState,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun,
        [switch]$ForceAllSubRuns  # Erzwingt alle Sub-Runs, ignoriert Router-Entscheidungen
    )

    $global:OrchestratorRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../")).Path
    # Ensure required scripts are loaded
    if (-not (Get-Command Get-RunState -ErrorAction SilentlyContinue)) {
        . (Join-Path $global:OrchestratorRoot "src/lib/state/run-state-manager.ps1")
    }

    $shortName = $MainRunName -replace 'MAIN-RUN-\d+_', ''
    Write-Host ""
    Write-Host "==========================================================================" -ForegroundColor Magenta
    Write-Host " >>> STARTE MAIN-PHASE: $shortName ($MainRunName)" -ForegroundColor Magenta
    Write-Host "==========================================================================" -ForegroundColor Magenta
    Write-Host ""

    # 1. Initialisiere MAIN-RUN-STATE & Verzeichnis
    $mainRunPath = Initialize-RunDirectory -RunType "Main" -RunName $MainRunName
    $mainRunState = New-RunState -RunType "Main" -RunName $MainRunName -RunPath $mainRunPath

    try {
        $mainRunState.status = "running"
        if ($ForceAllSubRuns.IsPresent) {
            $mainRunState.metadata["force_mode"] = $true
        }
        Save-RunState -State $mainRunState -RunPath $mainRunPath

        # 2. Rufe den spezifischen ROUTER auf (oder Config-Fallback)
        $subRunDefinitions = Resolve-SubRunDefinitions `
            -MainRunName $MainRunName `
            -GlobalState $GlobalState `
            -Config $Config `
            -MainState $mainRunState `
            -ForceAll:$ForceAllSubRuns

        if ($subRunDefinitions.Count -eq 0) {
            Write-VorceStatus -Phase $shortName -Message "Keine Aufgaben fuer diese Phase gefunden. Ueberspringe." -Color Yellow
            $mainRunState.status = "skipped"
            $mainRunState.metadata["skip_reason"] = "Keine Sub-Runs vom Router zurueckgegeben"
            return [pscustomobject]@{
                status   = "skipped"
                sub_runs = @()
                state    = $mainRunState
            }
        }

        Write-VorceStatus -Phase $shortName -Message "$($subRunDefinitions.Count) Sub-Aufgaben geplant." -Color DarkGray

        # 3. Iteriere ueber SUB-RUNS (Sequentielle Ausfuehrung fuer logische Abhaengigkeiten)
        $completedSubs = @()
        $failedCount = 0

        foreach ($subDef in $subRunDefinitions) {
            $subRunId = $subDef.id
            $mrShort = $MainRunName -replace 'MAIN-RUN-', 'MR-'
            $subRunName = "SUB-RUN-${subRunId}_${mrShort}__$($subDef.name)"
            $subScript = $subDef.script

            Write-VorceStatus -Phase $shortName -SubPhase $subDef.name -Message "Starte Ausfuehrung..." -Color Yellow

            $subRunPath = Initialize-RunDirectory -RunType "Sub" -RunName $subRunName -ParentPath (Join-Path $mainRunPath "SUB-RUNS")
            $subRunState = New-RunState -RunType "Sub" -RunName $subRunName -RunPath $subRunPath

            try {
                $subRunState.status = "running"
                Save-RunState -State $subRunState -RunPath $subRunPath

                $fullSubScriptPath = Join-Path $global:OrchestratorRoot $subScript
                if (Test-Path $fullSubScriptPath) {
                    # Frischen State laden, um Lese-Race-Conditions zu minimieren
                    $freshState = Read-AutopilotState
                    if ($null -ne $freshState) { $GlobalState = $freshState }

                    # Fuehre das SUB-RUN Skript direkt im Hauptprozess aus
                    & $fullSubScriptPath `
                        -MainState $mainRunState `
                        -SubState $subRunState `
                        -GlobalState $GlobalState `
                        -Config $Config `
                        -QuotaRegistry $QuotaRegistry `
                        -DryRun:$DryRun

                    # Verwende den echten Status aus dem SubState, nicht 'running'
                    if ($subRunState.status -eq "running") {
                        $subRunState.status = "completed"
                    }
                } else {
                    Add-RunError -State $subRunState -Message "SUB-RUN Skript nicht gefunden: $subScript"
                }
            } catch {
                Add-RunError -State $subRunState -Message "Fehler in $subRunName : $_" -Context $_.ScriptStackTrace
            } finally {
                $subRunState.completed_at = (Get-Date).ToString('o')
                Save-RunState -State $subRunState -RunPath $subRunPath

                if ($subRunState.status -ne "completed") {
                    $failedCount++
                    Write-VorceStatus -Phase $shortName -SubPhase $subDef.name -Message "FEHLGESCHLAGEN ($($subRunState.status))" -Color Red
                } else {
                    Write-VorceStatus -Phase $shortName -SubPhase $subDef.name -Message "ERFOLGREICH beendet." -Color Green
                }

                $mainRunState.metadata["sub_run_$($subDef.id)"] = @{
                    name   = $subDef.name
                    status = $subRunState.status
                    errors = $subRunState.errors.Count
                }
                $completedSubs += $subRunState
            }
        }

        # Gesamt-Status basierend auf Sub-Run Ergebnissen
        if ($failedCount -eq $subRunDefinitions.Count -and $subRunDefinitions.Count -gt 0) {
            $mainRunState.status = "failed"
        } elseif ($failedCount -gt 0) {
            $mainRunState.status = "partial"
        } else {
            $mainRunState.status = "completed"
        }

        return [pscustomobject]@{
            status   = $mainRunState.status
            sub_runs = $completedSubs
            state    = $mainRunState
        }
    } catch {
        Add-RunError -State $mainRunState -Message "Kritischer Fehler in ${MainRunName}: $_" -Context $_.ScriptStackTrace
        return [pscustomobject]@{
            status   = "failed"
            error    = $_.Exception.Message
            state    = $mainRunState
        }
    } finally {
        $mainRunState.completed_at = (Get-Date).ToString('o')
        Save-RunState -State $mainRunState -RunPath $mainRunPath
        Write-Host ""
        Write-Host "==========================================================================" -ForegroundColor Magenta
        Write-Host " <<< MAIN-PHASE BEENDET: $shortName ($($mainRunState.status))" -ForegroundColor Magenta
        Write-Host "==========================================================================" -ForegroundColor Magenta
        Write-Host ""
    }
}

function Resolve-SubRunDefinitions {
    <#
    .SYNOPSIS
    Bestimmt die auszufuehrenden Sub-Runs fuer einen Main-Run.
    Prioritaet: 1) ROUTER-Skript  2) Config router_rules  3) Leer
    #>
    param(
        [string]$MainRunName,
        [object]$GlobalState,
        [object]$Config,
        [object]$MainState,
        [switch]$ForceAll
    )

    # Versuch 1: Dediziertes Router-Skript
    $routerName = "ROUTER_$MainRunName"
    $routerScript = Join-Path $global:OrchestratorRoot "src/runs/$MainRunName/$routerName.ps1"

    if (Test-Path $routerScript) {
        Write-Host "[ORCHESTRATOR] Rufe Router-Skript auf: $routerName" -ForegroundColor Magenta
        $definitions = & $routerScript -GlobalState $GlobalState -Config $Config -MainState $MainState -QuotaRegistry $QuotaRegistry

        if ($ForceAll.IsPresent) {
            Write-Host "[ORCHESTRATOR] Force-Modus aktiv: Alle Sub-Runs werden ausgefuehrt." -ForegroundColor Yellow
        }

        return @($definitions)
    }

    # Versuch 2: Config-basierte Regeln (Fallback)
    # Extrahiere den kurzen Run-Typ-Namen (z.B. "Planning" aus "MAIN-RUN-01_Planning")
    $runType = $MainRunName -replace '^MAIN-RUN-\d+_', ''

    if ($Config.PSObject.Properties.Name -contains "router_rules" -and
        $Config.router_rules.PSObject.Properties.Name -contains $runType) {

        Write-Host "[ORCHESTRATOR] Kein Router-Skript gefunden. Nutze Config-Regeln fuer '$runType'." -ForegroundColor DarkYellow
        $rules = $Config.router_rules.$runType
        $subRuns = @()
        $idx = 1
        foreach ($rule in $rules) {
            if ($rule.enabled -or $ForceAll.IsPresent) {
                $subRuns += @{
                    id     = "{0:D2}" -f $idx
                    name   = $rule.name
                    script = $rule.script
                }
                $idx++
            } else {
                Write-Host "[ORCHESTRATOR]   -> Sub-Run $($rule.name) deaktiviert (Config)." -ForegroundColor DarkGray
                # State-Aggregation: Uebersprungene Sub-Runs dokumentieren
                $MainState.metadata["skipped_$($rule.name)"] = @{
                    reason    = "disabled_in_config"
                    timestamp = (Get-Date).ToString('o')
                }
            }
        }
        return $subRuns
    }

    Write-Warning "[ORCHESTRATOR] Weder Router-Skript noch Config-Regeln fuer '$MainRunName' gefunden!"
    return @()
}

function Invoke-PartRun {
    param(
        [Parameter(Mandatory)][string]$PartRunName,
        [Parameter(Mandatory)][string]$AgentType,
        [Parameter(Mandatory)][string]$Prompt,
        [object]$SubState,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun
    )

    $shortPhase = if ($SubState.PSObject.Properties.Name -contains "name") { $SubState.name -replace 'SUB-RUN-\d+_MR-\d+_', '' } else { "Task" }
    Write-VorceStatus -Phase $shortPhase -SubPhase "Agent" -Message "Bereite PART-RUN vor: $PartRunName (Rolle: $AgentType)" -Color DarkCyan

    $partRunPath = Initialize-RunDirectory -RunType "Part" -RunName $PartRunName -ParentPath (Join-Path $SubState.metadata["run_path"] "PART-RUNS")
    $partRunState = New-RunState -RunType "Part" -RunName $PartRunName -RunPath $partRunPath

    $cacheDir = Join-Path $global:OrchestratorRoot "var/db/cache"
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

    $hashInput = "$AgentType|$Prompt"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
    $hashString = [BitConverter]::ToString($hashBytes) -replace '-'
    $cacheFile = Join-Path $cacheDir "part-run-$hashString.json"

    if (-not $DryRun.IsPresent -and (Test-Path $cacheFile)) {
        try {
            $cacheData = Get-Content -LiteralPath $cacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $cacheAge = ((Get-Date) - [datetime]$cacheData.timestamp).TotalHours
            if ($cacheAge -lt 24) {
                Write-VorceStatus -Phase $shortPhase -SubPhase "Cache" -Message "Nutze Cache für $PartRunName" -Color Green
                $partRunState.status = "completed"
                $partRunState.metadata["output"] = $cacheData.output
                $partRunState.metadata["provider"] = "cache"
                $partRunState.completed_at = (Get-Date).ToString('o')
                Save-RunState -State $partRunState -RunPath $partRunPath
                return @{ success = $true; output = $cacheData.output; provider = "cache" }
            }
        } catch { }
    }

    try {
        $partRunState.status = "running"
        Save-RunState -State $partRunState -RunPath $partRunPath

        # Resolve Provider for Agent
        $taskType = if ($AgentType -eq "CEO" -or $AgentType -eq "codex_orchestrator") { "planning" } else { "complex_review" }

        $maxAttemptsPerProvider = if ($Config.PSObject.Properties.Name -contains "part_run_retry") { $Config.part_run_retry.max_attempts } else { 2 }
        $delayBase = if ($Config.PSObject.Properties.Name -contains "part_run_retry") { $Config.part_run_retry.delay_seconds } else { 5 }
        $result = $null
        $excludeProviders = @()

        # Check if AgentType is a specific provider name
        $preferredProvider = $null
        if ($QuotaRegistry.providers.PSObject.Properties.Name -contains $AgentType) {
            $preferredProvider = $AgentType
        }

        # PROVIDER CYCLING LOOP
        while ($true) {
            $route = $null

            if ($preferredProvider -and ($excludeProviders -notcontains $preferredProvider)) {
                # Use the specifically requested provider if it's available
                if (Test-ProviderAvailable -Registry $QuotaRegistry -ProviderName $preferredProvider) {
                    $cmdName = $QuotaRegistry.providers.$preferredProvider.command
                    $route = [ordered]@{
                        provider   = $preferredProvider
                        model_tier = "default" # Fallback to default for direct requests
                        command    = $cmdName
                    }
                    Write-VorceStatus -Phase $shortPhase -SubPhase "Agent" -Message "Nutze explizit angeforderten Provider: $preferredProvider" -Color Cyan
                } else {
                    Write-VorceStatus -Phase $shortPhase -SubPhase "Agent" -Message "Angeforderter Provider $preferredProvider nicht verfuegbar. Wechsle auf Routing-Chain." -Color DarkYellow
                    $preferredProvider = $null # Clear it so we don't try again
                }
            }

            if ($null -eq $route) {
                $route = Resolve-CliProvider -QuotaRegistry $QuotaRegistry -TaskType $taskType -ExcludeProviders $excludeProviders
            }

            if ($null -eq $route) {
                Write-Error "[ORCHESTRATOR] Alle verfügbaren Provider fuer '$taskType' sind erschoepft oder fehlgeschlagen."
                break
            }

            for ($i = 1; $i -le $maxAttemptsPerProvider; $i++) {
                $attemptStr = if ($maxAttemptsPerProvider -gt 1) { " (Versuch $i/$maxAttemptsPerProvider)" } else { "" }
                Write-VorceStatus -Phase $shortPhase -SubPhase "LLM" -Message "Rufe $($route.provider)$attemptStr auf..." -Color Cyan

                $result = Invoke-CliTask `
                    -QuotaRegistry $QuotaRegistry `
                    -TaskType $taskType `
                    -Prompt $Prompt `
                    -WorkingDirectory $Config.gemini_worktree_path `
                    -DryRun:$DryRun `
                    -ProviderOverride $route.provider `
                    -ModelTierOverride $route.model_tier

                if ($result.success) {
                    Write-VorceStatus -Phase $shortPhase -SubPhase "LLM" -Message "Antwort von $($result.provider) erhalten." -Color Green
                    break
                }

                if ($i -lt $maxAttemptsPerProvider) {
                    Write-VorceStatus -Phase $shortPhase -SubPhase "Retry" -Message "Fehler bei $($route.provider). Warte $($delayBase * $i)s..." -Color DarkYellow
                    Start-Sleep -Seconds ($delayBase * $i)
                }
            }

            if ($result.success) { break }

            # If all attempts for this provider failed, exclude it and try next provider in chain
            Write-VorceStatus -Phase $shortPhase -SubPhase "Cycle" -Message "Provider $($route.provider) erschoepft. Versuche Fallback..." -Color Red
            $excludeProviders += $route.provider
            if ($route.provider -eq $preferredProvider) { $preferredProvider = $null }
        }

        $partRunState.metadata["output"] = $result.output
        $partRunState.metadata["provider"] = $result.provider

        if ($result.success) {
            $partRunState.status = "completed"
            Add-RunArtifact -State $partRunState -ArtifactName "AgentOutput" -ArtifactPath (Join-Path $partRunPath "output.txt")
            $result.output | Set-Content (Join-Path $partRunPath "output.txt") -Encoding UTF8

            # Save to Cache
            $cacheData = [pscustomobject]@{
                timestamp = (Get-Date).ToString('o')
                output = $result.output
            }
            $cacheData | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $cacheFile -Encoding UTF8 -Force
        } else {
            $partRunState.status = "failed"
            Add-RunError -State $partRunState -Message "Agent Call fehlgeschlagen: $($result.error)"
        }

        return $result
    } catch {
        Add-RunError -State $partRunState -Message "Fehler im PART-RUN ${PartRunName}: $_"
        return @{ success = $false; error = $_.Exception.Message }
    } finally {
        $partRunState.completed_at = (Get-Date).ToString('o')
        Save-RunState -State $partRunState -RunPath $partRunPath
    }
}

