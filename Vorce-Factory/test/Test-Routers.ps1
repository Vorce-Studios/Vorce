[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { Split-Path -Parent $PSScriptRoot } else { $ProjectRoot }

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $ProjectRoot 'src/lib/engines/RouterEngine.ps1')

$test = New-VorceTestContext -Name 'Routers'
$configPath = Join-Path $ProjectRoot 'var/config/autopilot-config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$tempRoot = Join-Path $ProjectRoot 'var/tmp/test-routers'
$existingScript = 'src/lib/engines/RouterEngine.ps1'

function New-RouterTestBag {
    param(
        [hashtable]$RouterData = @{},
        [string]$VarDir = $tempRoot,
        [object]$Config = $config,
        [object]$GlobalState,
        [object]$QuotaRegistry
    )

    if ($null -eq $GlobalState) {
        $GlobalState = [pscustomobject]@{}
    }
    if ($null -eq $QuotaRegistry) {
        $QuotaRegistry = [pscustomobject]@{}
    }

    return @{
        VorceRoot = $ProjectRoot
        VarDir = $VarDir
        LibDir = Join-Path $ProjectRoot 'src/lib'
        Config = $Config
        GlobalState = $GlobalState
        QuotaRegistry = $QuotaRegistry
        RouterData = $RouterData
        Timestamp = '2026-06-23T12:00:00.0000000Z'
        DryRun = $true
    }
}

function New-RouterTestRule {
    param(
        [Parameter(Mandatory)][string]$Condition,
        [string]$Mode = 'automatic',
        [bool]$Enabled = $true,
        [object]$ConditionSettings = @{},
        [string]$Script = $existingScript
    )

    return [pscustomobject]@{
        id = '01'
        name = "Test_$Condition"
        script = $Script
        enabled = $Enabled
        mode = $Mode
        condition = $Condition
        condition_settings = $ConditionSettings
        dashboard_editable = $true
    }
}

function Invoke-RouterTestDecision {
    param(
        [Parameter(Mandatory)][string]$Condition,
        [Parameter(Mandatory)][hashtable]$RouterData,
        [string]$Mode = 'automatic',
        [bool]$Enabled = $true,
        [object]$ConditionSettings = @{},
        [string]$Script = $existingScript,
        [switch]$Force
    )

    $bag = New-RouterTestBag -RouterData $RouterData
    $state = [pscustomobject]@{ metadata = [ordered]@{} }
    $rule = New-RouterTestRule -Condition $Condition -Mode $Mode -Enabled $Enabled -ConditionSettings $ConditionSettings -Script $Script
    return @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $bag -MainState $state -Rules @($rule) -Force:$Force)[0]
}

function Test-ConditionPair {
    param(
        [Parameter(Mandatory)][string]$Condition,
        [Parameter(Mandatory)][hashtable]$TrueData,
        [Parameter(Mandatory)][hashtable]$FalseData,
        [object]$ConditionSettings = @{},
        [string]$ExpectedFalseReason = 'condition_not_met'
    )

    $trueDecision = Invoke-RouterTestDecision -Condition $Condition -RouterData $TrueData -ConditionSettings $ConditionSettings
    Write-VorceTestResult -Context $test -Message "$Condition true aktiviert" -Passed (
        $trueDecision.active -eq $true -and
        @('active_always', 'active_condition_met') -contains $trueDecision.reason
    )
    Write-VorceTestResult -Context $test -Message "$Condition true liefert Evidence" -Passed (
        $null -ne $trueDecision.evidence -and
        @($trueDecision.evidence.PSObject.Properties).Count -gt 0
    )

    if ($Condition -eq 'always') {
        $falseDecision = Invoke-RouterTestDecision -Condition $Condition -RouterData $FalseData -Enabled $false
    } else {
        $falseDecision = Invoke-RouterTestDecision -Condition $Condition -RouterData $FalseData -ConditionSettings $ConditionSettings
    }
    Write-VorceTestResult -Context $test -Message "$Condition false deaktiviert" -Passed (
        $falseDecision.active -eq $false -and $falseDecision.reason -eq $ExpectedFalseReason
    )
}

try {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path (Join-Path $tempRoot 'db') -Force

    $expectedWhitelist = @(
        'always',
        'pipeline_below_limit',
        'has_untriaged_issues',
        'has_approved_proposals',
        'has_active_jules_delegations',
        'has_active_local_agent_sessions',
        'has_open_prs_requiring_review',
        'jules_capacity_available',
        'housekeeping_due',
        'has_new_audit_inputs',
        'has_open_alerts',
        'optimizer_has_sufficient_samples',
        'optimizer_has_findings',
        'optimizer_has_approved_changes',
        'optimizer_has_changes_to_evaluate',
        'memory_maintenance_due',
        'memory_has_candidates',
        'master_issue_context_changed'
    )
    $actualWhitelist = @(Get-VorceRouterConditionWhitelist)
    Write-VorceTestResult -Context $test -Message 'Condition-Whitelist ist vollstaendig und exklusiv' -Passed (
        $actualWhitelist.Count -eq $expectedWhitelist.Count -and
        @($expectedWhitelist | Where-Object { $actualWhitelist -notcontains $_ }).Count -eq 0 -and
        @($actualWhitelist | Where-Object { $expectedWhitelist -notcontains $_ }).Count -eq 0
    )

    Test-ConditionPair -Condition 'always' -TrueData @{} -FalseData @{} -ExpectedFalseReason 'disabled_in_config'
    Test-ConditionPair -Condition 'pipeline_below_limit' `
        -TrueData @{ eligible_triaged_count = 4; pending_proposals = 2; max_issues_per_planning_cycle = 10; github_issue_count = 999 } `
        -FalseData @{ eligible_triaged_count = 8; pending_proposals = 2; max_issues_per_planning_cycle = 10; github_issue_count = 1 }
    Test-ConditionPair -Condition 'has_untriaged_issues' `
        -TrueData @{ data_sync_changed_issue_count = 1; triage_snapshot_current = $true } `
        -FalseData @{ data_sync_changed_issue_count = 0; triage_snapshot_current = $true }
    Test-ConditionPair -Condition 'has_approved_proposals' `
        -TrueData @{ approved_undelegated_proposal_count = 1; delegation_capacity_available = $true } `
        -FalseData @{ approved_undelegated_proposal_count = 1; delegation_capacity_available = $false } `
        -ExpectedFalseReason 'dependency_not_ready'
    Test-ConditionPair -Condition 'has_active_jules_delegations' `
        -TrueData @{ active_jules_delegation_count = 1 } `
        -FalseData @{ active_jules_delegation_count = 0 }
    Test-ConditionPair -Condition 'has_active_local_agent_sessions' `
        -TrueData @{ active_local_agent_session_count = 2 } `
        -FalseData @{ active_local_agent_session_count = 0 }
    Test-ConditionPair -Condition 'has_open_prs_requiring_review' `
        -TrueData @{ open_pr_review_count = 1 } `
        -FalseData @{ open_pr_review_count = 0 }
    Test-ConditionPair -Condition 'jules_capacity_available' `
        -TrueData @{ monitoring_refill_enabled = $true; jules_free_slots = 2; jules_quota_available = $true; delegable_task_count = 3 } `
        -FalseData @{ monitoring_refill_enabled = $true; jules_free_slots = 0; jules_quota_available = $true; delegable_task_count = 3 } `
        -ExpectedFalseReason 'dependency_not_ready'
    Test-ConditionPair -Condition 'housekeeping_due' `
        -TrueData @{ housekeeping_interval_elapsed = $true; expired_runtime_file_count = 0 } `
        -FalseData @{ housekeeping_interval_elapsed = $false; expired_runtime_file_count = 0 }
    Test-ConditionPair -Condition 'has_new_audit_inputs' `
        -TrueData @{ new_audit_input_count = 1; audit_max_interval_elapsed = $false } `
        -FalseData @{ new_audit_input_count = 0; audit_max_interval_elapsed = $false }
    Test-ConditionPair -Condition 'has_open_alerts' `
        -TrueData @{ open_alert_count = 1 } `
        -FalseData @{ open_alert_count = 0 }
    Test-ConditionPair -Condition 'optimizer_has_sufficient_samples' `
        -TrueData @{ optimizer_sample_count = 3 } `
        -FalseData @{ optimizer_sample_count = 2 } `
        -ConditionSettings @{ minimum_samples = 3 }
    Test-ConditionPair -Condition 'optimizer_has_findings' `
        -TrueData @{ optimizer_finding_count = 1 } `
        -FalseData @{ optimizer_finding_count = 0 }
    Test-ConditionPair -Condition 'optimizer_has_approved_changes' `
        -TrueData @{ optimizer_approved_change_count = 1 } `
        -FalseData @{ optimizer_approved_change_count = 0 }
    Test-ConditionPair -Condition 'optimizer_has_changes_to_evaluate' `
        -TrueData @{ optimizer_change_evaluation_count = 1 } `
        -FalseData @{ optimizer_change_evaluation_count = 0 }
    Test-ConditionPair -Condition 'memory_maintenance_due' `
        -TrueData @{ memory_interval_elapsed = $true; memory_expired_candidate_count = 0 } `
        -FalseData @{ memory_interval_elapsed = $false; memory_expired_candidate_count = 0 }
    Test-ConditionPair -Condition 'memory_has_candidates' `
        -TrueData @{ memory_candidate_count = 1 } `
        -FalseData @{ memory_candidate_count = 0 }
    Test-ConditionPair -Condition 'master_issue_context_changed' `
        -TrueData @{ changed_master_issue_count = 1 } `
        -FalseData @{ changed_master_issue_count = 0 }

    $manualNormal = Invoke-RouterTestDecision -Condition 'always' -RouterData @{} -Mode 'manual_only'
    $manualForced = Invoke-RouterTestDecision -Condition 'always' -RouterData @{} -Mode 'manual_only' -Force
    Write-VorceTestResult -Context $test -Message 'manual_only bleibt im Scheduler inaktiv' -Passed (
        -not $manualNormal.active -and $manualNormal.reason -eq 'manual_only'
    )
    Write-VorceTestResult -Context $test -Message 'manual_only wird bei explizitem Force aktiv' -Passed (
        $manualForced.active -and $manualForced.reason -eq 'active_condition_met' -and $manualForced.evidence.forced
    )

    $disabledForced = Invoke-RouterTestDecision -Condition 'always' -RouterData @{} -Mode 'manual_only' -Enabled $false -Force
    Write-VorceTestResult -Context $test -Message 'enabled=false hat auch bei Force Vorrang' -Passed (
        -not $disabledForced.active -and $disabledForced.reason -eq 'disabled_in_config'
    )

    $missingScript = Invoke-RouterTestDecision -Condition 'always' -RouterData @{} -Mode 'always' -Script 'src/does-not-exist.ps1'
    Write-VorceTestResult -Context $test -Message 'Fehlendes Script wird sicher deaktiviert' -Passed (
        -not $missingScript.active -and $missingScript.reason -eq 'script_missing'
    )

    $reuseBag = New-RouterTestBag -RouterData @{ reused_sub_runs = @('Reusable') }
    $reuseRule = [pscustomobject]@{
        id = '01'
        name = 'Reusable'
        script = $existingScript
        enabled = $true
        mode = 'always'
        condition = 'always'
        condition_settings = @{}
        dashboard_editable = $true
    }
    $reuseDecision = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $reuseBag -MainState ([pscustomobject]@{}) -Rules @($reuseRule))[0]
    Write-VorceTestResult -Context $test -Message 'Gueltiger Checkpoint wird nicht erneut ausgefuehrt' -Passed (
        -not $reuseDecision.active -and $reuseDecision.reason -eq 'reused_from_checkpoint'
    )

    $unavailableDecision = Invoke-RouterTestDecision -Condition 'master_issue_context_changed' -RouterData @{}
    Write-VorceTestResult -Context $test -Message 'Fehlende Datenquelle liefert data_source_unavailable' -Passed (
        -not $unavailableDecision.active -and $unavailableDecision.reason -eq 'data_source_unavailable'
    )

    Set-Content -LiteralPath (Join-Path $tempRoot 'db/pull-requests.json') -Value '' -Encoding UTF8
    $emptyJsonBag = New-RouterTestBag -RouterData @{} -VarDir $tempRoot
    $emptyJsonRule = New-RouterTestRule -Condition 'has_open_prs_requiring_review'
    $emptyJsonDecision = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $emptyJsonBag -MainState ([pscustomobject]@{}) -Rules @($emptyJsonRule))[0]
    Write-VorceTestResult -Context $test -Message 'Leere JSON-Datei verursacht keinen Router-Crash' -Passed (
        -not $emptyJsonDecision.active -and $emptyJsonDecision.reason -eq 'data_source_unavailable'
    )

    Remove-Item -LiteralPath (Join-Path $tempRoot 'db/pull-requests.json') -Force
    $oldPath = $env:PATH
    try {
        $env:PATH = $tempRoot
        $missingGhDecision = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $emptyJsonBag -MainState ([pscustomobject]@{}) -Rules @($emptyJsonRule))[0]
        Write-VorceTestResult -Context $test -Message 'Fehlendes gh verursacht keinen Router-Crash' -Passed (
            -not $missingGhDecision.active -and $missingGhDecision.reason -eq 'data_source_unavailable'
        )
    } finally {
        $env:PATH = $oldPath
    }

    $missingStateRule = New-RouterTestRule -Condition 'has_active_jules_delegations'
    $missingStateDecision = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $emptyJsonBag -MainState ([pscustomobject]@{}) -Rules @($missingStateRule))[0]
    Write-VorceTestResult -Context $test -Message 'Fehlende optionale State-Felder verursachen keinen Crash' -Passed (
        -not $missingStateDecision.active -and $missingStateDecision.reason -eq 'data_source_unavailable'
    )

    $prFixture = @(
        [pscustomobject]@{ number = 1; state = 'OPEN'; isDraft = $true; reviewDecision = $null },
        [pscustomobject]@{ number = 2; state = 'OPEN'; isDraft = $false; reviewDecision = 'APPROVED' },
        [pscustomobject]@{ number = 3; state = 'OPEN'; isDraft = $false; reviewDecision = 'REVIEW_REQUIRED' },
        [pscustomobject]@{ number = 4; state = 'CLOSED'; isDraft = $false; reviewDecision = 'REVIEW_REQUIRED' }
    )
    $prFixture | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $tempRoot 'db/pull-requests.json') -Encoding UTF8
    $prDecision = @(Resolve-VorceRouterDecision -MainName 'MAIN-RUN-TEST' -ConfigBag $emptyJsonBag -MainState ([pscustomobject]@{}) -Rules @($emptyJsonRule))[0]
    Write-VorceTestResult -Context $test -Message 'ReviewDispatch schliesst Drafts, abgeschlossene Reviews und geschlossene PRs aus' -Passed (
        $prDecision.active -and $prDecision.evidence.open_non_draft_prs_requiring_review -eq 1
    )

    $expectedMatrix = @{
        'Planning/DataSync' = 'always|always'
        'Planning/Triage' = 'automatic|has_untriaged_issues'
        'Planning/Strategy' = 'automatic|pipeline_below_limit'
        'Planning/Delegation' = 'automatic|has_approved_proposals'
        'CheckAndDoing/SessionSync' = 'always|always'
        'CheckAndDoing/JulesCheck' = 'automatic|has_active_jules_delegations'
        'CheckAndDoing/LocalAgentCheck' = 'automatic|has_active_local_agent_sessions'
        'CheckAndDoing/ReviewDispatch' = 'automatic|has_open_prs_requiring_review'
        'CheckAndDoing/JulesRefill' = 'automatic|jules_capacity_available'
        'CheckAndDoing/Housekeeping' = 'automatic|housekeeping_due'
        'Audit/DataSync' = 'always|always'
        'Audit/ComplianceCheck' = 'automatic|has_new_audit_inputs'
        'Audit/JulesSupervision' = 'automatic|has_active_jules_delegations'
        'Audit/AlertDisposition' = 'automatic|has_open_alerts'
        'Optimizer/PerformanceDataCollection' = 'always|always'
        'Optimizer/SystemAnalysis' = 'automatic|optimizer_has_sufficient_samples'
        'MemoryOptimization/MemoryMaintenance' = 'automatic|memory_maintenance_due'
    }

    $routerKeys = @('Planning', 'CheckAndDoing', 'Audit', 'Optimizer', 'MemoryOptimization')
    Write-VorceTestResult -Context $test -Message 'Alle 5 Router-Keys sind vorhanden' -Passed (
        @($routerKeys | Where-Object { $config.router_rules.PSObject.Properties.Name -notcontains $_ }).Count -eq 0
    )

    $allRules = @()
    foreach ($routerKey in $routerKeys) {
        foreach ($rule in @($config.router_rules.$routerKey)) {
            $allRules += [pscustomobject]@{ router_key = $routerKey; rule = $rule }
            $matrixKey = "$routerKey/$($rule.name)"
            $actualMatrixValue = "$($rule.mode)|$($rule.condition)"
            Write-VorceTestResult -Context $test -Message "Matrix $matrixKey" -Passed (
                $expectedMatrix.ContainsKey($matrixKey) -and $expectedMatrix[$matrixKey] -eq $actualMatrixValue
            )
            Write-VorceTestResult -Context $test -Message "Config-Vertrag $matrixKey vollstaendig" -Passed (
                $null -ne $rule.enabled -and
                @('always', 'automatic', 'manual_only') -contains $rule.mode -and
                $expectedWhitelist -contains $rule.condition -and
                $null -ne $rule.condition_settings -and
                $rule.dashboard_editable -eq $true
            )
            Write-VorceTestResult -Context $test -Message "Script existiert $matrixKey" -Passed (
                Test-Path -LiteralPath (Join-Path $ProjectRoot $rule.script) -PathType Leaf
            )
        }
    }
    Write-VorceTestResult -Context $test -Message 'Config enthaelt exakt 17 kanonische Router-Regeln' -Passed ($allRules.Count -eq 17)

    $integrationData = @{
        eligible_triaged_count = 1
        pending_proposals = 1
        max_issues_per_planning_cycle = 10
        data_sync_changed_issue_count = 1
        triage_snapshot_current = $false
        approved_undelegated_proposal_count = 1
        delegation_capacity_available = $true
        active_jules_delegation_count = 1
        active_local_agent_session_count = 1
        open_pr_review_count = 1
        monitoring_refill_enabled = $true
        jules_free_slots = 1
        jules_quota_available = $true
        delegable_task_count = 1
        housekeeping_interval_elapsed = $true
        expired_runtime_file_count = 0
        new_audit_input_count = 1
        audit_max_interval_elapsed = $false
        open_alert_count = 1
        optimizer_sample_count = 3
        optimizer_finding_count = 1
        optimizer_approved_change_count = 1
        optimizer_change_evaluation_count = 1
        memory_interval_elapsed = $true
        memory_expired_candidate_count = 0
        memory_candidate_count = 1
        changed_master_issue_count = 1
    }
    $routerFiles = @{
        Planning = 'src/runs/MAIN-RUN-01_Planning/Planning-Router.ps1'
        CheckAndDoing = 'src/runs/MAIN-RUN-02_CheckAndDoing/CheckAndDoing-Router.ps1'
        Audit = 'src/runs/MAIN-RUN-03_Audit/Audit-Router.ps1'
        Optimizer = 'src/runs/MAIN-RUN-04_Optimizer/Optimizer-Router.ps1'
        MemoryOptimization = 'src/runs/MAIN-RUN-05_MemoryOptimization/MemoryOptimization-Router.ps1'
    }
    foreach ($routerKey in $routerKeys) {
        $bag = New-RouterTestBag -RouterData $integrationData
        $state = [pscustomobject]@{ metadata = [ordered]@{} }
        $activeRuns = @(& (Join-Path $ProjectRoot $routerFiles[$routerKey]) -ConfigBag $bag -MainState $state)
        $decision = $state.metadata.router_decision
        $configuredCount = @($config.router_rules.$routerKey).Count
        Write-VorceTestResult -Context $test -Message "$routerKey verwendet zentralen Resolver und persistiert alle Decisions" -Passed (
            $null -ne $decision -and
            $decision.router_key -eq $routerKey -and
            @($decision.configured_sub_runs).Count -eq $configuredCount
        )
        Write-VorceTestResult -Context $test -Message "$routerKey liefert nur aktive Runs" -Passed (
            $activeRuns.Count -eq @($decision.active_sub_runs).Count -and
            @($activeRuns | Where-Object { -not $_.active }).Count -eq 0
        )
        Write-VorceTestResult -Context $test -Message "$routerKey aktive Scripts existieren" -Passed (
            @($activeRuns | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ProjectRoot $_.script) -PathType Leaf) }).Count -eq 0
        )
    }
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
