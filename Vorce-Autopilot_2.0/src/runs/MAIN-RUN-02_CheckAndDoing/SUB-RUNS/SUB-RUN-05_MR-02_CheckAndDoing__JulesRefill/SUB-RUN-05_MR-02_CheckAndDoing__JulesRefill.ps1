# src/runs/SUB-RUN/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill.ps1
# Fuellt freie Jules-Slots mit sicheren Kandidaten auf
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-05 JulesRefill: Pruefe freie Jules-Slots..." -ForegroundColor Cyan

$repo = $Config.repository
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

if (-not (Test-ObjectProperty -Object $Config -Name "jules") -or -not (Test-ObjectProperty -Object $Config.jules -Name "monitoring_refill_enabled") -or -not [bool]$Config.jules.monitoring_refill_enabled) {
    Write-Host "[CHECK&DOING] Jules Refill deaktiviert (Config)." -ForegroundColor DarkGray
    $SubState.status = "skipped"
    return
}

$julesProvider = $QuotaRegistry.providers.jules
$usage = $julesProvider.usage_today
$maxConcurrent = [int]$Config.jules.max_concurrent_sessions
$maxDaily = [int]$Config.jules.max_daily_sessions
$callsToday = if (Test-ObjectProperty -Object $usage -Name "calls") { [int]$usage.calls } else { 0 }

$trackedLive = @($GlobalState.active_delegations | Where-Object {
    (-not (Test-ObjectProperty -Object $_ -Name "agent_type") -or [string]$_.agent_type -eq "jules") -and
    (Test-CheckDoingJulesCapacityState -State $(if (Test-ObjectProperty -Object $_ -Name "jules_state") { [string]$_.jules_state } else { "QUEUED" }))
}).Count
$apiLive = if (Test-ObjectProperty -Object $usage -Name "scoped_live_capacity_sessions") { [int]$usage.scoped_live_capacity_sessions } elseif (Test-ObjectProperty -Object $usage -Name "live_capacity_sessions") { [int]$usage.live_capacity_sessions } else { 0 }
$liveCount = [Math]::Max($trackedLive, $apiLive)
$slots = [Math]::Min($maxConcurrent - $liveCount, $maxDaily - $callsToday)
if ($slots -le 0) {
    Write-Host "[CHECK&DOING] Jules Refill: keine freien Slots (live=$liveCount, daily=$callsToday/$maxDaily)." -ForegroundColor DarkGray
    $SubState.status = "skipped"
    return
}

$issues = @()
$cachedIssuePath = Join-Path $VarDbDir "github-issues.json"
if (Test-Path -LiteralPath $cachedIssuePath) {
    try { $issues = @(Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_.repo -eq $repo -and $_.state -eq "OPEN" }) } catch { $issues = @() }
}
if ($issues.Count -eq 0) {
    try { $issues = @(Get-GitHubIssues -Repository $repo -Limit 100) } catch { $issues = @() }
}

$activeIssueNumbers = @($GlobalState.active_delegations | ForEach-Object { [int]$_.issue_number })
$candidates = @()
foreach ($issue in @($issues | Sort-Object @{ Expression = { [int]$_.number } })) {
    $labels = @(Get-CheckDoingLabelNames -Issue $issue)
    $hasJulesLabel = ($labels -contains "jules-task") -or ($labels -contains "Todo-UserISU")
    $hasExcludedStatus = @($labels | Where-Object { $_ -in @("status: in-progress", "status: needs-review", "status: needs-testing", "status: blocked", "status: ready-to-merge", "duplicate", "wontfix", "on-hold") }).Count -gt 0
    $hasOtherAgent = @($labels | Where-Object { $_ -match "^agent:" -and $_ -ne "agent:jules" }).Count -gt 0
    $issueNum = [int]$issue.number
    $title = [string]$issue.title
    $body = if ((Test-ObjectProperty -Object $issue -Name "body") -and $null -ne $issue.body) { [string]$issue.body } else { "" }
    $hasJulesSessionMarker = Test-CheckDoingIssueHasJulesSession -Issue $issue

    if (-not $hasJulesLabel) { continue }
    if ($hasExcludedStatus -or $hasOtherAgent -or ($activeIssueNumbers -contains $issueNum)) {
        continue
    }

    $unsafeReason = Get-CheckDoingJulesSafetyReason -Title $title -Body $body
    if ([string]::IsNullOrWhiteSpace($unsafeReason)) {
        if ($hasJulesSessionMarker) {
            Write-Host "[CHECK&DOING] Jules-Task #$issueNum uebersprungen: vorhandene Jules-Session wird nicht dupliziert." -ForegroundColor DarkGray
            continue
        }
        $candidates += @($issue)
        continue
    }

    if (Test-CheckDoingLocalCliIssue -Title $title -Body $body) {
        if ($DryRun.IsPresent) {
            Write-Host "[CHECK&DOING] [DRY RUN] Wuerde unsicheren Jules-Task #$issueNum lokal einplanen: $unsafeReason" -ForegroundColor DarkYellow
        } else {
            Add-CheckDoingWorkingQueueItem -State $GlobalState -IssueNumber $issueNum -IssueTitle $title -AgentProvider "gemini_cli"
            Write-Host "[CHECK&DOING] Jules-Task #$issueNum zu lokaler CLI-Queue umgebogen: $unsafeReason" -ForegroundColor Yellow
        }
        continue
    }

    Write-Host "[CHECK&DOING] Jules-Task #$issueNum blockiert: $unsafeReason" -ForegroundColor Yellow
}

if ($candidates.Count -eq 0) {
    Write-Host "[CHECK&DOING] Jules Refill: freie Slots vorhanden, aber keine sicheren Jules-Kandidaten gefunden." -ForegroundColor Yellow
    if (-not $DryRun.IsPresent) {
        Save-AutopilotState -State $GlobalState
    }
    $SubState.status = "completed"
    return
}

foreach ($issue in @($candidates | Select-Object -First $slots)) {
    $issueNum = [int]$issue.number
    $issueTitle = [string]$issue.title
    if ($DryRun.IsPresent) {
        Write-Host "[CHECK&DOING] [DRY RUN] Wuerde Jules Refill starten: Issue #$issueNum - $issueTitle" -ForegroundColor DarkYellow
        continue
    }

    try {
        $sessionId = New-JulesSession -IssueNumber $issueNum -Repository $repo -ApiKey $env:JULES_API_KEY -AutoCreatePr
        Add-Delegation -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId $sessionId -AgentType "jules"
        Register-ProviderCall -Registry $QuotaRegistry -ProviderName "jules"
        Write-Host "[CHECK&DOING] Jules Refill gestartet: Issue #$issueNum -> Session $sessionId" -ForegroundColor Green
    } catch {
        Write-Warning "[CHECK&DOING] Jules refill failed for #${issueNum}: $_"
        Add-ErrorLog -State $GlobalState -Message "Jules refill failed for #$issueNum" -Context $_.Exception.Message
    }
}

$SubState.status = "completed"
