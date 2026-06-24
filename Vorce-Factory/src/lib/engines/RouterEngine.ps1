# Central deterministic router resolver for all Vorce MAIN-RUNs.

$script:VorceRouterConditionWhitelist = @(
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

function Get-VorceRouterConditionWhitelist {
    return @($script:VorceRouterConditionWhitelist)
}

function Get-VorceRouterValue {
    param(
        [object]$InputObject,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ref]$Found
    )

    $Found.Value = $false
    if ($null -eq $InputObject) {
        return $null
    }

    $current = $InputObject
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) {
            return $null
        }

        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) {
                return $null
            }
            $current = $current[$segment]
            continue
        }

        $property = $current.PSObject.Properties[$segment]
        if ($null -eq $property) {
            return $null
        }
        $current = $property.Value
    }

    $Found.Value = $true
    return $current
}

function Set-VorceRouterSnapshotValue {
    param(
        [Parameter(Mandatory)][hashtable]$Snapshot,
        [Parameter(Mandatory)][string]$Name,
        [object]$Value,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not $Snapshot.Values.ContainsKey($Name)) {
        $Snapshot.Values[$Name] = $Value
        $Snapshot.Sources[$Name] = $Source
    }
}

function Read-VorceRouterJsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ available = $false; value = $null; error = 'missing'; path = $Path }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq 'null') {
            return [pscustomobject]@{ available = $false; value = $null; error = 'empty'; path = $Path }
        }

        $value = $raw | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{ available = $true; value = $value; error = $null; path = $Path }
    } catch {
        return [pscustomobject]@{ available = $false; value = $null; error = $_.Exception.Message; path = $Path }
    }
}

function Get-VorceRouterNow {
    param([Parameter(Mandatory)][hashtable]$ConfigBag)

    $found = $false
    $timestamp = Get-VorceRouterValue -InputObject $ConfigBag -Path 'Timestamp' -Found ([ref]$found)
    if ($found -and $timestamp) {
        try { return [datetime]$timestamp } catch {}
    }
    return Get-Date
}

function Get-VorceRouterLatestFile {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Filter = '*.json'
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $Directory -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-VorceRouterProposalSummary {
    param([Parameter(Mandatory)][string]$VarDir)

    $proposalDir = Join-Path $VarDir 'db/proposals'
    if (-not (Test-Path -LiteralPath $proposalDir -PathType Container)) {
        return [pscustomobject]@{
            available = $true
            pending_count = 0
            approved_undelegated_count = 0
            error = $null
        }
    }

    $pending = 0
    $approved = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $proposalDir -Filter 'proposal_*.json' -File -ErrorAction SilentlyContinue)) {
        $read = Read-VorceRouterJsonFile -Path $file.FullName
        if (-not $read.available) {
            return [pscustomobject]@{
                available = $false
                pending_count = 0
                approved_undelegated_count = 0
                error = $read.error
            }
        }

        $proposal = $read.value
        $statusFound = $false
        $status = Get-VorceRouterValue -InputObject $proposal -Path 'status' -Found ([ref]$statusFound)
        $approvedFound = $false
        $approvedFlag = Get-VorceRouterValue -InputObject $proposal -Path 'approved' -Found ([ref]$approvedFound)
        $delegatedFound = $false
        $delegatedFlag = Get-VorceRouterValue -InputObject $proposal -Path 'delegated' -Found ([ref]$delegatedFound)
        $delegationFound = $false
        $delegationId = Get-VorceRouterValue -InputObject $proposal -Path 'delegation_id' -Found ([ref]$delegationFound)

        $isDelegated = ($delegatedFound -and [bool]$delegatedFlag) -or ($delegationFound -and -not [string]::IsNullOrWhiteSpace([string]$delegationId))
        $isApproved = ($approvedFound -and [bool]$approvedFlag) -or (
            $statusFound -and @('approved', 'ready', 'approved-awaiting-dispatch') -contains ([string]$status).ToLowerInvariant()
        )

        if (-not $isDelegated) {
            $pending++
        }
        if ($isApproved -and -not $isDelegated) {
            $approved++
        }
    }

    return [pscustomobject]@{
        available = $true
        pending_count = $pending
        approved_undelegated_count = $approved
        error = $null
    }
}

function Get-VorceRouterDataSnapshot {
    param(
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [object]$MainState
    )

    $snapshot = @{
        Values = @{}
        Sources = @{}
    }

    $routerDataFound = $false
    $routerData = Get-VorceRouterValue -InputObject $ConfigBag -Path 'RouterData' -Found ([ref]$routerDataFound)
    if ($routerDataFound -and $null -ne $routerData) {
        if ($routerData -is [System.Collections.IDictionary]) {
            foreach ($key in $routerData.Keys) {
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name ([string]$key) -Value $routerData[$key] -Source 'ConfigBag.RouterData'
            }
        } else {
            foreach ($property in $routerData.PSObject.Properties) {
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name $property.Name -Value $property.Value -Source 'ConfigBag.RouterData'
            }
        }
    }

    $varDirFound = $false
    $varDir = Get-VorceRouterValue -InputObject $ConfigBag -Path 'VarDir' -Found ([ref]$varDirFound)
    $configFound = $false
    $config = Get-VorceRouterValue -InputObject $ConfigBag -Path 'Config' -Found ([ref]$configFound)
    $globalStateFound = $false
    $globalState = Get-VorceRouterValue -InputObject $ConfigBag -Path 'GlobalState' -Found ([ref]$globalStateFound)
    $quotaFound = $false
    $quotaRegistry = Get-VorceRouterValue -InputObject $ConfigBag -Path 'QuotaRegistry' -Found ([ref]$quotaFound)
    $now = Get-VorceRouterNow -ConfigBag $ConfigBag

    if ($configFound) {
        $found = $false
        $maxIssues = Get-VorceRouterValue -InputObject $config -Path 'max_issues_per_planning_cycle' -Found ([ref]$found)
        if ($found) {
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'max_issues_per_planning_cycle' -Value ([int]$maxIssues) -Source 'Config.max_issues_per_planning_cycle'
        }

        $found = $false
        $refillEnabled = Get-VorceRouterValue -InputObject $config -Path 'jules.monitoring_refill_enabled' -Found ([ref]$found)
        if ($found) {
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'monitoring_refill_enabled' -Value ([bool]$refillEnabled) -Source 'Config.jules.monitoring_refill_enabled'
        }
    }

    if ($globalStateFound) {
        $found = $false
        $delegations = Get-VorceRouterValue -InputObject $globalState -Path 'active_delegations' -Found ([ref]$found)
        if ($found) {
            $activeJules = @($delegations | Where-Object {
                $providerFound = $false
                $provider = Get-VorceRouterValue -InputObject $_ -Path 'delegatedTo' -Found ([ref]$providerFound)
                if (-not $providerFound) {
                    $provider = Get-VorceRouterValue -InputObject $_ -Path 'provider' -Found ([ref]$providerFound)
                }
                $statusFound = $false
                $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                $isFinal = $statusFound -and @('completed', 'failed', 'cancelled') -contains ([string]$status).ToLowerInvariant()
                $providerFound -and ([string]$provider).ToLowerInvariant() -eq 'jules' -and -not $isFinal
            }).Count
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'active_jules_delegation_count' -Value $activeJules -Source 'GlobalState.active_delegations'
        }

        $found = $false
        $alerts = Get-VorceRouterValue -InputObject $globalState -Path 'alerts' -Found ([ref]$found)
        if ($found) {
            $openAlerts = @($alerts | Where-Object {
                $statusFound = $false
                $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                -not $statusFound -or @('open', 'active', 'new') -contains ([string]$status).ToLowerInvariant()
            }).Count
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'open_alert_count' -Value $openAlerts -Source 'GlobalState.alerts'
        }
    }

    if ($varDirFound -and -not [string]::IsNullOrWhiteSpace([string]$varDir)) {
        $issuesPath = Join-Path $varDir 'db/github-issues.json'
        $triagedPath = Join-Path $varDir 'db/triaged-issues.json'
        $issuesRead = Read-VorceRouterJsonFile -Path $issuesPath
        $triagedRead = Read-VorceRouterJsonFile -Path $triagedPath

        if ($issuesRead.available) {
            $issueFile = Get-Item -LiteralPath $issuesPath
            $triageCurrent = $false
            if ($triagedRead.available) {
                $triagedFile = Get-Item -LiteralPath $triagedPath
                $triageCurrent = $triagedFile.LastWriteTimeUtc -ge $issueFile.LastWriteTimeUtc
            }
            $changedCount = if ($triageCurrent) { 0 } else { @($issuesRead.value).Count }
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'data_sync_changed_issue_count' -Value $changedCount -Source 'db/github-issues.json'
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'triage_snapshot_current' -Value $triageCurrent -Source 'db/triaged-issues.json'
        }

        if ($triagedRead.available) {
            $eligibleCount = @($triagedRead.value | Where-Object {
                $eligibleFound = $false
                $eligible = Get-VorceRouterValue -InputObject $_ -Path 'eligible' -Found ([ref]$eligibleFound)
                $statusFound = $false
                $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                (-not $eligibleFound -or [bool]$eligible) -and (
                    -not $statusFound -or @('eligible', 'triaged', 'approved', 'ready') -contains ([string]$status).ToLowerInvariant()
                )
            }).Count
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'eligible_triaged_count' -Value $eligibleCount -Source 'db/triaged-issues.json'
        }

        $proposalSummary = Get-VorceRouterProposalSummary -VarDir $varDir
        if ($proposalSummary.available) {
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'pending_proposals' -Value $proposalSummary.pending_count -Source 'db/proposals'
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'approved_undelegated_proposal_count' -Value $proposalSummary.approved_undelegated_count -Source 'db/proposals'
        }

        $prPath = Join-Path $varDir 'db/pull-requests.json'
        $prRead = Read-VorceRouterJsonFile -Path $prPath
        if ($prRead.available) {
            $reviewCount = @($prRead.value | Where-Object {
                $draftFound = $false
                $isDraft = Get-VorceRouterValue -InputObject $_ -Path 'isDraft' -Found ([ref]$draftFound)
                $stateFound = $false
                $state = Get-VorceRouterValue -InputObject $_ -Path 'state' -Found ([ref]$stateFound)
                $decisionFound = $false
                $decision = Get-VorceRouterValue -InputObject $_ -Path 'reviewDecision' -Found ([ref]$decisionFound)
                $completedFound = $false
                $completed = Get-VorceRouterValue -InputObject $_ -Path 'review_completed' -Found ([ref]$completedFound)
                (-not $draftFound -or -not [bool]$isDraft) -and
                    (-not $stateFound -or ([string]$state).ToUpperInvariant() -eq 'OPEN') -and
                    (-not $decisionFound -or ([string]$decision).ToUpperInvariant() -ne 'APPROVED') -and
                    (-not $completedFound -or -not [bool]$completed)
            }).Count
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'open_pr_review_count' -Value $reviewCount -Source 'db/pull-requests.json'
        }

        $registryPaths = @(
            (Join-Path $varDir 'db/process-registry.json'),
            (Join-Path $varDir 'db/session-registry.json'),
            (Join-Path $varDir 'db/agent-sessions.json')
        )
        $registryPath = $registryPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($registryPath) {
            $registryRead = Read-VorceRouterJsonFile -Path $registryPath
            if ($registryRead.available) {
                $entries = @($registryRead.value)
                $entriesFound = $false
                $nestedEntries = Get-VorceRouterValue -InputObject $registryRead.value -Path 'processes' -Found ([ref]$entriesFound)
                if ($entriesFound) {
                    $entries = @($nestedEntries)
                }
                $localCount = @($entries | Where-Object {
                    $statusFound = $false
                    $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                    $typeFound = $false
                    $type = Get-VorceRouterValue -InputObject $_ -Path 'type' -Found ([ref]$typeFound)
                    $providerFound = $false
                    $provider = Get-VorceRouterValue -InputObject $_ -Path 'provider' -Found ([ref]$providerFound)
                    $isActive = -not $statusFound -or @('active', 'running', 'starting') -contains ([string]$status).ToLowerInvariant()
                    $isLocal = ($typeFound -and @('local_agent', 'agent') -contains ([string]$type).ToLowerInvariant()) -or
                        ($providerFound -and ([string]$provider).ToLowerInvariant() -ne 'jules')
                    $isActive -and $isLocal
                }).Count
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'active_local_agent_session_count' -Value $localCount -Source $registryPath
            }
        }

        $expiredRuntimeFiles = 0
        foreach ($runtimeDir in @((Join-Path $varDir 'tmp'), (Join-Path $varDir 'locks'))) {
            if (Test-Path -LiteralPath $runtimeDir -PathType Container) {
                $expiredRuntimeFiles += @(Get-ChildItem -LiteralPath $runtimeDir -File -ErrorAction SilentlyContinue | Where-Object {
                    $_.LastWriteTimeUtc -lt $now.ToUniversalTime().AddHours(-24)
                }).Count
            }
        }
        Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'expired_runtime_file_count' -Value $expiredRuntimeFiles -Source 'var/tmp,var/locks'

        if ($globalStateFound) {
            $found = $false
            $lastHousekeeping = Get-VorceRouterValue -InputObject $globalState -Path 'stats.last_housekeeping' -Found ([ref]$found)
            if ($found -and $lastHousekeeping) {
                try {
                    $elapsed = ($now - [datetime]$lastHousekeeping).TotalMinutes -ge 1440
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'housekeeping_interval_elapsed' -Value $elapsed -Source 'GlobalState.stats.last_housekeeping'
                } catch {}
            }

            $lastAuditFound = $false
            $lastAudit = Get-VorceRouterValue -InputObject $globalState -Path 'last_runs.MAIN-RUN-03_Audit' -Found ([ref]$lastAuditFound)
            if ($lastAuditFound -and $lastAudit) {
                try {
                    $lastAuditDate = [datetime]$lastAudit
                    $newAuditInputs = @(Get-ChildItem -LiteralPath (Join-Path $varDir 'db') -File -ErrorAction SilentlyContinue | Where-Object {
                        $_.LastWriteTimeUtc -gt $lastAuditDate.ToUniversalTime()
                    }).Count
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'new_audit_input_count' -Value $newAuditInputs -Source 'var/db timestamps'
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'audit_max_interval_elapsed' -Value (($now - $lastAuditDate).TotalMinutes -ge 1440) -Source 'GlobalState.last_runs'
                } catch {}
            } else {
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'audit_max_interval_elapsed' -Value $true -Source 'GlobalState.last_runs'
            }
        }

        $latestPerformance = Get-VorceRouterLatestFile -Directory (Join-Path $varDir 'performance')
        if ($latestPerformance) {
            $performanceRead = Read-VorceRouterJsonFile -Path $latestPerformance.FullName
            if ($performanceRead.available) {
                $runTimesFound = $false
                $runTimes = Get-VorceRouterValue -InputObject $performanceRead.value -Path 'run_times' -Found ([ref]$runTimesFound)
                if ($runTimesFound) {
                    $sampleCount = @($runTimes | Where-Object {
                        $statusFound = $false
                        $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                        $nameFound = $false
                        $name = Get-VorceRouterValue -InputObject $_ -Path 'run_name' -Found ([ref]$nameFound)
                        $statusFound -and ([string]$status).ToLowerInvariant() -eq 'completed' -and
                            $nameFound -and ([string]$name).StartsWith('MAIN_')
                    }).Count
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'optimizer_sample_count' -Value $sampleCount -Source $latestPerformance.FullName
                }
            }
        }

        $latestAnalysis = Get-VorceRouterLatestFile -Directory (Join-Path $varDir 'analysis')
        if ($latestAnalysis) {
            $analysisRead = Read-VorceRouterJsonFile -Path $latestAnalysis.FullName
            if ($analysisRead.available) {
                $recommendationsFound = $false
                $recommendations = Get-VorceRouterValue -InputObject $analysisRead.value -Path 'optimization_recommendations' -Found ([ref]$recommendationsFound)
                $bottlenecksFound = $false
                $bottlenecks = Get-VorceRouterValue -InputObject $analysisRead.value -Path 'bottleneck_analysis' -Found ([ref]$bottlenecksFound)
                $findingCount = 0
                if ($recommendationsFound) { $findingCount += @($recommendations).Count }
                if ($bottlenecksFound -and $null -ne $bottlenecks) { $findingCount += @($bottlenecks.PSObject.Properties).Count }
                if ($recommendationsFound -or $bottlenecksFound) {
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'optimizer_finding_count' -Value $findingCount -Source $latestAnalysis.FullName
                }
            }
        }

        foreach ($definition in @(
            @{ Name = 'optimizer_approved_change_count'; Directory = 'optimizer/approved'; Status = $null },
            @{ Name = 'optimizer_change_evaluation_count'; Directory = 'optimizer/applied'; Status = $null }
        )) {
            $directory = Join-Path $varDir $definition.Directory
            if (Test-Path -LiteralPath $directory -PathType Container) {
                $count = @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name $definition.Name -Value $count -Source $directory
            }
        }

        $memoryPath = Join-Path $varDir 'db/autopilot-memories.json'
        $memoryRead = Read-VorceRouterJsonFile -Path $memoryPath
        if ($memoryRead.available) {
            $memoriesFound = $false
            $memories = Get-VorceRouterValue -InputObject $memoryRead.value -Path 'memories' -Found ([ref]$memoriesFound)
            if (-not $memoriesFound) {
                $memories = $memoryRead.value
                $memoriesFound = $true
            }
            if ($memoriesFound) {
                $candidateCount = @($memories | Where-Object {
                    $statusFound = $false
                    $status = Get-VorceRouterValue -InputObject $_ -Path 'status' -Found ([ref]$statusFound)
                    $expiresFound = $false
                    $expiresAt = Get-VorceRouterValue -InputObject $_ -Path 'expires_at' -Found ([ref]$expiresFound)
                    $expired = $false
                    if ($expiresFound -and $expiresAt) {
                        try { $expired = [datetime]$expiresAt -le $now } catch {}
                    }
                    $expired -or ($statusFound -and @('expired', 'duplicate', 'invalid', 'candidate') -contains ([string]$status).ToLowerInvariant())
                }).Count
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'memory_candidate_count' -Value $candidateCount -Source $memoryPath
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'memory_expired_candidate_count' -Value $candidateCount -Source $memoryPath
            }
        }

        if ($globalStateFound -and $configFound) {
            $lastMemoryFound = $false
            $lastMemory = Get-VorceRouterValue -InputObject $globalState -Path 'last_runs.MAIN-RUN-05_MemoryOptimization' -Found ([ref]$lastMemoryFound)
            $intervalFound = $false
            $memoryInterval = Get-VorceRouterValue -InputObject $config -Path 'wake_intervals.memory_optimization_minutes' -Found ([ref]$intervalFound)
            if ($intervalFound) {
                if ($lastMemoryFound -and $lastMemory) {
                    try {
                        Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'memory_interval_elapsed' -Value (($now - [datetime]$lastMemory).TotalMinutes -ge [double]$memoryInterval) -Source 'GlobalState.last_runs'
                    } catch {}
                } else {
                    Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'memory_interval_elapsed' -Value $true -Source 'GlobalState.last_runs'
                }
            }
        }
    }

    if ($quotaFound -and $configFound) {
        $providerFound = $false
        $julesProvider = Get-VorceRouterValue -InputObject $quotaRegistry -Path 'providers.jules' -Found ([ref]$providerFound)
        if ($providerFound) {
            $activeFound = $false
            $activeSessions = Get-VorceRouterValue -InputObject $julesProvider -Path 'usage_today.active_sessions' -Found ([ref]$activeFound)
            if (-not $activeFound) {
                $activeSessions = Get-VorceRouterValue -InputObject $julesProvider -Path 'usage_today.live_capacity_sessions' -Found ([ref]$activeFound)
            }
            $maxFound = $false
            $maxConcurrent = Get-VorceRouterValue -InputObject $config -Path 'jules.max_concurrent_sessions' -Found ([ref]$maxFound)
            if ($activeFound -and $maxFound) {
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'jules_free_slots' -Value ([math]::Max(0, ([int]$maxConcurrent - [int]$activeSessions))) -Source 'QuotaRegistry.providers.jules'
            }

            $callsFound = $false
            $calls = Get-VorceRouterValue -InputObject $julesProvider -Path 'usage_today.calls' -Found ([ref]$callsFound)
            $limitFound = $false
            $limit = Get-VorceRouterValue -InputObject $julesProvider -Path 'daily_limit' -Found ([ref]$limitFound)
            if ($callsFound -and $limitFound) {
                Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'jules_quota_available' -Value ([int]$calls -lt [int]$limit) -Source 'QuotaRegistry.providers.jules'
            }
        }
    }

    if (-not $snapshot.Values.ContainsKey('delegable_task_count')) {
        $taskCount = 0
        $taskSourceAvailable = $false
        if ($snapshot.Values.ContainsKey('approved_undelegated_proposal_count')) {
            $taskCount += [int]$snapshot.Values['approved_undelegated_proposal_count']
            $taskSourceAvailable = $true
        }
        if ($globalStateFound) {
            $reviewFound = $false
            $reviewQueue = Get-VorceRouterValue -InputObject $globalState -Path 'review_queue' -Found ([ref]$reviewFound)
            if ($reviewFound) {
                $taskCount += @($reviewQueue).Count
                $taskSourceAvailable = $true
            }
        }
        if ($taskSourceAvailable) {
            Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'delegable_task_count' -Value $taskCount -Source 'proposals,GlobalState.review_queue'
        }
    }

    if (-not $snapshot.Values.ContainsKey('delegation_capacity_available') -and
        $snapshot.Values.ContainsKey('jules_free_slots') -and
        $snapshot.Values.ContainsKey('jules_quota_available')) {
        $capacity = [int]$snapshot.Values['jules_free_slots'] -gt 0 -and [bool]$snapshot.Values['jules_quota_available']
        Set-VorceRouterSnapshotValue -Snapshot $snapshot -Name 'delegation_capacity_available' -Value $capacity -Source 'Jules capacity'
    }

    return $snapshot
}

function Get-VorceRouterSignal {
    param(
        [Parameter(Mandatory)][hashtable]$Snapshot,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Snapshot.Values.ContainsKey($Name)) {
        return [pscustomobject]@{ available = $false; value = $null; source = $null; name = $Name }
    }

    return [pscustomobject]@{
        available = $true
        value = $Snapshot.Values[$Name]
        source = $Snapshot.Sources[$Name]
        name = $Name
    }
}

function New-VorceRouterConditionResult {
    param(
        [Parameter(Mandatory)][bool]$Available,
        [Parameter(Mandatory)][bool]$Met,
        [Parameter(Mandatory)][hashtable]$Evidence,
        [string]$InactiveReason = 'condition_not_met'
    )

    return [pscustomobject]@{
        available = $Available
        met = $Met
        inactive_reason = $InactiveReason
        evidence = [pscustomobject]$Evidence
    }
}

function Test-VorceRouterCondition {
    param(
        [Parameter(Mandatory)][ValidateSet(
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
        )][string]$Condition,
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [object]$MainState,
        [object]$ConditionSettings,
        [hashtable]$Snapshot
    )

    if ($null -eq $Snapshot) {
        $Snapshot = Get-VorceRouterDataSnapshot -ConfigBag $ConfigBag -MainState $MainState
    }

    if ($Condition -eq 'always') {
        return New-VorceRouterConditionResult -Available $true -Met $true -Evidence @{ condition = 'always' }
    }

    $settings = if ($null -eq $ConditionSettings) { @{} } else { $ConditionSettings }

    switch ($Condition) {
        'pipeline_below_limit' {
            $eligible = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'eligible_triaged_count'
            $pending = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'pending_proposals'
            $limit = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'max_issues_per_planning_cycle'
            $available = $eligible.available -and $pending.available -and $limit.available
            $met = $available -and (([int]$eligible.value + [int]$pending.value) -lt [int]$limit.value)
            return New-VorceRouterConditionResult -Available $available -Met $met -Evidence @{
                eligible_triaged_count = $eligible.value
                pending_proposals = $pending.value
                max_issues_per_planning_cycle = $limit.value
            }
        }
        'has_untriaged_issues' {
            $changed = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'data_sync_changed_issue_count'
            $current = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'triage_snapshot_current'
            $available = $changed.available -and $current.available
            $met = $available -and (([int]$changed.value -gt 0) -or -not [bool]$current.value)
            return New-VorceRouterConditionResult -Available $available -Met $met -Evidence @{
                data_sync_changed_issue_count = $changed.value
                triage_snapshot_current = $current.value
            }
        }
        'has_approved_proposals' {
            $proposals = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'approved_undelegated_proposal_count'
            $capacity = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'delegation_capacity_available'
            if (-not $proposals.available) {
                return New-VorceRouterConditionResult -Available $false -Met $false -Evidence @{ approved_undelegated_proposal_count = $null }
            }
            if ([int]$proposals.value -le 0) {
                return New-VorceRouterConditionResult -Available $true -Met $false -Evidence @{
                    approved_undelegated_proposal_count = $proposals.value
                    delegation_capacity_available = $capacity.value
                }
            }
            if (-not $capacity.available) {
                return New-VorceRouterConditionResult -Available $false -Met $false -Evidence @{
                    approved_undelegated_proposal_count = $proposals.value
                    delegation_capacity_available = $null
                }
            }
            return New-VorceRouterConditionResult -Available $true -Met ([bool]$capacity.value) -InactiveReason 'dependency_not_ready' -Evidence @{
                approved_undelegated_proposal_count = $proposals.value
                delegation_capacity_available = $capacity.value
            }
        }
        'has_active_jules_delegations' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'active_jules_delegation_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                active_jules_delegation_count = $signal.value
                source = $signal.source
            }
        }
        'has_active_local_agent_sessions' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'active_local_agent_session_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                active_local_agent_session_count = $signal.value
                source = $signal.source
                process_name_scan_used = $false
            }
        }
        'has_open_prs_requiring_review' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'open_pr_review_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                open_non_draft_prs_requiring_review = $signal.value
                source = $signal.source
            }
        }
        'jules_capacity_available' {
            $enabled = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'monitoring_refill_enabled'
            $slots = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'jules_free_slots'
            $quota = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'jules_quota_available'
            $tasks = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'delegable_task_count'
            $available = $enabled.available -and $slots.available -and $quota.available -and $tasks.available
            $met = $available -and [bool]$enabled.value -and [int]$slots.value -gt 0 -and [bool]$quota.value -and [int]$tasks.value -gt 0
            return New-VorceRouterConditionResult -Available $available -Met $met -InactiveReason 'dependency_not_ready' -Evidence @{
                monitoring_refill_enabled = $enabled.value
                jules_free_slots = $slots.value
                jules_quota_available = $quota.value
                delegable_task_count = $tasks.value
            }
        }
        'housekeeping_due' {
            $interval = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'housekeeping_interval_elapsed'
            $expired = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'expired_runtime_file_count'
            $metByExpiredFiles = $expired.available -and [int]$expired.value -gt 0
            $available = $metByExpiredFiles -or $interval.available
            $met = $metByExpiredFiles -or ($interval.available -and [bool]$interval.value)
            return New-VorceRouterConditionResult -Available $available -Met $met -Evidence @{
                housekeeping_interval_elapsed = $interval.value
                expired_runtime_file_count = $expired.value
            }
        }
        'has_new_audit_inputs' {
            $newInputs = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'new_audit_input_count'
            $maxInterval = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'audit_max_interval_elapsed'
            $metByInput = $newInputs.available -and [int]$newInputs.value -gt 0
            $available = $metByInput -or $maxInterval.available
            $met = $metByInput -or ($maxInterval.available -and [bool]$maxInterval.value)
            return New-VorceRouterConditionResult -Available $available -Met $met -Evidence @{
                new_audit_input_count = $newInputs.value
                audit_max_interval_elapsed = $maxInterval.value
            }
        }
        'has_open_alerts' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'open_alert_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                open_alert_count = $signal.value
                source = $signal.source
            }
        }
        'optimizer_has_sufficient_samples' {
            $samples = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'optimizer_sample_count'
            $minimumFound = $false
            $minimum = Get-VorceRouterValue -InputObject $settings -Path 'minimum_samples' -Found ([ref]$minimumFound)
            if (-not $minimumFound) { $minimum = 3 }
            return New-VorceRouterConditionResult -Available $samples.available -Met ($samples.available -and [int]$samples.value -ge [int]$minimum) -Evidence @{
                optimizer_sample_count = $samples.value
                minimum_samples = [int]$minimum
                source = $samples.source
            }
        }
        'optimizer_has_findings' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'optimizer_finding_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                optimizer_finding_count = $signal.value
                source = $signal.source
            }
        }
        'optimizer_has_approved_changes' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'optimizer_approved_change_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                optimizer_approved_change_count = $signal.value
                source = $signal.source
            }
        }
        'optimizer_has_changes_to_evaluate' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'optimizer_change_evaluation_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                optimizer_change_evaluation_count = $signal.value
                source = $signal.source
            }
        }
        'memory_maintenance_due' {
            $interval = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'memory_interval_elapsed'
            $expired = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'memory_expired_candidate_count'
            $metByCandidate = $expired.available -and [int]$expired.value -gt 0
            $available = $metByCandidate -or $interval.available
            $met = $metByCandidate -or ($interval.available -and [bool]$interval.value)
            return New-VorceRouterConditionResult -Available $available -Met $met -Evidence @{
                memory_interval_elapsed = $interval.value
                memory_expired_candidate_count = $expired.value
            }
        }
        'memory_has_candidates' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'memory_candidate_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                memory_candidate_count = $signal.value
                source = $signal.source
            }
        }
        'master_issue_context_changed' {
            $signal = Get-VorceRouterSignal -Snapshot $Snapshot -Name 'changed_master_issue_count'
            return New-VorceRouterConditionResult -Available $signal.available -Met ($signal.available -and [int]$signal.value -gt 0) -Evidence @{
                changed_master_issue_count = $signal.value
                source = $signal.source
            }
        }
    }
}

function Test-VorceRouterForce {
    param(
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [Parameter(Mandatory)][object]$Rule,
        [switch]$Force
    )

    if ($Force) {
        return $true
    }

    foreach ($flagPath in @('ForceRouter', 'RouterForce')) {
        $found = $false
        $flag = Get-VorceRouterValue -InputObject $ConfigBag -Path $flagPath -Found ([ref]$found)
        if ($found -and [bool]$flag) {
            return $true
        }
    }

    foreach ($listPath in @('ForceSubRuns', 'ManualSubRuns')) {
        $found = $false
        $forcedRuns = Get-VorceRouterValue -InputObject $ConfigBag -Path $listPath -Found ([ref]$found)
        if ($found) {
            foreach ($forcedRun in @($forcedRuns)) {
                if ([string]$forcedRun -in @('*', [string]$Rule.id, [string]$Rule.name, [string]$Rule.script)) {
                    return $true
                }
            }
        }
    }

    return $false
}

function Test-VorceRouterCheckpointReuse {
    param(
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [object]$MainState,
        [Parameter(Mandatory)][object]$Rule
    )

    $candidates = @()
    foreach ($path in @('ReusedSubRuns', 'RouterData.reused_sub_runs')) {
        $found = $false
        $value = Get-VorceRouterValue -InputObject $ConfigBag -Path $path -Found ([ref]$found)
        if ($found) { $candidates += @($value) }
    }

    $stateFound = $false
    $stateValue = Get-VorceRouterValue -InputObject $MainState -Path 'metadata.reused_sub_runs' -Found ([ref]$stateFound)
    if ($stateFound) { $candidates += @($stateValue) }

    foreach ($candidate in $candidates) {
        if ([string]$candidate -in @([string]$Rule.id, [string]$Rule.name, [string]$Rule.script)) {
            return $true
        }
    }
    return $false
}

function Resolve-VorceRouterDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MainName,
        [Parameter(Mandatory)][hashtable]$ConfigBag,
        [Parameter(Mandatory)][object]$MainState,
        [Parameter(Mandatory)][object[]]$Rules,
        [switch]$Force
    )

    $snapshot = Get-VorceRouterDataSnapshot -ConfigBag $ConfigBag -MainState $MainState
    $rootFound = $false
    $root = Get-VorceRouterValue -InputObject $ConfigBag -Path 'VorceRoot' -Found ([ref]$rootFound)
    if (-not $rootFound -or [string]::IsNullOrWhiteSpace([string]$root)) {
        $root = (Get-Location).Path
    }

    $decisions = foreach ($rule in @($Rules | Sort-Object { [int]$_.id })) {
        $enabledFound = $false
        $enabledValue = Get-VorceRouterValue -InputObject $rule -Path 'enabled' -Found ([ref]$enabledFound)
        $configuredEnabled = -not $enabledFound -or [bool]$enabledValue

        $modeFound = $false
        $mode = Get-VorceRouterValue -InputObject $rule -Path 'mode' -Found ([ref]$modeFound)
        if (-not $modeFound -or [string]::IsNullOrWhiteSpace([string]$mode)) { $mode = 'automatic' }
        $mode = ([string]$mode).ToLowerInvariant()
        if (@('always', 'automatic', 'manual_only') -notcontains $mode) {
            throw "Unsupported router mode '$mode' for $MainName/$($rule.name)."
        }

        $conditionFound = $false
        $condition = Get-VorceRouterValue -InputObject $rule -Path 'condition' -Found ([ref]$conditionFound)
        if (-not $conditionFound -or [string]::IsNullOrWhiteSpace([string]$condition)) { $condition = 'always' }
        $condition = ([string]$condition).ToLowerInvariant()
        if ($script:VorceRouterConditionWhitelist -notcontains $condition) {
            throw "Unsupported router condition '$condition' for $MainName/$($rule.name)."
        }

        $settingsFound = $false
        $conditionSettings = Get-VorceRouterValue -InputObject $rule -Path 'condition_settings' -Found ([ref]$settingsFound)
        if (-not $settingsFound -or $null -eq $conditionSettings) { $conditionSettings = @{} }

        $scriptPath = if ([System.IO.Path]::IsPathRooted([string]$rule.script)) {
            [string]$rule.script
        } else {
            Join-Path ([string]$root) ([string]$rule.script)
        }
        $scriptExists = Test-Path -LiteralPath $scriptPath -PathType Leaf
        $forced = Test-VorceRouterForce -ConfigBag $ConfigBag -Rule $rule -Force:$Force
        $reused = Test-VorceRouterCheckpointReuse -ConfigBag $ConfigBag -MainState $MainState -Rule $rule

        $active = $false
        $reason = 'condition_not_met'
        $evidence = [ordered]@{
            main_name = $MainName
            script_exists = $scriptExists
            forced = $forced
            checkpoint_reused = $reused
        }

        if (-not $configuredEnabled) {
            $reason = 'disabled_in_config'
        } elseif (-not $scriptExists) {
            $reason = 'script_missing'
        } elseif ($mode -eq 'manual_only' -and -not $forced) {
            $reason = 'manual_only'
        } elseif ($reused) {
            $reason = 'reused_from_checkpoint'
        } elseif ($mode -eq 'manual_only' -and $forced) {
            $active = $true
            $reason = 'active_condition_met'
        } elseif ($mode -eq 'always') {
            $active = $true
            $reason = 'active_always'
        } else {
            $conditionResult = Test-VorceRouterCondition -Condition $condition -ConfigBag $ConfigBag -MainState $MainState -ConditionSettings $conditionSettings -Snapshot $snapshot
            foreach ($property in $conditionResult.evidence.PSObject.Properties) {
                $evidence[$property.Name] = $property.Value
            }
            if (-not $conditionResult.available) {
                $reason = 'data_source_unavailable'
            } elseif ($conditionResult.met) {
                $active = $true
                $reason = if ($condition -eq 'always') { 'active_always' } else { 'active_condition_met' }
            } else {
                $reason = $conditionResult.inactive_reason
            }
        }

        [pscustomobject]@{
            id = [string]$rule.id
            name = [string]$rule.name
            script = [string]$rule.script
            configured_enabled = [bool]$configuredEnabled
            mode = $mode
            condition = $condition
            active = [bool]$active
            reason = $reason
            evidence = [pscustomobject]$evidence
        }
    }

    return @($decisions)
}

function Set-VorceRouterDecisionMetadata {
    param(
        [Parameter(Mandatory)][object]$MainState,
        [Parameter(Mandatory)][string]$RouterKey,
        [Parameter(Mandatory)][object[]]$Decisions,
        [string]$DecisionTimestamp
    )

    if ([string]::IsNullOrWhiteSpace($DecisionTimestamp)) {
        $DecisionTimestamp = (Get-Date).ToString('o')
    }

    if ($null -eq $MainState.PSObject.Properties['metadata'] -or $null -eq $MainState.metadata) {
        $MainState | Add-Member -MemberType NoteProperty -Name metadata -Value ([ordered]@{}) -Force
    }

    $routerDecision = [pscustomobject]@{
        configured_sub_runs = @($Decisions)
        active_sub_runs = @($Decisions | Where-Object { $_.active })
        inactive_sub_runs = @($Decisions | Where-Object { -not $_.active })
        router_key = $RouterKey
        decision_timestamp = $DecisionTimestamp
    }

    if ($MainState.metadata -is [System.Collections.IDictionary]) {
        $MainState.metadata['router_decision'] = $routerDecision
    } else {
        $MainState.metadata | Add-Member -MemberType NoteProperty -Name router_decision -Value $routerDecision -Force
    }
}
