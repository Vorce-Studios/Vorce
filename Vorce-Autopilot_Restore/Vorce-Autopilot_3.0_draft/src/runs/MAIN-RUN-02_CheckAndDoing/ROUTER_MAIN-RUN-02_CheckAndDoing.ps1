# src/runs/ROUTER/ROUTER_MAIN-RUN-02_CheckAndDoing.ps1
# Smart Router fuer den Check&Doing-Modus (ehemals Monitoring)

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
if (-not (Get-Command Test-ObjectProperty -ErrorAction SilentlyContinue)) {
    . (Join-Path $ScriptDir "src/lib/state/state-manager.ps1")
}
param(
    [object]$GlobalState,
    [object]$Config,
    [object]$MainState,
    [object]$QuotaRegistry
)

Write-Host "`n[ROUTER] Validiere dynamische Routing-Regeln fuer Check&Doing..." -ForegroundColor Magenta

$definitions = @()
$idx = 1

function Add-Def {
    param([string]$Name, [string]$Script)
    $Script:definitions += @{
        id     = "{0:D2}" -f $Script:idx
        name   = $Name
        script = $Script
    }
    $Script:idx++
}

# 1. SessionSync laeuft IMMER (leichtgewichtig, nur Status-Files lesen)
Add-Def -Name "SessionSync" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1"
Write-Host "[ROUTER]   -> SessionSync: ENABLED (Laeuft immer)" -ForegroundColor Green

# 2. JulesCheck: Nur wenn Jules-Delegierungen existieren
$julesDelegations = @($GlobalState.active_delegations | Where-Object {
    $at = if ($_.PSObject.Properties.Name -contains "agent_type" -and $_.agent_type) { [string]$_.agent_type } else { "jules" }
    $sid = [string]$_.jules_session_id
    $at -eq "jules" -and -not ($sid -match "^local-agent-") -and -not ($sid -match "^dry-run")
})
if ($julesDelegations.Count -gt 0) {
    Add-Def -Name "JulesCheck" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck.ps1"
    Write-Host "[ROUTER]   -> JulesCheck: ENABLED ($($julesDelegations.Count) aktive Jules-Sessions)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> JulesCheck: DISABLED (Keine aktiven Jules-Sessions)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_JulesCheck"] = @{ reason = "no_jules_delegations"; timestamp = (Get-Date).ToString('o') }
}

# 3. LocalAgentCheck: Nur wenn lokale Agent-Sessions laufen
$localDelegations = @($GlobalState.active_delegations | Where-Object {
    $at = if ($_.PSObject.Properties.Name -contains "agent_type" -and $_.agent_type) { [string]$_.agent_type } else { "jules" }
    $sid = [string]$_.jules_session_id
    ($at -ne "jules") -or ($sid -match "^local-agent-")
})
if ($localDelegations.Count -gt 0) {
    Add-Def -Name "LocalAgentCheck" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck.ps1"
    Write-Host "[ROUTER]   -> LocalAgentCheck: ENABLED ($($localDelegations.Count) lokale Agent-Sessions)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> LocalAgentCheck: DISABLED (Keine lokalen Agent-Sessions)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_LocalAgentCheck"] = @{ reason = "no_local_delegations"; timestamp = (Get-Date).ToString('o') }
}

# 4. ReviewDispatch: Nur wenn offene PRs oder pending Reviews existieren
$hasPendingReviews = @($GlobalState.review_queue | Where-Object { $_.review_status -eq "pending" }).Count -gt 0
$hasOpenDelegations = @($GlobalState.active_delegations).Count -gt 0
if ($hasPendingReviews -or $hasOpenDelegations) {
    Add-Def -Name "ReviewDispatch" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1"
    $reason = if ($hasPendingReviews) { "Pending Reviews vorhanden" } else { "Offene Delegierungen vorhanden" }
    Write-Host "[ROUTER]   -> ReviewDispatch: ENABLED ($reason)" -ForegroundColor Green
} else {
    Write-Host "[ROUTER]   -> ReviewDispatch: DISABLED (Keine PRs/Reviews)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_ReviewDispatch"] = @{ reason = "no_pending_reviews"; timestamp = (Get-Date).ToString('o') }
}

# 5. JulesRefill: Nur wenn monitoring_refill_enabled UND freie Slots
$refillEnabled = (Test-ObjectProperty -Object $Config -Name "jules") -and
                 (Test-ObjectProperty -Object $Config.jules -Name "monitoring_refill_enabled") -and
                 [bool]$Config.jules.monitoring_refill_enabled
if ($refillEnabled) {
    $julesProvider = $QuotaRegistry.providers.jules
    $usage = $julesProvider.usage_today
    $maxConcurrent = [int]$Config.jules.max_concurrent_sessions
    $maxDaily = [int]$Config.jules.max_daily_sessions
    $callsToday = if (Test-ObjectProperty -Object $usage -Name "calls") { [int]$usage.calls } else { 0 }
    $trackedLive = @($GlobalState.active_delegations | Where-Object {
        (-not (Test-ObjectProperty -Object $_ -Name "agent_type") -or [string]$_.agent_type -eq "jules") -and
        (Test-CheckDoingJulesCapacityState -State $(if (Test-ObjectProperty -Object $_ -Name "jules_state") { [string]$_.jules_state } else { "QUEUED" }))
    }).Count
    $liveCount = $trackedLive
    $slots = [Math]::Min($maxConcurrent - $liveCount, $maxDaily - $callsToday)

    if ($slots -gt 0) {
        Add-Def -Name "JulesRefill" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill.ps1"
        Write-Host "[ROUTER]   -> JulesRefill: ENABLED ($slots freie Slots)" -ForegroundColor Green
    } else {
        Write-Host "[ROUTER]   -> JulesRefill: DISABLED (Keine freien Jules-Slots)" -ForegroundColor DarkGray
        $MainState.metadata["skipped_JulesRefill"] = @{ reason = "no_free_slots"; timestamp = (Get-Date).ToString('o') }
    }
} else {
    Write-Host "[ROUTER]   -> JulesRefill: DISABLED (Config: monitoring_refill_enabled=false)" -ForegroundColor DarkGray
    $MainState.metadata["skipped_JulesRefill"] = @{ reason = "refill_disabled"; timestamp = (Get-Date).ToString('o') }
}

# 6. Housekeeping laeuft IMMER
Add-Def -Name "Housekeeping" -Script "src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping.ps1"
Write-Host "[ROUTER]   -> Housekeeping: ENABLED (Laeuft immer)" -ForegroundColor Green

return $definitions
