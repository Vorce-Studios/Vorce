# scripts/codex-cli/phases/monitoring-wakeup.ps1
# Monitoring Mode: Granular working sessions for health checks

Set-StrictMode -Version Latest

# Load local libraries
$script:PhaseDir = Split-Path -Parent $PSCommandPath
$script:LibDir = Join-Path (Split-Path -Parent $script:PhaseDir) "lib"
$script:CodexRoot = Split-Path -Parent $script:PhaseDir
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $script:CodexRoot)
. (Join-Path $script:LibDir "autopilot-prompts.ps1")

function Ensure-WorkingSessionsState {
    param([Parameter(Mandatory)][object]$State)
    if (-not ($State.PSObject.Properties.Name -contains "working_sessions") -or $null -eq $State.working_sessions) {
        $State | Add-Member -MemberType NoteProperty -Name "working_sessions" -Value @() -Force
    } elseif ($State.working_sessions -isnot [System.Array] -and $State.working_sessions -isnot [System.Collections.IList]) {
        $State.working_sessions = @($State.working_sessions)
    }
}

function Get-WorkingSessionProperty {
    param([object]$Session, [string]$Name, $Default = $null)
    if ($null -ne $Session -and $Session.PSObject.Properties.Name -contains $Name) { return $Session.$Name }
    return $Default
}

function Sync-WorkingSessions {
    param([Parameter(Mandatory)][object]$State)

    Ensure-WorkingSessionsState -State $State
    foreach ($session in @($State.working_sessions)) {
        $status = [string](Get-WorkingSessionProperty -Session $session -Name "status" -Default "")
        if ($status -notin @("RUNNING", "QUEUED")) { continue }

        $statusFile = [string](Get-WorkingSessionProperty -Session $session -Name "status_file" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($statusFile) -and (Test-Path -LiteralPath $statusFile)) {
            try {
                $taskStatus = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($taskStatus.PSObject.Properties.Name -contains "status") {
                    $session.status = [string]$taskStatus.status
                    $session.updated_at = (Get-Date -Format 'o')
                }
                if ($taskStatus.PSObject.Properties.Name -contains "pr_url" -and -not [string]::IsNullOrWhiteSpace([string]$taskStatus.pr_url)) {
                    $session.pr_url = [string]$taskStatus.pr_url
                }
            } catch {
                Write-Warning "[MONITOR] Working-Session Status konnte nicht gelesen werden: $statusFile"
            }
        }

        $pidValue = Get-WorkingSessionProperty -Session $session -Name "process_id" -Default $null
        if ($status -eq "RUNNING" -and $pidValue) {
            $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
            if ($null -eq $process -and [string](Get-WorkingSessionProperty -Session $session -Name "status" -Default "") -eq "RUNNING") {
                $session.status = "FAILED"
                $session.updated_at = (Get-Date -Format 'o')
                Write-Warning "[MONITOR] Working Session #$($session.issue_number) Prozess nicht mehr aktiv, Status auf FAILED gesetzt."
            }
        }
    }
}

function Start-QueuedWorkingSessions {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [switch]$DryRun
    )

    Ensure-WorkingSessionsState -State $State
    $maxConcurrent = 3
    if ($Config.PSObject.Properties.Name -contains "working_sessions" -and $Config.working_sessions -and ($Config.working_sessions.PSObject.Properties.Name -contains "max_concurrent")) {
        $maxConcurrent = [int]$Config.working_sessions.max_concurrent
    }

    $running = @($State.working_sessions | Where-Object { [string](Get-WorkingSessionProperty -Session $_ -Name "status" -Default "") -eq "RUNNING" }).Count
    $queued = @($State.working_sessions | Where-Object { [string](Get-WorkingSessionProperty -Session $_ -Name "status" -Default "") -eq "QUEUED" })
    if ($queued.Count -eq 0) { return }

    $toolsDir = Join-Path $script:CodexRoot "tools"
    $runner = Join-Path $toolsDir "run-visible-agent-task.ps1"
    $quotaPath = Join-Path $script:CodexRoot "quota-registry.json"
    $tasksDir = Join-Path (Join-Path $script:CodexRoot "tmp") "agent-tasks"
    if (-not (Test-Path -LiteralPath $tasksDir)) { New-Item -ItemType Directory -Path $tasksDir -Force | Out-Null }
    $powerShellHost = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($powerShellHost) { $powerShellHost = $powerShellHost.Source } else { $powerShellHost = (Get-Command powershell -ErrorAction Stop).Source }

    foreach ($session in $queued) {
        if ($running -ge $maxConcurrent) { break }

        $issueNumber = [int](Get-WorkingSessionProperty -Session $session -Name "issue_number" -Default 0)
        $issueTitle = [string](Get-WorkingSessionProperty -Session $session -Name "issue_title" -Default "")
        $agentProvider = [string](Get-WorkingSessionProperty -Session $session -Name "agent_provider" -Default "gemini_cli")
        $promptHint = [string](Get-WorkingSessionProperty -Session $session -Name "prompt_hint" -Default "")
        $statusFile = Join-Path $tasksDir "$issueNumber.json"

        if ($DryRun.IsPresent) {
            Write-Host "[DRY-RUN] Working Session wuerde starten: #$issueNumber -> $agentProvider" -ForegroundColor Yellow
            continue
        }

        $args = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $runner,
            "-IssueNumber", $issueNumber,
            "-IssueTitle", $issueTitle,
            "-AgentProvider", $agentProvider,
            "-Repository", $Config.repository,
            "-QuotaRegistryPath", $quotaPath,
            "-PromptHint", $promptHint
        )

        $process = Start-Process -FilePath $powerShellHost -ArgumentList $args -WorkingDirectory $script:RepoRoot -WindowStyle Hidden -PassThru
        $session.status = "RUNNING"
        $session.process_id = $process.Id
        $session.status_file = $statusFile
        $session.started_at = (Get-Date -Format 'o')
        $session.updated_at = (Get-Date -Format 'o')
        $running++
        Write-Host "[MONITOR] Working Session gestartet: #$issueNumber -> $agentProvider (PID $($process.Id))" -ForegroundColor Green
    }
}

function Invoke-MonitoringWakeUp {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $repo = $Config.repository
    Write-Host "`n[MONITOR] ========== Monitoring Wake-Up (Granular) ==========" -ForegroundColor Blue
    Ensure-WorkingSessionsState -State $State
    Sync-WorkingSessions -State $State
    Start-QueuedWorkingSessions -State $State -Config $Config -DryRun:$DryRun

    $monitoringContext = ""
    $prsData = gh pr list --repo $repo --state open --json number,title,mergeable,statusCheckRollup --limit 50
    $sessionsData = $State.active_delegations | ConvertTo-Json -Depth 5

    if ($Config.PSObject.Properties.Name -contains "monitoring_sequence") {
        foreach ($step in $Config.monitoring_sequence) {
            Write-Host "[MONITOR] Schritt: $($step.label) ($($step.tier))" -ForegroundColor Cyan
            $promptVars = @{ repo = $repo; prs = $prsData; sessions = $sessionsData; context = $monitoringContext }
            $stepPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey $step.prompt_ref -Variables $promptVars
            $fullPrompt = "$(Get-VorceDashboardDataInstructions)`n`n$stepPrompt"

            $stepResult = Invoke-DualCeoTask -QuotaRegistry $QuotaRegistry -Config $Config -TaskType "monitoring" -DryRun:$DryRun -Prompt $fullPrompt -State $State -AlphaTierOverride $step.tier
            if ($stepResult.success) {
                $monitoringContext += "`n### Ergebnis $($step.label):`n$($stepResult.output)`n"
            }
        }
    }

    $State.last_monitoring_at = (Get-Date -Format 'o')
    Save-AutopilotState -State $State
    Write-Host "[MONITOR] ========== Monitoring abgeschlossen ==========" -ForegroundColor Magenta
}
