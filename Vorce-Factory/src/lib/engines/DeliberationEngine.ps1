# DeliberationEngine.ps1 (Vorce 3.0)
# Fuehrt Proposal, Critique und Synthesis mit validierten Agent-Payloads aus.

function Get-VorceDeliberationValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Copy-VorceDeliberationHashtable {
    param([hashtable]$Source = @{})

    $copy = @{}
    foreach ($key in $Source.Keys) {
        $copy[$key] = $Source[$key]
    }
    return $copy
}

function ConvertTo-VorceDeliberationPayloadJson {
    param([AllowNull()][object]$Payload)

    return ($Payload | ConvertTo-Json -Depth 100 -Compress)
}

function Get-VorceDeliberationArtifactRefs {
    param([AllowNull()][object]$Result)

    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($attempt in @(Get-VorceDeliberationValue -Object $Result -Name 'attempts')) {
        foreach ($name in @('stdout_path', 'stderr_path')) {
            $path = [string](Get-VorceDeliberationValue -Object $attempt -Name $name)
            if (-not [string]::IsNullOrWhiteSpace($path) -and -not $refs.Contains($path)) {
                $refs.Add($path)
            }
        }
    }
    foreach ($name in @('stdout_path', 'stderr_path')) {
        $path = [string](Get-VorceDeliberationValue -Object $Result -Name $name)
        if (-not [string]::IsNullOrWhiteSpace($path) -and -not $refs.Contains($path)) {
            $refs.Add($path)
        }
    }
    return @($refs.ToArray())
}

function ConvertTo-VorceDeliberationAttemptRecord {
    param([Parameter(Mandatory)][object]$Attempt)

    return [pscustomobject]@{
        attempt_id = Get-VorceDeliberationValue -Object $Attempt -Name 'attempt_id'
        success = (Get-VorceDeliberationValue -Object $Attempt -Name 'success') -eq $true
        provider = Get-VorceDeliberationValue -Object $Attempt -Name 'provider'
        model_tier = Get-VorceDeliberationValue -Object $Attempt -Name 'model_tier'
        model = Get-VorceDeliberationValue -Object $Attempt -Name 'model'
        duration_ms = Get-VorceDeliberationValue -Object $Attempt -Name 'duration_ms'
        error_class = Get-VorceDeliberationValue -Object $Attempt -Name 'error_class'
        stdout_path = Get-VorceDeliberationValue -Object $Attempt -Name 'stdout_path'
        stderr_path = Get-VorceDeliberationValue -Object $Attempt -Name 'stderr_path'
    }
}

function New-VorceDeliberationPhaseRecord {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$PhaseId,
        [Parameter(Mandatory)][object]$Result
    )

    $success = (Get-VorceDeliberationValue -Object $Result -Name 'success') -eq $true
    $runnerStatus = [string](Get-VorceDeliberationValue -Object $Result -Name 'status')
    $errorClass = [string](Get-VorceDeliberationValue -Object $Result -Name 'error_class')
    $phaseStatus = if ($success) {
        'completed'
    } elseif ($runnerStatus -eq 'waiting_provider') {
        'waiting_provider'
    } elseif ($errorClass -eq 'chain_exhausted') {
        'chain_exhausted'
    } else {
        'failed'
    }
    $attempts = @(
        @(Get-VorceDeliberationValue -Object $Result -Name 'attempts') |
            ForEach-Object { ConvertTo-VorceDeliberationAttemptRecord -Attempt $_ }
    )

    return [pscustomobject]@{
        phase = $Phase
        phase_id = $PhaseId
        status = $phaseStatus
        success = $success
        provider = Get-VorceDeliberationValue -Object $Result -Name 'provider'
        model_tier = Get-VorceDeliberationValue -Object $Result -Name 'model_tier'
        model = Get-VorceDeliberationValue -Object $Result -Name 'model'
        duration_ms = Get-VorceDeliberationValue -Object $Result -Name 'duration_ms'
        summary = Get-VorceDeliberationValue -Object $Result -Name 'summary'
        error_class = Get-VorceDeliberationValue -Object $Result -Name 'error_class'
        validation = [pscustomobject]@{
            expected_output = 'json'
            valid = $success
            output_hash = Get-VorceDeliberationValue -Object $Result -Name 'output_hash'
            non_error_class = Get-VorceDeliberationValue -Object $Result -Name 'non_error_class'
            wrapper_detected = (Get-VorceDeliberationValue -Object $Result -Name 'wrapper_detected') -eq $true
        }
        attempts = $attempts
        artifact_refs = @(Get-VorceDeliberationArtifactRefs -Result $Result)
    }
}

function New-VorceDeliberationOutcome {
    param(
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Outcome,
        [AllowNull()][object]$Payload,
        [object[]]$Phases = @(),
        [AllowNull()][object]$TerminalResult,
        [AllowNull()][string]$Summary
    )

    $attempts = @($Phases | ForEach-Object { @($_.attempts) })
    $artifactRefs = New-Object System.Collections.Generic.List[string]
    foreach ($phase in $Phases) {
        foreach ($path in @($phase.artifact_refs)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$path) -and -not $artifactRefs.Contains([string]$path)) {
                $artifactRefs.Add([string]$path)
            }
        }
    }
    $success = $Status -notin @('failed', 'waiting_provider')

    return [pscustomobject]@{
        success = $success
        status = $Status
        outcome = $Outcome
        payload = $Payload
        summary = $Summary
        phases = @($Phases)
        attempts = $attempts
        artifact_refs = @($artifactRefs.ToArray())
        error = Get-VorceDeliberationValue -Object $TerminalResult -Name 'error'
        error_class = Get-VorceDeliberationValue -Object $TerminalResult -Name 'error_class'
        retry_after = if ($Status -eq 'waiting_provider') {
            Get-VorceDeliberationValue -Object $TerminalResult -Name 'retry_after'
        } else {
            $null
        }
        resume_required = $Status -eq 'waiting_provider' -and
            (Get-VorceDeliberationValue -Object $TerminalResult -Name 'resume_required') -eq $true
    }
}

function Assert-VorceDeliberationRunContext {
    param([Parameter(Mandatory)][hashtable]$RunContext)

    $missing = @(
        @('main_run_id', 'sub_run_id', 'part_run_id') |
            Where-Object { [string]::IsNullOrWhiteSpace([string]$RunContext[$_]) }
    )
    if ($missing.Count -gt 0) {
        throw "Deliberation benoetigt echte Runtime-IDs: $($missing -join ', ')."
    }
}

function Invoke-VorceDeliberation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$RunContext,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][hashtable]$Variables
    )

    Assert-VorceDeliberationRunContext -RunContext $RunContext
    Write-VorceHeader -Title "DELIBERATION: $TaskName" -Icon "D"

    $configPath = Join-Path $global:VarDir 'config/autopilot-config.json'
    $config = if (Test-Path -LiteralPath $configPath) {
        Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        [pscustomobject]@{}
    }
    $dualCeo = $config.dual_ceo
    $phases = New-Object System.Collections.Generic.List[object]
    $promptVariables = Copy-VorceDeliberationHashtable -Source $Variables

    $proposalContext = Copy-VorceDeliberationHashtable -Source $RunContext
    $proposalContext.task_name = $TaskName
    $proposalContext.phase = 'proposal'
    $proposalContext.phase_id = "$($RunContext.part_run_id):proposal"
    Write-VorceStep -Message "Phase 1: Erstelle Vorschlag..." -Status "RUN"
    $proposalPrompt = Get-VorcePrompt -PromptId 'deliberation_proposal' -Variables $promptVariables
    $proposal = Invoke-VorceAgentWithFallback `
        -TaskType 'planning' `
        -Prompt $proposalPrompt `
        -PreferredChain @($dualCeo.ceo_chain) `
        -RunContext $proposalContext `
        -ExpectedOutput 'json'
    $proposalPhase = New-VorceDeliberationPhaseRecord -Phase 'proposal' -PhaseId $proposalContext.phase_id -Result $proposal
    $phases.Add($proposalPhase)

    if (-not $proposal.success) {
        $status = if ($proposal.status -eq 'waiting_provider') { 'waiting_provider' } else { 'failed' }
        $outcome = if ($proposal.error_class -eq 'chain_exhausted') { 'chain_exhausted' } else { 'proposal_failed' }
        return New-VorceDeliberationOutcome `
            -Status $status `
            -Outcome $outcome `
            -Payload $null `
            -Phases $phases.ToArray() `
            -TerminalResult $proposal `
            -Summary $proposal.summary
    }

    $promptVariables['CeoProposal'] = ConvertTo-VorceDeliberationPayloadJson -Payload $proposal.payload
    $critiqueContext = Copy-VorceDeliberationHashtable -Source $RunContext
    $critiqueContext.task_name = $TaskName
    $critiqueContext.phase = 'critique'
    $critiqueContext.phase_id = "$($RunContext.part_run_id):critique"
    Write-VorceStep -Message "Phase 2: Review und Kritik..." -Status "RUN"
    $critiquePrompt = Get-VorcePrompt -PromptId 'deliberation_critique' -Variables $promptVariables
    $critique = Invoke-VorceAgentWithFallback `
        -TaskType 'audit' `
        -Prompt $critiquePrompt `
        -PreferredChain @($dualCeo.qa_manager_chain) `
        -RunContext $critiqueContext `
        -ExpectedOutput 'json'
    $critiquePhase = New-VorceDeliberationPhaseRecord -Phase 'critique' -PhaseId $critiqueContext.phase_id -Result $critique
    $phases.Add($critiquePhase)

    if (-not $critique.success) {
        if ($dualCeo.fallback_to_single -eq $true) {
            Write-VorceStep -Message "Critique nicht verfuegbar. Nutze expliziten Single-Agent-Fallback." -Status "WARN"
            return New-VorceDeliberationOutcome `
                -Status 'single_agent_fallback' `
                -Outcome 'critique_failed' `
                -Payload $proposal.payload `
                -Phases $phases.ToArray() `
                -TerminalResult $critique `
                -Summary $proposal.summary
        }

        $status = if ($critique.status -eq 'waiting_provider') { 'waiting_provider' } else { 'failed' }
        $outcome = if ($critique.error_class -eq 'chain_exhausted') { 'chain_exhausted' } else { 'critique_failed' }
        return New-VorceDeliberationOutcome `
            -Status $status `
            -Outcome $outcome `
            -Payload $null `
            -Phases $phases.ToArray() `
            -TerminalResult $critique `
            -Summary $critique.summary
    }

    $promptVariables['QaCritique'] = ConvertTo-VorceDeliberationPayloadJson -Payload $critique.payload
    $synthesisChain = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($dualCeo.ceo_chain)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry)) { $synthesisChain.Add([string]$entry) }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$critique.provider)) {
        $critiqueFallback = if ($critique.model_tier) {
            "$($critique.provider):$($critique.model_tier)"
        } else {
            [string]$critique.provider
        }
        if (-not $synthesisChain.Contains($critiqueFallback)) { $synthesisChain.Add($critiqueFallback) }
    }

    $synthesisContext = Copy-VorceDeliberationHashtable -Source $RunContext
    $synthesisContext.task_name = $TaskName
    $synthesisContext.phase = 'synthesis'
    $synthesisContext.phase_id = "$($RunContext.part_run_id):synthesis"
    Write-VorceStep -Message "Phase 3: Synthese der Ergebnisse..." -Status "RUN"
    $synthesisPrompt = Get-VorcePrompt -PromptId 'deliberation_synthesis' -Variables $promptVariables
    $synthesis = Invoke-VorceAgentWithFallback `
        -TaskType 'planning' `
        -Prompt $synthesisPrompt `
        -PreferredChain $synthesisChain.ToArray() `
        -RunContext $synthesisContext `
        -ExpectedOutput 'json'
    $synthesisPhase = New-VorceDeliberationPhaseRecord -Phase 'synthesis' -PhaseId $synthesisContext.phase_id -Result $synthesis
    $phases.Add($synthesisPhase)

    if (-not $synthesis.success) {
        Write-VorceStep -Message "Synthese fehlgeschlagen. Nutze expliziten Synthesis-Fallback." -Status "WARN"
        return New-VorceDeliberationOutcome `
            -Status 'synthesis_fallback' `
            -Outcome $(if ($synthesis.error_class -eq 'chain_exhausted') { 'chain_exhausted' } else { 'synthesis_failed' }) `
            -Payload $proposal.payload `
            -Phases $phases.ToArray() `
            -TerminalResult $synthesis `
            -Summary $proposal.summary
    }

    return New-VorceDeliberationOutcome `
        -Status 'completed' `
        -Outcome 'synthesized' `
        -Payload $synthesis.payload `
        -Phases $phases.ToArray() `
        -TerminalResult $synthesis `
        -Summary $synthesis.summary
}

# Ende DeliberationEngine
