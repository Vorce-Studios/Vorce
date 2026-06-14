# src/runs/SUB-RUN/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1
# Synced Working-Session-Status aus Status-Files und startet QUEUED Sessions
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-01 SessionSync: Synchronisiere Session-Status..." -ForegroundColor Cyan

$repo = $Config.repository
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"
if ($null -eq (Get-Variable -Name "VorceAutopilotStateFilePath" -Scope Global -ErrorAction SilentlyContinue)) {
    $global:VorceAutopilotStateFilePath = Join-Path $VarDbDir "active-sessions.json"
}

Confirm-WorkingSessionsState -State $GlobalState

# --- 1. Sync Working Sessions from Status Files ---
foreach ($workSession in @($GlobalState.working_sessions)) {
    $currentStatus = ([string]$workSession.status).ToUpperInvariant()
    if ($currentStatus -notin @("IN_PROGRESS", "RUNNING", "INITIALIZING")) { continue }

    $issueNum = [int]$workSession.issue_number
    $statusFile = Join-Path $VarDbDir "agent-tasks/$issueNum.json"
    if (Test-Path -LiteralPath $statusFile) {
        try {
            $agentState = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if (Test-ObjectProperty -Object $agentState -Name "status") {
                $workSession.status = [string]$agentState.status
                $workSession | Add-Member -MemberType NoteProperty -Name "last_checked_at" -Value (Get-Date -Format 'o') -Force
                if (Test-ObjectProperty -Object $agentState -Name "error") {
                    $workSession | Add-Member -MemberType NoteProperty -Name "error" -Value ([string]$agentState.error) -Force
                }
                if (Test-ObjectProperty -Object $agentState -Name "updated_at") {
                    $workSession | Add-Member -MemberType NoteProperty -Name "status_updated_at" -Value ([string]$agentState.updated_at) -Force
                }
                if (Test-ObjectProperty -Object $agentState -Name "pr_url") {
                    $workSession | Add-Member -MemberType NoteProperty -Name "pr_url" -Value ([string]$agentState.pr_url) -Force
                }
                continue
            }
        } catch {
            Write-Warning "[CHECK&DOING] Working Session #$issueNum Statusfile konnte nicht gelesen werden: $_"
        }
    }

    if ((Test-ObjectProperty -Object $workSession -Name "process_id") -and $workSession.process_id) {
        $proc = Get-Process -Id ([int]$workSession.process_id) -ErrorAction SilentlyContinue
        if ($null -eq $proc) {
            $workSession.status = "FAILED"
            $workSession | Add-Member -MemberType NoteProperty -Name "last_checked_at" -Value (Get-Date -Format 'o') -Force
            $workSession | Add-Member -MemberType NoteProperty -Name "error" -Value "Local agent process exited before writing a final status." -Force
            $failedState = [pscustomobject]@{
                status = "FAILED"
                pr_url = ""
                updated_at = (Get-Date -Format 'o')
                error = "Local agent process exited before writing a final status."
            }
            Write-JsonLocked -Path $statusFile -Data $failedState | Out-Null
            Write-Host "[CHECK&DOING] Working Session #$issueNum als FAILED markiert: PID $($workSession.process_id) laeuft nicht mehr." -ForegroundColor Yellow
        }
    }
}

# --- 2. Import Stalled Jules Sessions ---
$sessionCachePath = Join-Path $VarDbDir "jules-sessions.json"
if (-not (Test-Path -LiteralPath $sessionCachePath)) {
    $dashboardSessionCachePath = Join-Path $ScriptDir "dashboard/jules-sessions.json"
    if (Test-Path -LiteralPath $dashboardSessionCachePath) {
        $sessionCachePath = $dashboardSessionCachePath
    }
}

if (Test-Path -LiteralPath $sessionCachePath) {
    $sessions = @()
    try {
        $sessions = @(Get-Content -LiteralPath $sessionCachePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warning "[CHECK&DOING] Konnte Jules Session Cache nicht lesen: $_"
    }

    $activeIssueNumbers = @($GlobalState.active_delegations | Where-Object {
        -not (Test-ObjectProperty -Object $_ -Name "agent_type") -or [string]$_.agent_type -eq "jules"
    } | ForEach-Object { [int]$_.issue_number })

    foreach ($session in $sessions) {
        $stateName = if (Test-ObjectProperty -Object $session -Name "state") { [string]$session.state } else { "" }
        if ($stateName -notin @("AWAITING_USER_FEEDBACK", "PAUSED", "FAILED")) { continue }
        if ((Test-ObjectProperty -Object $session -Name "repo") -and -not [string]::IsNullOrWhiteSpace([string]$session.repo) -and [string]$session.repo -ne $repo) { continue }
        if (-not (Test-ObjectProperty -Object $session -Name "issueNumber") -or $null -eq $session.issueNumber) {
            $sessionTitle = if (Test-ObjectProperty -Object $session -Name "title") { [string]$session.title } else { "(ohne Titel)" }
            if ($DryRun.IsPresent) {
                Write-Host "[CHECK&DOING] [DRY RUN] Unzugeordnete haengende Jules Session gefunden: $sessionTitle ($stateName)" -ForegroundColor DarkYellow
            } else {
                Add-DecisionPending -State $GlobalState -Topic "Unzugeordnete Jules Session braucht Klaerung" -Context "Session '$sessionTitle' ($stateName) hat keine Issue-Nummer und kann nicht automatisch sauber weitergefuehrt werden. URL: $($session.url)"
            }
            continue
        }

        $issueNum = [int]$session.issueNumber
        if ($activeIssueNumbers -contains $issueNum) { continue }

        $sessionTitle = if (Test-ObjectProperty -Object $session -Name "title") { [string]$session.title } else { "Issue #$issueNum" }
        if ($sessionTitle -match "_MAIs_" -or $sessionTitle -match "Resolve-Merge-Conflicts?") {
            if ($DryRun.IsPresent) {
                Write-Host "[CHECK&DOING] [DRY RUN] Haengende Jules Session #$issueNum wegen unsicherem Scope blockiert." -ForegroundColor DarkYellow
            } else {
                Add-DecisionPending -State $GlobalState -Topic "Jules Session #$issueNum blockiert durch unsicheren Scope" -Context "Session fuer Issue #$issueNum ist '$stateName', wird aber nicht automatisch neu gestartet/weitergetrieben, weil Titel/Scope nach Master-, Tracker- oder Konfliktauftrag aussieht. URL: $($session.url)"
            }
            continue
        }

        $sessionId = Get-CheckDoingSessionId -Session $session
        if ([string]::IsNullOrWhiteSpace($sessionId)) { continue }

        if ($DryRun.IsPresent) {
            Write-Host "[CHECK&DOING] [DRY RUN] Wuerde haengende Jules Session fuer Issue #$issueNum importieren ($stateName)." -ForegroundColor DarkYellow
            continue
        }

        Add-Delegation -State $GlobalState -IssueNumber $issueNum -IssueTitle $sessionTitle -JulesSessionId $sessionId -AgentType "jules"
        Update-DelegationState -State $GlobalState -IssueNumber $issueNum -JulesState $stateName
        Write-Host "[CHECK&DOING] Importierte haengende Jules Session fuer Issue #$issueNum ($stateName)." -ForegroundColor Yellow
    }
}

# --- 3. Start Queued Working Sessions ---
$toolsDir = Join-Path $ScriptDir "tools"
$quotaRegistryPath = Join-Path $ScriptDir "config/quota-registry.json"

$workingCfg = if (Test-ObjectProperty -Object $Config -Name "working_sessions") { $Config.working_sessions } else { $null }
$wsEnabled = $true
if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "enabled") -and -not $workingCfg.enabled) {
    $wsEnabled = $false
}

$maxConcurrent = if ($workingCfg -and (Test-ObjectProperty -Object $workingCfg -Name "max_concurrent")) { [int]$workingCfg.max_concurrent } else { 3 }

if ($wsEnabled -and $maxConcurrent -gt 0) {
    $running = @($GlobalState.working_sessions | Where-Object { [string]$_.status -eq "IN_PROGRESS" }).Count
    $slots = $maxConcurrent - $running
    if ($slots -gt 0 -and @($GlobalState.working_queue).Count -gt 0) {
        $toStart = @($GlobalState.working_queue | Select-Object -First $slots)
        foreach ($item in $toStart) {
            $issueNum = [int]$item.issue_number
            $issueTitle = [string]$item.issue_title
            $agentProvider = [string]$item.agent_provider

            if ($DryRun.IsPresent) {
                Write-Host "[CHECK&DOING] [DRY RUN] Wuerde Working Session starten: #$issueNum -> $agentProvider" -ForegroundColor DarkYellow
                continue
            }

            try {
                $cmdArgs = "-NoProfile", "-File", "`"$toolsDir\run-local-agent-task.ps1`"", "-IssueNumber", $issueNum, "-IssueTitle", "`"$issueTitle`"", "-AgentProvider", "`"$agentProvider`"", "-Repository", "`"$repo`"", "-QuotaRegistryPath", "`"$quotaRegistryPath`""
                $proc = Start-Process pwsh -ArgumentList $cmdArgs -PassThru -WindowStyle Normal

                $GlobalState.working_sessions += @([ordered]@{
                    id             = if (Test-ObjectProperty -Object $item -Name "id") { $item.id } else { "work-$issueNum-$($proc.Id)" }
                    issue_number   = $issueNum
                    issue_title    = $issueTitle
                    agent_provider = $agentProvider
                    process_id     = $proc.Id
                    status         = "IN_PROGRESS"
                    started_at     = (Get-Date -Format 'o')
                })
                $GlobalState.working_queue = @($GlobalState.working_queue | Where-Object { [int]$_.issue_number -ne $issueNum })
                Add-Delegation -State $GlobalState -IssueNumber $issueNum -IssueTitle $issueTitle -JulesSessionId "local-agent-$($proc.Id)" -AgentType $agentProvider -JobId $($proc.Id.ToString())
                Write-Host "[CHECK&DOING] Working Session gestartet: #$issueNum -> $agentProvider (PID: $($proc.Id))" -ForegroundColor Cyan
            } catch {
                Write-Warning "[CHECK&DOING] Working Session fuer #$issueNum fehlgeschlagen: $_"
                Add-ErrorLog -State $GlobalState -Message "Working session failed for #$issueNum" -Context $_.Exception.Message
            }
        }
        Save-AutopilotState -State $GlobalState
    }
}

$SubState.status = "completed"
$SubState.artifacts += @{
    type = "SessionSyncReport"
    timestamp = (Get-Date).ToString('o')
    working_sessions = @($GlobalState.working_sessions).Count
    working_queue = @($GlobalState.working_queue).Count
}
