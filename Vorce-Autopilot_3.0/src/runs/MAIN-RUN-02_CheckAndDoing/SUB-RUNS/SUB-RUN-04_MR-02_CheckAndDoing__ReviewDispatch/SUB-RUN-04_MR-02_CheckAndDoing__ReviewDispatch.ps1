# src/runs/SUB-RUN/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1
# PR-Sync, Merge-Konflikt-Erkennung und Claude-Code-Review-Dispatching
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-04 ReviewDispatch: Pruefe PRs und dispatche Reviews..." -ForegroundColor Cyan

$repo = $Config.repository
$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../../..")
$VarDbDir = Join-Path $ScriptDir "var/db"

# Verwende PRs aus MainState (falls von JulesCheck bereits geladen)
$prs = @()
if ($MainState.PSObject.Properties.Name -contains "OpenPRs" -and $null -ne $MainState.OpenPRs) {
    $prs = @($MainState.OpenPRs)
} else {
    $cachedPrPath = Join-Path $VarDbDir "pull-requests.json"
    if (Test-Path $cachedPrPath) {
        try {
            $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
                $prs = @($prsRaw | Where-Object { $_.state -eq "OPEN" -and $_.repo -eq $repo })
            }
        } catch {
            Write-Warning "[CHECK&DOING] Fehler beim Lesen der gecachten PRs: $_"
        }
    }
    if ($prs.Count -eq 0) {
        try { $prs = Get-GitHubPullRequests -Repository $repo -Limit 100 } catch { $prs = @() }
    }
}

Write-Host "[CHECK&DOING] $($prs.Count) offene PRs gefunden." -ForegroundColor DarkGray

# --- PR Status-Check ---
$conflictingPrs = @()
foreach ($pr in $prs) {
    $prNum = [int]$pr.number
    $mergeable = [string]$pr.mergeable

    if ($mergeable -eq "CONFLICTING") {
        Write-Host ("[CHECK&DOING]   PR #{0} MERGE CONFLICT!" -f $prNum) -ForegroundColor Red
        $conflictingPrs += $pr
    }

    $failingChecks = @()
    $checks = if (Test-ObjectProperty -Object $pr -Name "statusCheckRollup") { $pr.statusCheckRollup } else { @() }
    if ($checks) {
        $failingChecks = @($checks | Where-Object {
            ((Test-ObjectProperty -Object $_ -Name "conclusion") -and $_.conclusion -eq "FAILURE") -or
            ((Test-ObjectProperty -Object $_ -Name "status") -and $_.status -eq "FAILURE")
        })
    }

    if ($failingChecks.Count -gt 0) {
        $failNames = ($failingChecks | ForEach-Object { $_.name }) -join ", "
        Write-Host ("[CHECK&DOING]   PR #{0} {1} Checks fehlgeschlagen ({2})" -f $prNum, $failingChecks.Count, $failNames) -ForegroundColor Red
    }
}
Sync-OpenPullRequestsToReviewQueue -State $GlobalState -PullRequests $prs

# --- Review Result Polling ---
$reviewResultsDir = Join-Path $VarDbDir "reviews"
if (-not (Test-Path $reviewResultsDir)) {
    New-Item -ItemType Directory -Path $reviewResultsDir -Force | Out-Null
}

$resultFiles = Get-ChildItem -Path $reviewResultsDir -Filter "*-result.json"
foreach ($file in $resultFiles) {
    try {
        $resultData = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $prNum = [int]$resultData.pr_number
        $review = $GlobalState.review_queue | Where-Object { [int]$_.pr_number -eq $prNum } | Select-Object -First 1

        if ($null -ne $review) {
            if ($resultData.success -and [string]$resultData.provider -eq "claude_code") {
                $review.review_status = "completed"
                $review | Add-Member -MemberType NoteProperty -Name "review_provider" -Value "claude_code" -Force
                $review | Add-Member -MemberType NoteProperty -Name "reviewed_at" -Value ([string]$resultData.completed_at) -Force
                $reviewedRevision = if (Test-ObjectProperty -Object $review -Name "pr_updated_at") { [string]$review.pr_updated_at } else { "" }
                $review | Add-Member -MemberType NoteProperty -Name "reviewed_pr_updated_at" -Value $reviewedRevision -Force
                Write-Host "[CHECK&DOING]   Async Review fuer PR #$($review.pr_number) erfolgreich abgeschlossen via $($resultData.provider)." -ForegroundColor Green
            } elseif ($resultData.success) {
                $review.review_status = "pending"
                Write-Warning "[CHECK&DOING]   Async Review fuer PR #$($review.pr_number) via $($resultData.provider) wird nicht als Merge-Freigabe akzeptiert; Claude Code ist verpflichtend."
            } else {
                $errMsg = "Async Review fuer PR #$($review.pr_number) fehlgeschlagen: $($resultData.output)"
                Write-Warning "[CHECK&DOING]   $errMsg"
                Add-ErrorLog -State $GlobalState -Message "PR Review Failed for PR #$($review.pr_number)" -Context $errMsg
            }
        }
        Remove-Item -LiteralPath $file.FullName -Force
    } catch {
        Write-Warning "[CHECK&DOING] Fehler beim Verarbeiten von Review-Resultat $($file.Name): $_"
    }
}


# Speichere Conflict-Info im MainState
if (-not ($MainState.PSObject.Properties.Name -contains "ConflictingPRs")) {
    $MainState | Add-Member -MemberType NoteProperty -Name "ConflictingPRs" -Value @() -Force
}
$MainState.ConflictingPRs = $conflictingPrs

# --- Review-Queue Processing (Claude-Code zwingend) ---
foreach ($review in @($GlobalState.review_queue)) {
    $reviewProvider = if (Test-ObjectProperty -Object $review -Name "review_provider") { [string]$review.review_provider } else { "" }
    if ($review.review_status -eq "completed" -and $reviewProvider -ne "claude_code") {
        $review.review_status = "pending"
        $review | Add-Member -MemberType NoteProperty -Name "review_provider" -Value $null -Force
        Write-Host "[CHECK&DOING]   PR #$($review.pr_number) wird fuer verpflichtendes Claude-Code-Review erneut eingereiht." -ForegroundColor Yellow
    }
}

$pendingReviews = @($GlobalState.review_queue | Where-Object { $_.review_status -eq "pending" })
if ($pendingReviews.Count -gt 0) {
    Write-Host "[CHECK&DOING] $($pendingReviews.Count) PRs im Review-Queue." -ForegroundColor Cyan

    foreach ($review in $pendingReviews) {
        if ($DryRun.IsPresent) {
            Write-Host "[CHECK&DOING] [DRY RUN] Wuerde Claude-Code-Review fuer PR #$($review.pr_number) starten." -ForegroundColor Yellow
            continue
        }

        $promptVars = @{
            repo = $repo
            pr_number = $review.pr_number
            issue_number = $review.issue_number
            pr_url = $review.pr_url
        }
        $reviewPrompt = Get-VorceConfigPrompt -Config $Config -PromptKey "pr_review" -Variables $promptVars
        if ($reviewPrompt -match "^Missing prompt template") {
            $reviewPrompt = "Starte Skill /vorce-pr-review $($review.pr_number)"
        }

        # Check if review result file exists or if it's already dispatched
        $expectedResultPath = Join-Path $reviewResultsDir "pr-$($review.pr_number)-result.json"
        if (Test-Path $expectedResultPath) {
            Write-Host "[CHECK&DOING]   Review fuer PR #$($review.pr_number) laeuft bereits im Hintergrund..." -ForegroundColor DarkGray
            continue
        }

        # Check if a pwsh process with this PR number is already running
        $isRunning = $false
        $processes = Get-WmiObject Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue
        if ($null -ne $processes) {
            foreach ($p in $processes) {
                if ($p.CommandLine -match "run-background-review.ps1.*-PullRequestNumber $($review.pr_number)\b") {
                    $isRunning = $true
                    break
                }
            }
        }

        if ($isRunning) {
            Write-Host "[CHECK&DOING]   Review-Prozess fuer PR #$($review.pr_number) laeuft noch..." -ForegroundColor DarkGray
            continue
        }

        # Dispatch as background process
        $toolsDir = Join-Path $ScriptDir "tools"
        $scriptPath = Join-Path $toolsDir "agents/run-background-review.ps1"
        $configPath = Join-Path $ScriptDir "config/autopilot-config.json"
        $quotaPath = Join-Path $ScriptDir "config/quota-registry.json"

        # Save substate temporarily for the script to read
        $subStateTempPath = Join-Path $reviewResultsDir "pr-$($review.pr_number)-substate.json"
        $SubState | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $subStateTempPath -Encoding UTF8 -Force

        $cmdArgs = "-NoProfile", "-WindowStyle", "Hidden", "-File", "`"$scriptPath`"", "-PullRequestNumber", $($review.pr_number), "-Repository", "`"$repo`"", "-ReviewPrompt", "`"$reviewPrompt`"", "-ConfigPath", "`"$configPath`"", "-QuotaRegistryPath", "`"$quotaPath`"", "-SubStatePath", "`"$subStateTempPath`"", "-OutputFilePath", "`"$expectedResultPath`""

        try {
            Start-Process pwsh -ArgumentList $cmdArgs
            Write-Host "[CHECK&DOING]   Background Review fuer PR #$($review.pr_number) wurde erfolgreich dispatched." -ForegroundColor Green
        } catch {
            Write-Warning "[CHECK&DOING]   Fehler beim Dispatchen des Reviews fuer PR #$($review.pr_number): $_"
        }
    }
}

$SubState.status = "completed"
$SubState.artifacts += @{
    type = "ReviewDispatchReport"
    timestamp = (Get-Date).ToString('o')
    open_prs = $prs.Count
    conflicting_prs = $conflictingPrs.Count
    pending_reviews = $pendingReviews.Count
}
