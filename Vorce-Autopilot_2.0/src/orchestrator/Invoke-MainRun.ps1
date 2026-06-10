# Invoke-MainRun.ps1
# Zentraler Orchestrator fuer hierarchische Ausfuehrungen (V2.0)
# Unterstützt MAIN-RUN -> ROUTER -> SUB-RUN -> PART-RUN

function Invoke-MainRun {
    param(
        [Parameter(Mandatory)][string]$MainRunName, # z.B. MAIN-RUN-01_Planning
        [object]$GlobalState,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun
    )

    $Script:OrchestratorRoot = Join-Path $PSScriptRoot "../../"
    . (Join-Path $Script:OrchestratorRoot "src/lib/run-state-manager.ps1")

    Write-Host "`n[ORCHESTRATOR] >>> Starte $MainRunName <<<" -ForegroundColor Cyan -Font Weight Bold

    # 1. Initialisiere MAIN-RUN-STATE & Verzeichnis
    $mainRunPath = Initialize-RunDirectory -RunType "Main" -RunName $MainRunName
    $mainRunState = New-RunState -RunType "Main" -RunName $MainRunName -RunPath $mainRunPath
    
    try {
        $mainRunState.status = "running"
        Save-RunState -State $mainRunState -RunPath $mainRunPath

        # 2. Rufe den spezifischen ROUTER auf
        $routerName = "ROUTER_$MainRunName"
        $routerScript = Join-Path $Script:OrchestratorRoot "src/runs/ROUTER/$routerName.ps1"
        
        if (-not (Test-Path $routerScript)) {
            throw "Router-Skript nicht gefunden: $routerScript"
        }

        Write-Host "[ORCHESTRATOR] Rufe $routerName auf..." -ForegroundColor Magenta
        $subRunDefinitions = & $routerScript -GlobalState $GlobalState -Config $Config -MainState $mainRunState

        # 3. Iteriere über SUB-RUNS
        $completedSubs = @()
        foreach ($subDef in $subRunDefinitions) {
            $subRunId = $subDef.id # z.B. 01
            $mrShort = $MainRunName -replace 'MAIN-RUN-', 'MR-'
            $subRunName = "SUB-RUN-$subRunId`_$mrShort`__$($subDef.name)"
            $subScript = $subDef.script
            
            Write-Host "[ORCHESTRATOR]   -> Starte $subRunName" -ForegroundColor Yellow
            
            $subRunPath = Initialize-RunDirectory -RunType "Sub" -RunName $subRunName -ParentPath (Join-Path $mainRunPath "SUB-RUNS")
            $subRunState = New-RunState -RunType "Sub" -RunName $subRunName -RunPath $subRunPath
            
            try {
                $subRunState.status = "running"
                Save-RunState -State $subRunState -RunPath $subRunPath
                
                $fullSubScriptPath = Join-Path $Script:OrchestratorRoot $subScript
                if (Test-Path $fullSubScriptPath) {
                    # Hier könnten PART-RUNS innerhalb des SUB-RUNS gestartet werden
                    # Wir übergeben die States hierarchisch weiter
                    & $fullSubScriptPath `
                        -MainState $mainRunState `
                        -SubState $subRunState `
                        -GlobalState $GlobalState `
                        -Config $Config `
                        -QuotaRegistry $QuotaRegistry `
                        -DryRun:$DryRun
                    
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
                $mainRunState.metadata["$subRunName"] = $subRunState.status
                $completedSubs += $subRunState
            }
        }

        $mainRunState.status = "completed"
        return [pscustomobject]@{
            status   = "completed"
            sub_runs = $completedSubs
            state    = $mainRunState
        }
    } catch {
        Add-RunError -State $mainRunState -Message "Kritischer Fehler in $MainRunName : $_" -Context $_.ScriptStackTrace
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
        Add-RunError -State $partRunState -Message "Fehler im PART-RUN $PartRunName : $_"
        return @{ success = $false; error = $_.Exception.Message }
    } finally {
        $partRunState.completed_at = (Get-Date).ToString('o')
        Save-RunState -State $partRunState -RunPath $partRunPath
    }
}

# if ($null -ne (Get-Command Export-ModuleMember -ErrorAction SilentlyContinue)) {
#     try {
#         Export-ModuleMember -Function Invoke-MainRun, Invoke-PartRun
#     } catch {}
# }
