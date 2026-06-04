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
    "Get-GitHubPullRequests",
    "New-JulesSession",
    "Get-JulesSessionStatus"
)
foreach ($commandName in $requiredCommands) {
    Assert-True -Condition ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "Required command not loaded: $commandName"
}

# 4. Verify Dashboard pages content to ensure merge conflict regressions aren't present
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

# 5. Build Dashboard to verify TS/Vite compilation
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
