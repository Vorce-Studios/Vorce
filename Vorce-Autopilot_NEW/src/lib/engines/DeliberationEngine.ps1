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
    
    # 1. Proposal (Agent A)
    Write-VorceStep -Message "Phase 1: Erstelle Vorschlag..." -Status "RUN"
    $proposalPrompt = Get-VorcePrompt -PromptId "deliberation_proposal" -Variables $Variables
    $proposal = Invoke-VorceAgent -AgentName "gemini_cli" -Prompt $proposalPrompt
    
    if ($null -eq $proposal) { return $null }
    
    # 2. Critique (Agent B)
    Write-VorceStep -Message "Phase 2: Review und Kritik..." -Status "RUN"
    $Variables["CeoProposal"] = $proposal
    $critiquePrompt = Get-VorcePrompt -PromptId "deliberation_critique" -Variables $Variables
    $critique = Invoke-VorceAgent -AgentName "gemini_cli" -Prompt $critiquePrompt # Hier könnte ein anderer Agent stehen
    
    if ($null -eq $critique) { 
        Write-VorceStep -Message "Critique fehlgeschlagen. Nutze Proposal als Fallback." -Status "WARN"
        return $proposal 
    }
    
    # 3. Synthesis (Agent A)
    Write-VorceStep -Message "Phase 3: Synthese der Ergebnisse..." -Status "RUN"
    $Variables["QaCritique"] = $critique
    $synthesisPrompt = Get-VorcePrompt -PromptId "deliberation_synthesis" -Variables $Variables
    $synthesis = Invoke-VorceAgent -AgentName "gemini_cli" -Prompt $synthesisPrompt
    
    return if ($null -ne $synthesis) { $synthesis } else { $proposal }
}

# Ende DeliberationEngine
