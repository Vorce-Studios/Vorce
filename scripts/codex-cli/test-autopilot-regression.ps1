# scripts/codex-cli/test-autopilot-regression.ps1
# Smoke checks for the Vorce Autopilot files that have regressed during merges.

[CmdletBinding()]
param(
    [switch]$SkipDashboardBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
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

function Assert-FileDoesNotContain {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    Assert-True -Condition (Test-Path $Path) -Message "File missing: $Path"
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    foreach ($pattern in $Patterns) {
        Assert-True -Condition (-not $content.Contains($pattern)) -Message "Unexpected stale marker in ${Path}: $pattern"
    }
}

Push-Location $RepoRoot
try {
    $unmerged = @(git ls-files -u)
    Assert-True -Condition ($unmerged.Count -eq 0) -Message "Unmerged Git index entries are present."
} finally {
    Pop-Location
}

Assert-True -Condition (-not (Test-Path (Join-Path $ScriptDir "ROADMAP.md"))) -Message "Obsolete scripts/codex-cli/ROADMAP.md exists again."

. (Join-Path $ScriptDir "lib\state-manager.ps1")
. (Join-Path $ScriptDir "lib\quota-manager.ps1")
. (Join-Path $ScriptDir "lib\cli-router.ps1")
. (Join-Path $ScriptDir "lib\memory-store.ps1")
. (Join-Path $ScriptDir "lib\deliberation-engine.ps1")
. (Join-Path $ScriptDir "lib\autopilot-session-manager.ps1")
. (Join-Path $ScriptDir "lib\autopilot-prompts.ps1")
. (Join-Path $ScriptDir "phases\planning-wakeup.ps1")
. (Join-Path $ScriptDir "phases\monitoring-wakeup.ps1")
. (Join-Path $ScriptDir "phases\audit-wakeup.ps1")

$requiredCommands = @(
    "Get-VorceConfigPrompt",
    "Get-VorceLagebildSummary",
    "Confirm-WorkingSessionsState",
    "Optimize-AutopilotMemories",
    "Invoke-PlanningWakeUp",
    "Invoke-MonitoringWakeUp",
    "Invoke-AuditWakeUp"
)
foreach ($commandName in $requiredCommands) {
    Assert-True -Condition ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) -Message "Required command not loaded: $commandName"
}

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

if (-not $SkipDashboardBuild.IsPresent) {
    Push-Location $DashboardDir
    try {
        npm run build
    } finally {
        Pop-Location
    }
}

Write-Host "[REGRESSION] Autopilot smoke checks passed." -ForegroundColor Green
