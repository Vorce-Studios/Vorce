# DeliberationEngine.ps1 (Vorce 3.0)
# Implementiert die Dual-CEO Logik (Proposal -> Critique -> Synthesis)

function Invoke-VorceDeliberation {
    param(
        [Parameter(Mandatory)][string]$MainRun,
        [Parameter(Mandatory)][string]$SubRun,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][hashtable]$Variables
    )
    
    Write-VorceHeader -Title "DELIBERATION: $TaskName" -Icon "⚖️"

    $configPath = Join-Path $global:VarDir 'config/autopilot-config.json'
    $config = if (Test-Path $configPath) { Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    $dualCeo = $config.dual_ceo
    $runContext = @{
        main_run_id = $MainRun
        sub_run_id = $SubRun
        task_name = $TaskName
    }
    
    # 1. Proposal (Agent A)
    Write-VorceStep -Message "Phase 1: Erstelle Vorschlag..." -Status "RUN"
    $proposalPrompt = Get-VorcePrompt -PromptId "deliberation_proposal" -Variables $Variables
    $proposal = Invoke-VorceAgentWithFallback -TaskType "planning" -Prompt $proposalPrompt -PreferredChain @($dualCeo.ceo_chain) -RunContext $runContext -ExpectedOutput "json"
    
    if ($null -eq $proposal) { return $null }
    if (-not $proposal.success -and $proposal.error_class -eq 'chain_exhausted') {
        return [pscustomobject]@{
            status = 'waiting_provider'
            phase = 'proposal'
            proposal = $proposal
        }
    }
    
    # 2. Critique (Agent B)
    Write-VorceStep -Message "Phase 2: Review und Kritik..." -Status "RUN"
    $Variables["CeoProposal"] = $proposal
    $critiquePrompt = Get-VorcePrompt -PromptId "deliberation_critique" -Variables $Variables
    $critique = Invoke-VorceAgentWithFallback -TaskType "complex_review" -Prompt $critiquePrompt -PreferredChain @($dualCeo.qa_manager_chain) -RunContext $runContext -ExpectedOutput "json"
    
    if ($null -eq $critique -or (-not $critique.success)) { 
        Write-VorceStep -Message "Critique fehlgeschlagen. Nutze Proposal als Fallback." -Status "WARN"
        if ($dualCeo.fallback_to_single -eq $true) {
            return $proposal
        }
        return [pscustomobject]@{ status = 'waiting_provider'; phase = 'critique'; proposal = $proposal; critique = $critique }
    }
    
    # 3. Synthesis (Agent A)
    Write-VorceStep -Message "Phase 3: Synthese der Ergebnisse..." -Status "RUN"
    $Variables["QaCritique"] = $critique
    $synthesisPrompt = Get-VorcePrompt -PromptId "deliberation_synthesis" -Variables $Variables
    $synthesis = Invoke-VorceAgentWithFallback -TaskType "planning" -Prompt $synthesisPrompt -PreferredChain @($dualCeo.ceo_chain) -RunContext $runContext -ExpectedOutput "json"
    
    if ($null -eq $synthesis -or (-not $synthesis.success)) {
        return $proposal
    }

    return $synthesis
}

# Ende DeliberationEngine
