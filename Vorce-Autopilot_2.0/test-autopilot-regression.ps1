# Vorce-Autopilot/test-autopilot-regression.ps1
# Regression and smoke checks for the new parallel Vorce Autopilot structure.

[CmdletBinding()]
param(
    [switch]$SkipDashboardBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir
$DashboardDir = Join-Path $ScriptDir "dashboard"

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "[REGRESSION] $Message"
    }
}

function Assert-FileContains {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    Assert-True -Condition (Test-Path $Path) -Message "File missing: $Path"
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($pattern in $Patterns) {
        Assert-True -Condition ($content.Contains($pattern)) -Message "Expected marker missing in ${Path}: $pattern"
    }
}

# 1. Check Git status (no unmerged entries)
Push-Location $RepoRoot
try {
    $unmerged = @(git ls-files -u)
    Assert-True -Condition ($unmerged.Count -eq 0) -Message "Unmerged Git index entries are present."
} finally {
    Pop-Location
}

# 2. Source all PowerShell libraries and phase scripts
$modules = @(
    "src/lib/telemetry-manager.ps1",
    "src/lib/database-manager.ps1",
    "src/lib/state-manager.ps1",
    "src/lib/naming-convention.ps1",
    "src/lib/quota-manager.ps1",
    "src/lib/cli-router.ps1",
    "src/lib/memory-store.ps1",
    "src/lib/deliberation-engine.ps1",
    "src/lib/autopilot-session-manager.ps1",
    "src/lib/autopilot-prompts.ps1",
    "src/lib/github-client.ps1",
    "src/lib/jules-client.ps1",
    "src/phases/planning-wakeup.ps1",
    "src/phases/monitoring-wakeup.ps1",
    "src/phases/audit-wakeup.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $ScriptDir $module
    Assert-True -Condition (Test-Path $modulePath) -Message "Module script missing: $module"
    . $modulePath
}

# 3. Assert all key commands are loaded in scope
$requiredCommands = @(
    "Get-VorceConfigPrompt",
    "Confirm-WorkingSessionsState",
    "Optimize-AutopilotMemories",
    "Invoke-PlanningWakeUp",
    "Invoke-MonitoringWakeUp",
    "Invoke-AuditWakeUp",
    "Get-GitHubIssues",
    "Get-AllGitHubIssues",
    "Get-GitHubPullRequests",
    "Format-VorceIssueTitle",
    "Format-VorcePullRequestTitle",
    "New-JulesSession",
    "Get-JulesSessionStatus"
)
foreach ($commandName in $requiredCommands) {
    Assert-True -Condition ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "Required command not loaded: $commandName"
}

# 4. Verify Vorce naming convention
$defaultTitle = Format-VorceIssueTitle -Type "default" -Id 1 -Title "Analog Meter Option"
$masterTitle = Format-VorceIssueTitle -Type "master" -Id 2 -Title "Release 1.0 Readiness Gate"
$subTitle = Format-VorceIssueTitle -Type "sub_issue" -ParentMasterId 2 -SubIndex 15 -Title "Packaging Artifact"
$prTitle = Format-VorcePullRequestTitle -IssueTitle $subTitle

Assert-True -Condition ($defaultTitle -eq "*D**-001_Analog-Meter-Option") -Message "Default issue naming convention failed: $defaultTitle"
Assert-True -Condition ($masterTitle -eq "M...-002_Release-1-0-Readiness-Gate") -Message "Master issue naming convention failed: $masterTitle"
Assert-True -Condition ($subTitle -eq "___M-002_s15_Packaging-Artifact") -Message "Sub-issue naming convention failed: $subTitle"
Assert-True -Condition ($prTitle -eq "PR____M-002_s15_Packaging-Artifact") -Message "PR naming convention failed: $prTitle"
Assert-True -Condition (-not (Test-VorceIssueTitle -Title "MF-StIs_Old-Title")) -Message "Legacy issue title was incorrectly accepted."
Assert-True -Condition (-not (Test-VorcePullRequestTitle -Title $subTitle)) -Message "PR title without PR_ was incorrectly accepted."

# 5. Verify runtime helpers and routing fallbacks
$orderedResult = [ordered]@{ provider = "codex_orchestrator"; error = "CODEX_SESSION_FAILED"; output = "ERROR: usage limit exceeded" }
Assert-True -Condition (Test-ObjectProperty -Object $orderedResult -Name "provider") -Message "Ordered dictionary properties are not detected."
$formattedFailure = Format-AutopilotTaskFailure -Result $orderedResult
Assert-True -Condition ($formattedFailure -match "codex_orchestrator" -and $formattedFailure -match "usage limit") -Message "Task failure details are incomplete."
$nullConfigPrompt = Get-VorceConfigPrompt -Config $null -PromptKey "proposal" -Variables @{ contextPrompt = "test" }
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($nullConfigPrompt)) -Message "Prompt loading with null config failed."

$originalStateFilePath = $StateFilePath
$StateFilePath = Join-Path $env:TEMP "vorce-autopilot-regression-state.json"
try {
    $reviewState = New-AutopilotState
    Add-ReviewItem -State $reviewState -IssueNumber 0 -PrUrl "https://github.com/Vorce-Studios/Vorce/pull/1" -PrNumber 1 -PrUpdatedAt "2026-06-07T10:00:00Z"
    Add-ReviewItem -State $reviewState -IssueNumber 123 -PrUrl "https://github.com/Vorce-Studios/Vorce/pull/1" -PrNumber 1 -PrUpdatedAt "2026-06-07T10:00:00Z"
    Assert-True -Condition (@($reviewState.review_queue).Count -eq 1 -and [int]$reviewState.review_queue[0].issue_number -eq 123) -Message "Review queue does not deduplicate open PRs."
    $reviewState.review_queue[0].review_status = "completed"
    $reviewState.review_queue[0].reviewed_pr_updated_at = "2026-06-07T10:00:00Z"
    Add-ReviewItem -State $reviewState -IssueNumber 123 -PrUrl "https://github.com/Vorce-Studios/Vorce/pull/1" -PrNumber 1 -PrUpdatedAt "2026-06-07T11:00:00Z"
    Assert-True -Condition ($reviewState.review_queue[0].review_status -eq "pending") -Message "Updated PR was not re-queued for Claude review."
} finally {
    $StateFilePath = $originalStateFilePath
    Remove-Item -LiteralPath (Join-Path $env:TEMP "vorce-autopilot-regression-state.json") -Force -ErrorAction SilentlyContinue
}

$quotaConfig = Get-Content (Join-Path $ScriptDir "config\quota-registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True -Condition (@($quotaConfig.routing_rules.code_review).Count -eq 1 -and $quotaConfig.routing_rules.code_review[0] -eq "claude_code:balanced") -Message "PR reviews are not exclusively routed to Claude Code."
Assert-True -Condition (@($quotaConfig.routing_rules.monitoring) -contains "claude_code:balanced") -Message "Monitoring has no Claude Code fallback."

$originalDbPath = $DbPath
$DbPath = Join-Path $env:TEMP "vorce-autopilot-regression-historical-db.json"
try {
    "[]" | Set-Content -LiteralPath $DbPath -Encoding UTF8
    Save-DailyUsage -Date "2026-06-06" -ProviderName "regression" -ModelName "test" -Calls 1 -CostUsd 0 -InputTokens 0 -OutputTokens 0 -CachedTokens 0 -ReasoningTokens 0 -ToolTokens 0 -DurationMs 0
    Clear-DailyUsageForProvider -Date "2026-06-06" -ProviderName "regression"
} finally {
    $DbPath = $originalDbPath
    Remove-Item -LiteralPath (Join-Path $env:TEMP "vorce-autopilot-regression-historical-db.json") -Force -ErrorAction SilentlyContinue
}

# 6. Verify Dashboard pages content to ensure merge conflict regressions aren't present
Assert-FileContains -Path (Join-Path $DashboardDir "src\pages\DashboardPage.tsx") -Patterns @(
    "Tageskosten",
    "Jules Sessions",
    "Open PRs",
    "Abgeschlossen",
    "Audit Alerts",
    "Working Sessions",
    "Live Log"
)

Assert-FileContains -Path (Join-Path $DashboardDir "src\pages\WorkstreamsPage.tsx") -Patterns @(
    "Smart Workstreams",
    "Korrelierte Ansicht von Issues, Agent Sessions und Pull Requests",
    "Grouped",
    "Flat List",
    "Agent Session",
    "Pull Request"
)

$settingsPath = Join-Path $DashboardDir "src\pages\SettingsPage.tsx"
Assert-FileContains -Path $settingsPath -Patterns @(
    "Model Auswahl",
    "System-Prompts",
    "API Provider Quotas",
    "Routing-Regeln"
)

$intervalStatsPath = Join-Path $ScriptDir "src\phases\interval-stats.ps1"
Assert-FileContains -Path $intervalStatsPath -Patterns @(
    'Write-JsonLocked -Path (Join-Path $VarDbDir "active-sessions.json")',
    'gh project item-list 1 --owner Vorce-Studios --limit 1000'
)

$viteConfigPath = Join-Path $DashboardDir "vite.config.ts"
Assert-FileContains -Path $viteConfigPath -Patterns @(
    "/api/health",
    "../var/db/autopilot-state.json",
    "../var/db/project-items.json"
)

# 7. Build Dashboard to verify TS/Vite compilation
if (-not $SkipDashboardBuild.IsPresent) {
    Push-Location $DashboardDir
    try {
        Write-Host "Verifying Vite dashboard build..." -ForegroundColor Cyan
        npm run build
        if ($LASTEXITCODE -ne 0) {
            throw "npm run build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

Write-Host "[REGRESSION] Autopilot parallel structure checks passed." -ForegroundColor Green

Write-Host "Running Quota Manager Unit Tests..." -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "test\ut-quota-manager.ps1")

Write-Host "Running Planning Cycle Integration Tests..." -ForegroundColor Cyan
& pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir "test\it-planning-cycle.ps1")
