# Invoke-MainRun.ps1
# Zentraler Orchestrator fuer hierarchische Ausfuehrungen (V2.0)
# Unterstuetzt MAIN-RUN -> ROUTER -> SUB-RUN -> PART-RUN

function Invoke-MainRun {
    param(
        [Parameter(Mandatory)][string]$MainRunName, # z.B. MAIN-RUN-01_Planning
        [object]$GlobalState,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun,
        [switch]$ForceAllSubRuns  # Erzwingt alle Sub-Runs, ignoriert Router-Entscheidungen
    )

    $Script:OrchestratorRoot = Join-Path $PSScriptRoot "../../"
    . (Join-Path $Script:OrchestratorRoot "src/lib/run-state-manager.ps1")

    Write-Host "`n[ORCHESTRATOR] >>> Starte $MainRunName <<<" -ForegroundColor Cyan

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
            Write-Host "[ORCHESTRATOR] Keine Sub-Runs fuer $MainRunName definiert. Ueberspringe." -ForegroundColor Yellow
            $mainRunState.status = "skipped"
            $mainRunState.metadata["skip_reason"] = "Keine Sub-Runs vom Router zurueckgegeben"
            return [pscustomobject]@{
                status   = "skipped"
                sub_runs = @()
                state    = $mainRunState
            }
        }

        Write-Host "[ORCHESTRATOR] $($subRunDefinitions.Count) Sub-Run(s) geplant." -ForegroundColor DarkGray

        # 3. Iteriere ueber SUB-RUNS
        $completedSubs = @()
        $failedCount = 0
        foreach ($subDef in $subRunDefinitions) {
            $subRunId = $subDef.id
            $mrShort = $MainRunName -replace 'MAIN-RUN-', 'MR-'
            $subRunName = "SUB-RUN-${subRunId}_${mrShort}__$($subDef.name)"
            $subScript = $subDef.script
            
            Write-Host "[ORCHESTRATOR]   -> Starte $subRunName" -ForegroundColor Yellow
            
            $subRunPath = Initialize-RunDirectory -RunType "Sub" -RunName $subRunName -ParentPath (Join-Path $mainRunPath "SUB-RUNS")
            $subRunState = New-RunState -RunType "Sub" -RunName $subRunName -RunPath $subRunPath
            
            try {
                $subRunState.status = "running"
                Save-RunState -State $subRunState -RunPath $subRunPath
                
                $fullSubScriptPath = Join-Path $Script:OrchestratorRoot $subScript
                if (Test-Path $fullSubScriptPath) {
                    & $fullSubScriptPath `
                        -MainState $mainRunState `
                        -SubState $subRunState `
                        -GlobalState $GlobalState `
                        -Config $Config `
                        -QuotaRegistry $QuotaRegistry `
                        -DryRun:$DryRun
                    
                    # Nur auf "completed" setzen wenn der Sub-Run seinen Status nicht selbst geaendert hat
                    if ($subRunState.status -eq "running") {
                        $subRunState.status = "completed"
                    }
                } else {
                    Add-RunError -State $subRunState -Message "SUB-RUN Skript nicht gefunden: $subScript"
                }
            } catch {
                $failedCount++
                Add-RunError -State $subRunState -Message "Fehler in ${subRunName}: $_" -Context $_.ScriptStackTrace
            } finally {
                $subRunState.completed_at = (Get-Date).ToString('o')
                Save-RunState -State $subRunState -RunPath $subRunPath
                # State-Aggregation: Alle Sub-Run Ergebnisse im Main-Run tracken
                $mainRunState.metadata["sub_run_$subRunId"] = @{
                    name   = $subDef.name
                    status = $subRunState.status
                    errors = $subRunState.errors.Count
                }
                $completedSubs += $subRunState
            }
        }

        # Gesamt-Status basierend auf Sub-Run Ergebnissen
        if ($failedCount -eq $subRunDefinitions.Count) {
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
        Write-Host "[ORCHESTRATOR] $MainRunName beendet ($($mainRunState.status))." -ForegroundColor Cyan
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
    $routerScript = Join-Path $Script:OrchestratorRoot "src/runs/ROUTER/$routerName.ps1"
    
    if (Test-Path $routerScript) {
        Write-Host "[ORCHESTRATOR] Rufe Router-Skript auf: $routerName" -ForegroundColor Magenta
        $definitions = & $routerScript -GlobalState $GlobalState -Config $Config -MainState $MainState
        
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
        [Parameter(Mandatory)][string]$AgentType, # CEO, QA-Manager, Partner
        [Parameter(Mandatory)][string]$Prompt,
        [object]$SubState,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun
    )

    Write-Host "[ORCHESTRATOR]   >> PART-RUN: $PartRunName (Agent: $AgentType)" -ForegroundColor DarkCyan

    $partRunPath = Initialize-RunDirectory -RunType "Part" -RunName $PartRunName -ParentPath (Join-Path $SubState.metadata["run_path"] "PART-RUNS")
    $partRunState = New-RunState -RunType "Part" -RunName $PartRunName -RunPath $partRunPath

    try {
        $partRunState.status = "running"
        Save-RunState -State $partRunState -RunPath $partRunPath

        # Resolve Provider for Agent
        $taskType = if ($AgentType -eq "CEO") { "planning" } else { "complex_review" }
        $route = Resolve-CliProvider -QuotaRegistry $QuotaRegistry -TaskType $taskType
        
        $result = Invoke-CliTask `
            -QuotaRegistry $QuotaRegistry `
            -TaskType $taskType `
            -Prompt $Prompt `
            -WorkingDirectory $Config.gemini_worktree_path `
            -DryRun:$DryRun `
            -ProviderOverride $route.provider `
            -ModelTierOverride $route.model_tier

        $partRunState.metadata["output"] = $result.output
        $partRunState.metadata["provider"] = $result.provider
        
        if ($result.success) {
            $partRunState.status = "completed"
            Add-RunArtifact -State $partRunState -ArtifactName "AgentOutput" -ArtifactPath (Join-Path $partRunPath "output.txt")
            $result.output | Set-Content (Join-Path $partRunPath "output.txt") -Encoding UTF8
        } else {
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
