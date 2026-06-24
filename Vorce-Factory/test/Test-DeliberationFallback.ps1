[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-deliberation-" + [guid]::NewGuid().ToString('N'))
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $tempRoot 'var'
$global:LibDir = Join-Path $projectRoot 'src/lib'

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$test = New-VorceTestContext -Name 'DeliberationFallback'

$global:VorceTestAgentResults = New-Object 'System.Collections.Generic.Queue[object]'
$global:VorceTestAgentCalls = @()
$global:VorceTestPromptCalls = @()

function Write-VorceHeader {
    param([string]$Title, [string]$Icon)
}

function Write-VorceStep {
    param([string]$Message, [string]$Status)
}

function Get-VorcePrompt {
    param(
        [string]$PromptId,
        [hashtable]$Variables = @{}
    )

    $variableCopy = @{}
    foreach ($key in $Variables.Keys) {
        $variableCopy[$key] = $Variables[$key]
    }
    $global:VorceTestPromptCalls += [pscustomobject]@{
        prompt_id = $PromptId
        variables = $variableCopy
    }
    return "$PromptId`n$($Variables | ConvertTo-Json -Depth 20 -Compress)"
}

function Invoke-VorceAgentWithFallback {
    param(
        [string]$TaskType,
        [string]$Prompt,
        [string[]]$PreferredChain,
        [hashtable]$RunContext,
        [object]$ExpectedOutput,
        [int]$TimeoutSeconds
    )

    $contextCopy = @{}
    foreach ($key in $RunContext.Keys) {
        $contextCopy[$key] = $RunContext[$key]
    }
    $global:VorceTestAgentCalls += [pscustomobject]@{
        task_type = $TaskType
        prompt = $Prompt
        preferred_chain = @($PreferredChain)
        run_context = $contextCopy
        expected_output = $ExpectedOutput
    }
    if ($global:VorceTestAgentResults.Count -eq 0) {
        throw 'Mock-AgentRunner hat kein vorbereitetes Ergebnis.'
    }
    return $global:VorceTestAgentResults.Dequeue()
}

function New-MockAgentSuccess {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][object]$Payload,
        [Parameter(Mandatory)][string]$AttemptId,
        [string]$ModelTier = 'balanced',
        [string]$Summary = 'ok',
        [string]$WrapperMarker
    )

    $attempt = [pscustomobject]@{
        success = $true
        provider = $Provider
        model_tier = $ModelTier
        model = "$Provider-model"
        attempt_id = $AttemptId
        duration_ms = 10
        error_class = $null
        stdout_path = "artifacts/$AttemptId/stdout.log"
        stderr_path = "artifacts/$AttemptId/stderr.log"
    }
    return [pscustomobject]@{
        success = $true
        status = 'completed'
        provider = $Provider
        model_tier = $ModelTier
        model = "$Provider-model"
        attempt_id = $AttemptId
        duration_ms = 10
        payload = $Payload
        summary = $Summary
        output_hash = ('a' * 64)
        stdout_path = $attempt.stdout_path
        stderr_path = $attempt.stderr_path
        error = $null
        error_class = $null
        non_error_class = if ($Payload.status -eq 'no_work') { 'no_work' } else { $null }
        wrapper_detected = -not [string]::IsNullOrWhiteSpace($WrapperMarker)
        provider_wrapper_marker = $WrapperMarker
        attempts = @($attempt)
    }
}

function New-MockAgentWaiting {
    param(
        [string]$AttemptId = 'waiting-attempt',
        [string]$Provider = 'gemini_cli'
    )

    $attempt = [pscustomobject]@{
        success = $false
        provider = $Provider
        model_tier = 'balanced'
        model = "$Provider-model"
        attempt_id = $AttemptId
        duration_ms = 12
        error_class = 'quota_exhausted'
        stdout_path = "artifacts/$AttemptId/stdout.log"
        stderr_path = "artifacts/$AttemptId/stderr.log"
    }
    return [pscustomobject]@{
        success = $false
        status = 'waiting_provider'
        provider = $Provider
        model_tier = 'balanced'
        model = "$Provider-model"
        attempt_id = $AttemptId
        duration_ms = 12
        payload = $null
        summary = ''
        output_hash = $null
        stdout_path = $attempt.stdout_path
        stderr_path = $attempt.stderr_path
        error = 'Provider-Chain ist erschoepft.'
        error_class = 'chain_exhausted'
        retry_after = (Get-Date).AddMinutes(5).ToString('o')
        resume_required = $true
        attempts = @($attempt)
    }
}

function New-MockAgentFailure {
    param(
        [string]$AttemptId = 'failed-attempt',
        [string]$ErrorClass = 'chain_exhausted'
    )

    $attempt = [pscustomobject]@{
        success = $false
        provider = 'claude_code'
        model_tier = 'balanced'
        model = 'claude-model'
        attempt_id = $AttemptId
        duration_ms = 9
        error_class = $ErrorClass
        stdout_path = "artifacts/$AttemptId/stdout.log"
        stderr_path = "artifacts/$AttemptId/stderr.log"
    }
    return [pscustomobject]@{
        success = $false
        status = 'failed'
        provider = 'claude_code'
        model_tier = 'balanced'
        model = 'claude-model'
        attempt_id = $AttemptId
        duration_ms = 9
        payload = $null
        summary = ''
        output_hash = $null
        stdout_path = $attempt.stdout_path
        stderr_path = $attempt.stderr_path
        error = 'Provider-Chain ist erschoepft.'
        error_class = $ErrorClass
        retry_after = $null
        resume_required = $false
        attempts = @($attempt)
    }
}

function Set-MockAgentResults {
    param([object[]]$Results)

    $global:VorceTestAgentResults = New-Object 'System.Collections.Generic.Queue[object]'
    foreach ($result in $Results) {
        $global:VorceTestAgentResults.Enqueue($result)
    }
    $global:VorceTestAgentCalls = @()
    $global:VorceTestPromptCalls = @()
}

function Set-TestDualCeoConfig {
    param([bool]$FallbackToSingle = $true)

    $configDir = Join-Path $global:VarDir 'config'
    if (-not (Test-Path -LiteralPath $configDir)) {
        $null = New-Item -ItemType Directory -Path $configDir -Force
    }
    [ordered]@{
        repository = 'Vorce-Studios/Vorce'
        dual_ceo = [ordered]@{
            ceo_chain = @('codex_orchestrator:planning')
            qa_manager_chain = @('gemini_cli:premium')
            fallback_to_single = $FallbackToSingle
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $configDir 'autopilot-config.json') -Encoding UTF8
}

function Invoke-TestDeliberation {
    return Invoke-VorceDeliberation `
        -RunContext @{
            main_run_id = 'main-runtime-1'
            sub_run_id = 'sub-runtime-1'
            part_run_id = 'part-runtime-1'
            part_run_name = 'PART-RUN-Test'
        } `
        -TaskName 'Test Proposal' `
        -Variables @{ contextPrompt = 'context' }
}

$null = New-Item -ItemType Directory -Path $global:VarDir -Force
Set-TestDualCeoConfig
. (Join-Path $projectRoot 'src/lib/engines/DeliberationEngine.ps1')

try {
    Set-MockAgentResults -Results @(
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ proposal = 'domain-proposal' }) -AttemptId 'proposal-1' -WrapperMarker 'must-not-flow')
        (New-MockAgentSuccess -Provider 'gemini_cli' -Payload ([pscustomobject]@{ assessment = 'domain-critique' }) -AttemptId 'critique-1' -ModelTier 'premium')
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ decision = 'domain-final' }) -AttemptId 'synthesis-1')
    )
    $completed = Invoke-TestDeliberation
    Write-VorceTestResult -Context $test -Message 'Proposal, Critique und Synthesis liefern validierten finalen Payload' -Passed $(
        $completed.success -and
        $completed.status -eq 'completed' -and
        $completed.payload.decision -eq 'domain-final' -and
        $completed.phases.Count -eq 3 -and
        $completed.attempts.Count -eq 3
    )
    Write-VorceTestResult -Context $test -Message 'Alle Phasen behalten echte MAIN-, SUB- und PART-IDs mit eigener phase_id' -Passed $(
        $global:VorceTestAgentCalls.Count -eq 3 -and
        @($global:VorceTestAgentCalls | Where-Object {
            $_.run_context.main_run_id -eq 'main-runtime-1' -and
            $_.run_context.sub_run_id -eq 'sub-runtime-1' -and
            $_.run_context.part_run_id -eq 'part-runtime-1'
        }).Count -eq 3 -and
        @($global:VorceTestAgentCalls.run_context.phase_id | Select-Object -Unique).Count -eq 3
    )
    Write-VorceTestResult -Context $test -Message 'Routing nutzt planning, audit, planning und Critique-Provider spaet in Synthesis' -Passed $(
        ($global:VorceTestAgentCalls.task_type -join ',') -eq 'planning,audit,planning' -and
        $global:VorceTestAgentCalls[2].preferred_chain -contains 'gemini_cli:premium'
    )
    $critiqueVariables = @($global:VorceTestPromptCalls | Where-Object { $_.prompt_id -eq 'deliberation_critique' })[0].variables
    $synthesisVariables = @($global:VorceTestPromptCalls | Where-Object { $_.prompt_id -eq 'deliberation_synthesis' })[0].variables
    Write-VorceTestResult -Context $test -Message 'Folgeprompts erhalten nur Payload, nie Provider-Wrapper' -Passed $(
        $critiqueVariables.CeoProposal -match 'domain-proposal' -and
        $critiqueVariables.CeoProposal -notmatch 'must-not-flow' -and
        $synthesisVariables.QaCritique -match 'domain-critique'
    )

    Set-MockAgentResults -Results @((New-MockAgentWaiting -AttemptId 'proposal-waiting'))
    $proposalWaiting = Invoke-TestDeliberation
    Write-VorceTestResult -Context $test -Message 'Proposal chain_exhausted propagiert waiting_provider ohne Payload' -Passed $(
        -not $proposalWaiting.success -and
        $proposalWaiting.status -eq 'waiting_provider' -and
        $proposalWaiting.outcome -eq 'chain_exhausted' -and
        $null -eq $proposalWaiting.payload -and
        $proposalWaiting.phases[0].status -eq 'waiting_provider'
    )

    Set-MockAgentResults -Results @(
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ proposal = 'single-result' }) -AttemptId 'proposal-single')
        (New-MockAgentWaiting -AttemptId 'critique-waiting')
    )
    $singleFallback = Invoke-TestDeliberation
    Write-VorceTestResult -Context $test -Message 'Critique-Ausfall ist expliziter single_agent_fallback' -Passed $(
        $singleFallback.success -and
        $singleFallback.status -eq 'single_agent_fallback' -and
        $singleFallback.payload.proposal -eq 'single-result' -and
        $singleFallback.phases.Count -eq 2
    )

    Set-MockAgentResults -Results @(
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ proposal = 'synthesis-source' }) -AttemptId 'proposal-synthesis')
        (New-MockAgentSuccess -Provider 'gemini_cli' -Payload ([pscustomobject]@{ assessment = 'approved' }) -AttemptId 'critique-synthesis' -ModelTier 'premium')
        (New-MockAgentFailure -AttemptId 'synthesis-failed')
    )
    $synthesisFallback = Invoke-TestDeliberation
    Write-VorceTestResult -Context $test -Message 'Synthesis-Ausfall ist expliziter synthesis_fallback' -Passed $(
        $synthesisFallback.success -and
        $synthesisFallback.status -eq 'synthesis_fallback' -and
        $synthesisFallback.outcome -eq 'chain_exhausted' -and
        $synthesisFallback.payload.proposal -eq 'synthesis-source' -and
        $synthesisFallback.phases[2].status -eq 'chain_exhausted'
    )

    Set-MockAgentResults -Results @(
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ status = 'no_work' }) -AttemptId 'proposal-no-work')
        (New-MockAgentSuccess -Provider 'gemini_cli' -Payload ([pscustomobject]@{ status = 'no_work' }) -AttemptId 'critique-no-work' -ModelTier 'premium')
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ status = 'no_work' }) -AttemptId 'synthesis-no-work')
    )
    $noWork = Invoke-TestDeliberation
    Write-VorceTestResult -Context $test -Message 'Gueltiges no_work bleibt erfolgreich und loest keinen zusaetzlichen Fallback aus' -Passed $(
        $noWork.success -and
        $noWork.status -eq 'completed' -and
        $noWork.payload.status -eq 'no_work' -and
        $global:VorceTestAgentCalls.Count -eq 3
    )

    $promptDir = Join-Path $global:VarDir 'prompts'
    $sharedDir = Join-Path $promptDir 'shared'
    $dbDir = Join-Path $global:VarDir 'db'
    $null = New-Item -ItemType Directory -Path $sharedDir -Force
    $null = New-Item -ItemType Directory -Path $dbDir -Force
    [ordered]@{
        schema_version = 1
        prompts = [ordered]@{
            planning_session = @{ path = 'shared/planning.md' }
            deliberation_proposal = @{ path = 'shared/proposal.md' }
            deliberation_critique = @{ path = 'shared/critique.md' }
            deliberation_synthesis = @{ path = 'shared/synthesis.md' }
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $promptDir 'prompt-registry.json') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $sharedDir 'planning.md') -Encoding UTF8 -Value 'Plan {{Repository}}'
    Set-Content -LiteralPath (Join-Path $sharedDir 'proposal.md') -Encoding UTF8 -Value 'Proposal {{contextPrompt}}'
    Set-Content -LiteralPath (Join-Path $sharedDir 'critique.md') -Encoding UTF8 -Value 'Critique {{CeoProposal}}'
    Set-Content -LiteralPath (Join-Path $sharedDir 'synthesis.md') -Encoding UTF8 -Value 'Synthesis {{QaCritique}}'
    @(
        [ordered]@{
            id = 42
            number = 42
            title = 'Waiting issue'
            body = 'Body'
        }
    ) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $dbDir 'triaged-issues.json') -Encoding UTF8

    Set-MockAgentResults -Results @((New-MockAgentWaiting -AttemptId 'part-waiting'))
    $partResult = & (Join-Path $projectRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1') `
        -ConfigBag @{
            VorceRoot = $projectRoot
            VarDir = $global:VarDir
            LibDir = $global:LibDir
            Config = [pscustomobject]@{ repository = 'Vorce-Studios/Vorce' }
            DryRun = $false
            Arguments = @{ IssueNumber = 42; IssueTitle = 'Waiting issue'; IssueBody = 'Body' }
            RunContext = @{
                main_run_id = 'main-runtime-part'
                sub_run_id = 'sub-runtime-part'
                part_run_id = 'part-runtime-part'
            }
        } `
        -ParentState ([pscustomobject]@{
            id = 'sub-runtime-part'
            main_run_id = 'main-runtime-part'
            type = 'SUB'
        })
    $checkpointPath = Join-Path $global:VarDir $partResult.checkpoint_ref
    $checkpoint = if (Test-Path -LiteralPath $checkpointPath) {
        Get-Content -LiteralPath $checkpointPath -Raw | ConvertFrom-Json
    } else {
        $null
    }
    Write-VorceTestResult -Context $test -Message 'CreateProposal speichert bei waiting_provider kein Proposal und keinen created-Status' -Passed $(
        $partResult.status -eq 'waiting_provider' -and
        $partResult.status -ne 'proposal_created' -and
        -not (Test-Path -LiteralPath (Join-Path $global:VarDir 'db/proposals')) -and
        $null -ne $checkpoint
    )
    Write-VorceTestResult -Context $test -Message 'waiting_provider liefert Checkpoint- und Artefaktreferenzen fuer Resume' -Passed $(
        $partResult.checkpoint_ref -and
        $partResult.artifact_refs.Count -eq 2 -and
        $checkpoint.status -eq 'waiting_provider' -and
        $checkpoint.run_context.part_run_id -eq 'part-runtime-part' -and
        $checkpoint.artifact_refs.Count -eq 2
    )

    . (Join-Path $projectRoot 'src/lib/utils/StatusPrinter.ps1')
    . (Join-Path $projectRoot 'src/lib/state/StateManager.ps1')
    . (Join-Path $projectRoot 'src/lib/engines/RunEngine.ps1')
    Set-MockAgentResults -Results @((New-MockAgentWaiting -AttemptId 'run-engine-waiting'))
    $runEngineState = Invoke-VorcePartRun `
        -PartName 'PART-RUN-01_MR-01_Planning__Strategy__CreateProposal_42' `
        -ScriptPath (Join-Path $projectRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1') `
        -ParentState ([pscustomobject]@{
            id = 'sub-runtime-engine'
            main_run_id = 'main-runtime-engine'
            type = 'SUB'
        }) `
        -Arguments @{
            ConfigBag = @{
                VorceRoot = $projectRoot
                VarDir = $global:VarDir
                LibDir = $global:LibDir
                Config = [pscustomobject]@{ repository = 'Vorce-Studios/Vorce' }
                DryRun = $false
                Arguments = @{ IssueNumber = 42; IssueTitle = 'Waiting issue'; IssueBody = 'Body' }
                RunContext = @{
                    main_run_id = 'main-runtime-engine'
                    sub_run_id = 'sub-runtime-engine'
                }
            }
            ParentState = [pscustomobject]@{
                id = 'sub-runtime-engine'
                main_run_id = 'main-runtime-engine'
                type = 'SUB'
            }
        }
    Write-VorceTestResult -Context $test -Message 'RunEngine persistiert waiting_provider statt completed' -Passed $(
        $runEngineState.status -eq 'waiting_provider' -and
        $runEngineState.resume.blocked_part_run -eq 'PART-RUN-01_MR-01_Planning__Strategy__CreateProposal_42' -and
        $runEngineState.results[0].checkpoint_ref -and
        $runEngineState.attempts.Count -eq 1
    )

    Set-MockAgentResults -Results @(
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ proposal = 'persisted-proposal' }) -AttemptId 'part-proposal')
        (New-MockAgentSuccess -Provider 'gemini_cli' -Payload ([pscustomobject]@{ assessment = 'persisted-critique' }) -AttemptId 'part-critique' -ModelTier 'premium')
        (New-MockAgentSuccess -Provider 'codex_orchestrator' -Payload ([pscustomobject]@{ decision = 'persisted-final' }) -AttemptId 'part-synthesis' -WrapperMarker 'wrapper-must-not-persist')
    )
    $createdResult = & (Join-Path $projectRoot 'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-03_MR-01_Planning__Strategy/PART-RUNS/PART-RUN-01_MR-01_Planning__Strategy__CreateProposal.ps1') `
        -ConfigBag @{
            VorceRoot = $projectRoot
            VarDir = $global:VarDir
            LibDir = $global:LibDir
            Config = [pscustomobject]@{ repository = 'Vorce-Studios/Vorce' }
            DryRun = $false
            Arguments = @{ IssueNumber = 42; IssueTitle = 'Waiting issue'; IssueBody = 'Body' }
            RunContext = @{
                main_run_id = 'main-runtime-part'
                sub_run_id = 'sub-runtime-part'
                part_run_id = 'part-runtime-part'
            }
        } `
        -ParentState ([pscustomobject]@{
            id = 'sub-runtime-part'
            main_run_id = 'main-runtime-part'
            type = 'SUB'
        })
    $persistedProposal = Get-Content -LiteralPath $createdResult.proposal_file -Raw | ConvertFrom-Json
    Write-VorceTestResult -Context $test -Message 'CreateProposal persistiert nur finalen Payload und kompakte Artefaktmetadaten' -Passed $(
        $createdResult.status -eq 'proposal_created' -and
        $persistedProposal.deliberation.decision -eq 'persisted-final' -and
        $persistedProposal.deliberation_status -eq 'completed' -and
        ($persistedProposal | ConvertTo-Json -Depth 30) -notmatch 'wrapper-must-not-persist'
    )
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    Remove-Variable -Name VorceTestAgentResults -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name VorceTestAgentCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name VorceTestPromptCalls -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
