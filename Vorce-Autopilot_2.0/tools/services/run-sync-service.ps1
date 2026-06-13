# Vorce-Autopilot/src/phases/interval-stats.ps1
# Synchronisiert Datenbank, Registry und GitHub Issues für das Dashboard

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")
. (Join-Path $ScriptDir "src/lib/quota-manager.ps1")
. (Join-Path $ScriptDir "src/lib/database-manager.ps1")
. (Join-Path $ScriptDir "src/lib/telemetry-manager.ps1")

$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$JulesScriptDir = Join-Path $RepoRoot "scripts/jules"
. (Join-Path $JulesScriptDir "jules-api.ps1")

$VarDbDir = Join-Path $ScriptDir "var/db"
if (-not (Test-Path $VarDbDir)) { New-Item -ItemType Directory -Path $VarDbDir | Out-Null }

$ConfigPath = Join-Path $ScriptDir "config/autopilot-config.json"
$Config = if (Test-Path $ConfigPath) { Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$Repository = if ($Config -and -not [string]::IsNullOrWhiteSpace([string]$Config.repository)) { [string]$Config.repository } else { "Vorce-Studios/Vorce" }
$StatePath = Join-Path $VarDbDir "autopilot-state.json"

$lastGhFetch = [datetime]::MinValue
$dashboardSyncIntervalSec = 60
$ghFetchIntervalSec = 300 # Alle 5 Minuten GitHub und PRs abfragen

function Add-SchedulerSnapshot {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config
    )

    $now = Get-Date
    $planMinutes = [int]$Config.wake_intervals.planning_minutes
    $checkAndDoingMinutes = [int]$Config.wake_intervals.check_and_doing_minutes

    $lastPlanning = $null
    $lastCheckAndDoing = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$State.last_planning_at)) {
            $lastPlanning = [datetimeoffset]::Parse([string]$State.last_planning_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
        }
    } catch { }
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$State.last_check_and_doing_at)) {
            $lastCheckAndDoing = [datetimeoffset]::Parse([string]$State.last_check_and_doing_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).LocalDateTime
        }
    } catch { }

    if ($null -eq $lastPlanning) { $lastPlanning = $now }
    if ($null -eq $lastCheckAndDoing) { $lastCheckAndDoing = $now }

    $nextPlanning = $lastPlanning.AddMinutes($planMinutes)
    $nextCheckAndDoing = $lastCheckAndDoing.AddMinutes($checkAndDoingMinutes)

    $scheduler = [pscustomobject]@{
        planning_interval_minutes = $planMinutes
        check_and_doing_interval_minutes = $checkAndDoingMinutes
        last_planning_at = $State.last_planning_at
        last_check_and_doing_at = $State.last_check_and_doing_at
        next_planning_at = $nextPlanning.ToString("o")
        next_check_and_doing_at = $nextCheckAndDoing.ToString("o")
        next_planning_in_seconds = [Math]::Max(0, [int][Math]::Round(($nextPlanning - $now).TotalSeconds))
        next_check_and_doing_in_seconds = [Math]::Max(0, [int][Math]::Round(($nextCheckAndDoing - $now).TotalSeconds))
        generated_at = $now.ToString("o")
    }

    $State | Add-Member -MemberType NoteProperty -Name "scheduler" -Value $scheduler -Force
    return $State
}

function Invoke-BoundedTelemetrySync {
    param(
        [Parameter(Mandatory)][object]$Registry,
        [AllowNull()][object]$Config,
        [Parameter(Mandatory)][string]$StatePath,
        [int]$TimeoutSeconds = 30
    )

    $managerPath = Join-Path $ScriptDir "src/lib/telemetry-manager.ps1"
    $job = Start-Job -ScriptBlock {
        param($TelemetryManagerPath, $InputRegistry, $InputConfig, $InputStatePath)
        . $TelemetryManagerPath
        Sync-AutopilotTelemetry -Registry $InputRegistry -Config $InputConfig -StatePath $InputStatePath
    } -ArgumentList $managerPath, $Registry, $Config, $StatePath

    try {
        $null = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($job.State -eq "Completed") {
            $result = Receive-Job -Job $job
            if ($null -ne $result) { return $result }
        } else {
            Write-Warning "[STATS] Telemetrie-Sync nach $TimeoutSeconds Sekunden abgebrochen; verwende letzten Registry-Stand."
        }
    } finally {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }

    return $Registry
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " VORCE AUTOPILOT - Persistent Dashboard Sync (Optimized)" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[STATS] Sync Loop gestartet (Ctrl+C zum Beenden)..."

while ($true) {
    try {
        $registry = Read-QuotaRegistry

        # Export operational state before slower telemetry and API collection.
        if (Test-Path $StatePath) {
            $quickState = Read-JsonLocked -Path $StatePath
            if ($null -ne $quickState) {
                $quickState = Add-SchedulerSnapshot -State $quickState -Config $Config
                Write-JsonLocked -Path (Join-Path $VarDbDir "active-sessions.json") -Data $quickState | Out-Null
            }
        }
        Write-JsonLocked -Path (Join-Path $VarDbDir "registry.json") -Data $registry | Out-Null

        $registry = Invoke-BoundedTelemetrySync -Registry $registry -Config $Config -StatePath $StatePath
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        $reportDate = if (-not [string]::IsNullOrWhiteSpace($registry.last_reset_date)) { $registry.last_reset_date } else { $currentDate }

        # Historical reporting must not block operational dashboard snapshots.
        try {
          # --- DB Sync ---
          foreach ($prop in $registry.providers.PSObject.Properties) {
            $providerName = $prop.Name
            $provider = $prop.Value
            Initialize-ProviderUsageToday -Provider $provider
            Clear-DailyUsageForProvider -Date $reportDate -ProviderName $providerName

            $modelBuckets = @($provider.usage_today.PSObject.Properties | Where-Object {
                $_.Name -notin @("calls", "estimated_cost_usd", "source", "last_synced_at", "rate_limits", "quota_buckets", "quota_source", "quota_synced_at", "quota_error", "active_sessions", "completed_sessions", "failed_sessions", "pending_sessions", "api_sessions_seen", "api_sessions_today", "account_sessions_observed_today", "account_sessions_observed_rolling_24h", "live_capacity_sessions", "live_in_progress_sessions", "live_queued_sessions", "live_waiting_sessions", "scoped_live_capacity_sessions", "scoped_live_in_progress_sessions", "scoped_live_queued_sessions", "scoped_live_waiting_sessions", "last_error") -and
                $null -ne $_.Value -and
                (Test-ObjectProperty -Object $_.Value -Name "calls")
            })

            if ($modelBuckets.Count -eq 0) {
                $totals = Get-ProviderUsageTotals -Provider $provider
                if ([int]$totals.calls -gt 0) {
                    Save-DailyUsage -Date $reportDate -ProviderName $providerName -ModelName "aggregate" -Calls ([int]$totals.calls) -CostUsd ([double]$totals.estimated_cost_usd) -InputTokens 0 -OutputTokens 0 -CachedTokens 0 -ReasoningTokens 0 -ToolTokens 0 -DurationMs 0
                }
            }

            foreach ($modelProp in $modelBuckets) {
                $modelName = $modelProp.Name
                $modUsage = $modelProp.Value
                $calls = [int]($modUsage.calls)
                if ($calls -gt 0) {
                    $cost = [double]($modUsage.estimated_cost_usd)
                    $inputTokens = if ($modUsage.PSObject.Properties.Name -contains "total_input_tokens" -and $modUsage.total_input_tokens) { [int]$modUsage.total_input_tokens } else { 0 }
                    $outputTokens = if ($modUsage.PSObject.Properties.Name -contains "total_output_tokens" -and $modUsage.total_output_tokens) { [int]$modUsage.total_output_tokens } else { 0 }
                    $cachedTokens = if ($modUsage.PSObject.Properties.Name -contains "cached_tokens" -and $modUsage.cached_tokens) { [int]$modUsage.cached_tokens } else { 0 }
                    $reasoningTokens = if ($modUsage.PSObject.Properties.Name -contains "reasoning_tokens" -and $modUsage.reasoning_tokens) { [int]$modUsage.reasoning_tokens } else { 0 }
                    $toolTokens = if ($modUsage.PSObject.Properties.Name -contains "tool_tokens" -and $modUsage.tool_tokens) { [int]$modUsage.tool_tokens } else { 0 }
                    $durationMs = if ($modUsage.PSObject.Properties.Name -contains "total_duration_ms" -and $modUsage.total_duration_ms) { [int]$modUsage.total_duration_ms } else { 0 }

                    Save-DailyUsage -Date $reportDate -ProviderName $providerName -ModelName $modelName -Calls $calls -CostUsd $cost -InputTokens $inputTokens -OutputTokens $outputTokens -CachedTokens $cachedTokens -ReasoningTokens $reasoningTokens -ToolTokens $toolTokens -DurationMs $durationMs
                }
            }
          }

          # --- File Export (write directly to var/db for dashboard proxy) ---
          $DbPath = Join-Path $VarDbDir "historical-quota-db.json"
          if (Test-Path $DbPath) {
              $db = Read-JsonLocked -Path $DbPath
              if ($null -eq $db) { $db = @() }
              Write-JsonLocked -Path (Join-Path $VarDbDir "data.json") -Data @($db) | Out-Null
          }
        } catch {
          Write-Warning "[STATS] Historischer Quota-Sync fehlgeschlagen; operative Dashboard-Daten werden trotzdem aktualisiert: $($_.Exception.Message)"
        }

        if (Test-Path $StatePath) {
            $state = Read-JsonLocked -Path $StatePath
            if ($null -ne $state) {
                # Load deliberation protocols
                $delibLogDir = Join-Path $ScriptDir "var/log/deliberations"
                $delibLog = @()
                if (Test-Path $delibLogDir) {
                    $delibFiles = @(Get-ChildItem -Path $delibLogDir -Filter "*.json" -File | Sort-Object LastWriteTime)
                    foreach ($file in $delibFiles) {
                        $delibObj = Read-JsonLocked -Path $file.FullName
                        if ($null -ne $delibObj) {
                            $delibLog += $delibObj
                        }
                    }
                }
                $state | Add-Member -MemberType NoteProperty -Name "deliberation_log" -Value $delibLog -Force

                $state = Add-SchedulerSnapshot -State $state -Config $Config
                Write-JsonLocked -Path (Join-Path $VarDbDir "active-sessions.json") -Data $state | Out-Null
            }
        }

        Write-JsonLocked -Path (Join-Path $VarDbDir "registry.json") -Data $registry | Out-Null

        # --- GitHub / PR / Jules Polling (Throttled) ---
        $now = Get-Date
        if (($now - $lastGhFetch).TotalSeconds -ge $ghFetchIntervalSec) {
            Write-Host "[STATS] Starte parallelen Sync (Issues, PRs, Jules)..." -ForegroundColor Gray

            $reposToPoll = @($Repository)
            if ($Repository -eq "Vorce-Studios/Vorce") {
                $reposToPoll += "MrLongNight/MapFlow"
            }

            # 1. Start Jobs
            $jobIssues = Start-Job -ScriptBlock {
                param($repos)
                $allIssues = @()
                foreach ($r in $repos) {
                    $issuesRaw = gh issue list --repo $r --state all --limit 1000 --json number,title,state,url,updatedAt,createdAt,labels,body,assignees,milestone 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $issueData = $issuesRaw | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($issueData) {
                            foreach ($issue in $issueData) {
                                $issue | Add-Member -MemberType NoteProperty -Name "repo" -Value $r -Force
                                $allIssues += $issue
                            }
                        }
                    }
                }
                return $allIssues
            } -ArgumentList (,$reposToPoll)

            $jobPRs = Start-Job -ScriptBlock {
                param($repos)
                $allPRs = @()
                foreach ($r in $repos) {
                    $prsRaw = gh pr list --repo $r --state open --limit 1000 --json number,title,state,url,updatedAt,headRefName,baseRefName,mergeable,statusCheckRollup,isDraft 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $prData = $prsRaw | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($prData) {
                            foreach ($pr in $prData) {
                                $pr | Add-Member -MemberType NoteProperty -Name "repo" -Value $r -Force
                                $allPRs += $pr
                            }
                        }
                    }
                }
                return $allPRs
            } -ArgumentList (,$reposToPoll)

            $jApiKey = Get-JulesApiKey
            $jobJules = Start-Job -ScriptBlock {
                param($apiKey, $julesDir)
                . (Join-Path $julesDir "jules-api.ps1")
                try {
                    $jSessions = @(Get-AllJulesSessions -ApiKey $apiKey -PageSize 100 -MaxPages 15)
                    $jList = @()
                    foreach ($s in $jSessions) {
                        $stateName = [string]$s.state
                        $sourceContext = $null
                        if ($s -is [System.Collections.IDictionary]) {
                            if ($s.Contains("sourceContext")) { $sourceContext = $s["sourceContext"] }
                        } elseif ($s.PSObject.Properties["sourceContext"]) {
                            $sourceContext = $s.sourceContext
                        }
                        $source = ""
                        if ($sourceContext -is [System.Collections.IDictionary]) {
                            if ($sourceContext.Contains("source")) { $source = [string]$sourceContext["source"] }
                        } elseif ($null -ne $sourceContext -and $sourceContext.PSObject.Properties["source"]) {
                            $source = [string]$sourceContext.source
                        }
                        $repo = if ($source -match "sources/github/(?<name>.*)") { $Matches["name"] } else { $source }

                        $issueNum = Get-IssueNumberFromSession -Session $s
                        $jList += [ordered]@{
                            name        = [string]$s.name
                            title       = [string]$s.title
                            state       = $stateName
                            repo        = $repo
                            issueNumber = $issueNum
                            updatedAt   = [string]$s.updateTime
                            createdAt   = [string]$s.createTime
                            url         = [string]$s.url
                        }
                    }
                    return $jList
                } catch {
                    return "ERROR:" + $_.Exception.Message
                }
            } -ArgumentList $jApiKey, $JulesScriptDir

            $jobProjectItems = Start-Job -ScriptBlock {
                $itemsRaw = gh project item-list 1 --owner Vorce-Studios --limit 1000 --format json 2>$null
                if ($LASTEXITCODE -eq 0 -and $itemsRaw) {
                    $itemsData = $itemsRaw | Out-String | ConvertFrom-Json -ErrorAction SilentlyContinue
                    return $itemsData
                }
                return $null
            }

            # 2. Wait and Receive
            Wait-Job $jobIssues, $jobPRs, $jobJules, $jobProjectItems -Timeout 180 | Out-Null

            $allIssues = Receive-Job $jobIssues
            $allPRs = Receive-Job $jobPRs
            $julesResult = Receive-Job $jobJules
            $projectItems = Receive-Job $jobProjectItems

            Remove-Job $jobIssues, $jobPRs, $jobJules, $jobProjectItems -Force

            # 3. Write results
            if ($null -ne $allIssues -and $allIssues.Count -gt 0) {
                Write-JsonLocked -Path (Join-Path $VarDbDir "github-issues.json") -Data @($allIssues) | Out-Null
                Write-Host "[STATS] GitHub Issues updated ($($allIssues.Count) issues)." -ForegroundColor Gray
            }
            if ($null -ne $allPRs) {
                Write-JsonLocked -Path (Join-Path $VarDbDir "pull-requests.json") -Data @($allPRs) | Out-Null
                Write-Host "[STATS] Pull Requests updated ($($allPRs.Count) PRs)." -ForegroundColor Gray
            }
            if ($julesResult -is [string] -and $julesResult -match "^ERROR:") {
                Write-Warning "[STATS] Jules API Sync Fehler: $($julesResult.Substring(6))"
            } elseif ($null -ne $julesResult) {
                Write-JsonLocked -Path (Join-Path $VarDbDir "jules-sessions.json") -Data @($julesResult) | Out-Null
                Write-Host "[STATS] Jules API Sessions updated ($($julesResult.Count) sessions)." -ForegroundColor Gray
            }
            if ($null -ne $projectItems -and $projectItems.items.Count -gt 0) {
                Write-JsonLocked -Path (Join-Path $VarDbDir "project-items.json") -Data $projectItems | Out-Null
                Write-Host "[STATS] Project Items updated ($($projectItems.items.Count) items)." -ForegroundColor Gray
            }

            $lastGhFetch = $now
        }

    } catch {
        Write-Warning "[STATS] Sync Fehler: $($_.Exception.Message)"
        Write-Warning "StackTrace: $($_.ScriptStackTrace)"
    }

    Start-Sleep -Seconds $dashboardSyncIntervalSec
}
