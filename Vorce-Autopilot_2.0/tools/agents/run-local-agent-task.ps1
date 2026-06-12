# scripts/codex-cli/tools/run-visible-agent-task.ps1
# Starts a visible local agent task for a specific GitHub issue.

param(
    [Parameter(Mandatory)][int]$IssueNumber,
    [Parameter(Mandatory)][string]$IssueTitle,
    [Parameter(Mandatory)][string]$AgentProvider,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$QuotaRegistryPath
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$autopilotRoot = Split-Path -Parent $scriptDir
$libCandidates = @(
    (Join-Path $autopilotRoot "src/lib"),
    (Join-Path $autopilotRoot "lib")
)
$libDir = $libCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($libDir)) {
    throw "Autopilot lib directory not found. Checked: $($libCandidates -join ', ')"
}
$varDbDir = Join-Path $autopilotRoot "var/db"
$tasksDir = Join-Path $varDbDir "agent-tasks"

if (-not (Test-Path $tasksDir)) { New-Item -ItemType Directory -Path $tasksDir | Out-Null }

$statusFile = Join-Path $tasksDir "$IssueNumber.json"

function Write-Status {
    param([string]$Status, [string]$PrUrl = "", [string]$ErrorMessage = "")
    $data = @{
        status = $Status
        pr_url = $PrUrl
        updated_at = (Get-Date -Format 'o')
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $data.error = $ErrorMessage
    }
    $data | ConvertTo-Json -Depth 5 | Set-Content $statusFile -Encoding UTF8
}

function Get-ConflictPrNumbers {
    param(
        [Parameter(Mandatory)][string]$Title,
        [AllowNull()][string]$Body
    )

    if ($Title -notmatch "(?i)Resolve-Merge-Conflicts?|Merge-Konflikt|Merge-Konflikte|Merge-Conflict|Konflikt") {
        return @()
    }

    $numbers = [System.Collections.Generic.List[int]]::new()

    $scanText = "$Title`n$Body"
    foreach ($rangeMatch in [regex]::Matches($scanText, '(?i)\bPRs?\s*[-_:#\s]*(\d+)\s*[-\u2013]\s*(\d+)\b')) {
        $start = [int]$rangeMatch.Groups[1].Value
        $end = [int]$rangeMatch.Groups[2].Value
        if ($start -le $end -and ($end - $start) -le 50) {
            for ($n = $start; $n -le $end; $n++) {
                $numbers.Add($n)
            }
        }
    }

    foreach ($match in [regex]::Matches($Title, '\d+')) {
        $numbers.Add([int]$match.Value)
    }

    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        foreach ($match in [regex]::Matches($Body, '(?i)\bPR\s*#?(\d+)\b')) {
            $numbers.Add([int]$match.Groups[1].Value)
        }
    }

    return @($numbers | Select-Object -Unique)
}

function Resolve-ConflictPr {
    param(
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$AgentProvider,
        [Parameter(Mandatory)][object]$Registry,
        [Parameter(Mandatory)][string]$QuotaRegistryPath
    )

    Write-Host "[2/4] Fetching conflict PR #$PullRequestNumber details..." -ForegroundColor Cyan
    $prDetailsJson = gh pr view $PullRequestNumber --repo $Repository --json state,mergeable,headRefName,baseRefName,title 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($prDetailsJson) -or $prDetailsJson -match "Could not resolve") {
        Write-Host "PR #$PullRequestNumber not found or error occurred; skipping. Details: $($prDetailsJson.Trim())" -ForegroundColor Yellow
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "SKIPPED_ERROR"; Details = "PR not found or gh error." }
    }

    $prDetails = $null
    try { $prDetails = $prDetailsJson | ConvertFrom-Json } catch { }

    if ($null -eq $prDetails -or -not ($prDetails.PSObject.Properties.Name -contains "state")) {
        Write-Host "PR #$PullRequestNumber invalid JSON or missing state; skipping." -ForegroundColor Yellow
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "SKIPPED_ERROR"; Details = "Invalid PR JSON." }
    }

    if ([string]$prDetails.state -ne "OPEN") {
        Write-Host "PR #$PullRequestNumber is not open; skipping." -ForegroundColor Yellow
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "SKIPPED_CLOSED"; Details = "PR is not open." }
    }
    if ([string]$prDetails.mergeable -ne "CONFLICTING") {
        Write-Host "PR #$PullRequestNumber is no longer conflicting; skipping." -ForegroundColor Green
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "SKIPPED_NOT_CONFLICTING"; Details = "mergeable=$($prDetails.mergeable)" }
    }

    $headBranch = [string]$prDetails.headRefName
    $baseBranch = [string]$prDetails.baseRefName
    $prTitle = [string]$prDetails.title

    Write-Host "Conflict PR Branch: $headBranch" -ForegroundColor Cyan
    Write-Host "Base Branch: $baseBranch" -ForegroundColor Cyan

    git fetch origin $headBranch
    git checkout -B $headBranch origin/$headBranch

    git fetch origin $baseBranch
    Write-Host "Merging origin/$baseBranch into $headBranch to trigger conflict resolution..." -ForegroundColor Yellow
    $mergeOutput = git merge origin/$baseBranch --no-commit --no-ff 2>&1 | Out-String
    Write-Host $mergeOutput -ForegroundColor DarkGray

    . (Join-Path $libDir "autopilot-prompts.ps1")
    $conflictFiles = @(git diff --name-only --diff-filter=U 2>$null)
    $fileList = if ($conflictFiles.Count -gt 0) { $conflictFiles -join "`n- " } else { "No unmerged files reported after merge command." }
    $prompt = (Get-VorceCliPrConflictResolutionPrompt -Repository $Repository -PullRequestNumber $PullRequestNumber -HeadRefName $headBranch -BaseRefName $baseBranch -PullRequestTitle $prTitle) + @"

Zusatzkontext:
Konfliktdateien laut `git diff --name-only --diff-filter=U`:
- $fileList

Pflicht:
- Loese den bestehenden PR-Branch lokal und minimal.
- Erstelle keinen neuen PR, keinen Ersatzauftrag und keine Jules-Session.
- Wenn ein Konflikt fachlich nicht aufloesbar ist, schreibe `Result: NEEDS_MANUAL_REVIEW` und nenne Dateien plus Grund.
"@

    Write-Host "[3/4] Running agent $AgentProvider for PR #$PullRequestNumber conflict resolution..." -ForegroundColor Cyan
    $result = Invoke-CliTask -QuotaRegistry $Registry -TaskType "merge_conflict_resolution" -Prompt $prompt -WorkingDirectory (Get-Location) -ProviderOverride $AgentProvider
    Save-QuotaRegistry -Registry $Registry -FilePath $QuotaRegistryPath

    if (-not $result.success) {
        git merge --abort 2>&1 | Out-Null
        git checkout main 2>&1 | Out-Null
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "FAILED"; Details = "Agent failed: $($result.error) $($result.output)" }
    }

    Write-Host "`nAgent Output:" -ForegroundColor DarkGray
    Write-Host $result.output -ForegroundColor DarkGray
    Write-Host "`n"

    if ($result.output -match "Result:\s*NEEDS_MANUAL_REVIEW") {
        git merge --abort 2>&1 | Out-Null
        git checkout main 2>&1 | Out-Null
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "NEEDS_MANUAL_REVIEW"; Details = $result.output }
    }

    Write-Host "[4/4] Committing resolved conflicts for PR #$PullRequestNumber..." -ForegroundColor Cyan
    $remainingConflicts = @(git diff --name-only --diff-filter=U 2>$null)
    if ($remainingConflicts.Count -gt 0) {
        git merge --abort 2>&1 | Out-Null
        git checkout main 2>&1 | Out-Null
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "FAILED_UNRESOLVED_FILES"; Details = ($remainingConflicts -join ", ") }
    }

    $statusOutput = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($statusOutput)) {
        git merge --abort 2>&1 | Out-Null
        git checkout main 2>&1 | Out-Null
        return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "SKIPPED_NO_CHANGES"; Details = "No changes after merge attempt." }
    }

    git add .
    git commit -m "Resolve merge conflicts for PR #$PullRequestNumber via $AgentProvider"
    git push origin $headBranch
    git checkout main

    return [pscustomobject]@{ PullRequestNumber = $PullRequestNumber; Status = "COMPLETED"; Details = "Pushed conflict resolution to $headBranch." }
}

Write-Status -Status "IN_PROGRESS"

try {
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  LOCAL AGENT TASK RUNNER" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Issue:    #$IssueNumber - $IssueTitle"
    Write-Host "Agent:    $AgentProvider"
    Write-Host "Repo:     $Repository"
    Write-Host "========================================`n"

    # Load lib
    . (Join-Path $libDir "state-manager.ps1")
    . (Join-Path $libDir "quota-manager.ps1")
    . (Join-Path $libDir "cli-router.ps1")

    $registry = Read-QuotaRegistry -FilePath $QuotaRegistryPath

    # 1. Fetch Issue Details
    Write-Host "[1/4] Fetching issue details..." -ForegroundColor Cyan
    $issueJson = gh issue view $IssueNumber --repo $Repository --json title,body | ConvertFrom-Json
    $body = $issueJson.body

    # 2. Branch setup and running Agent
    $conflictPrNumbers = @(Get-ConflictPrNumbers -Title $IssueTitle -Body $body)
    $isConflict = $conflictPrNumbers.Count -gt 0

    if ($isConflict) {
        Write-Host "[2/4] Conflict bundle detected: PRs $($conflictPrNumbers -join ', ')" -ForegroundColor Cyan
        $results = @()
        foreach ($prNumber in $conflictPrNumbers) {
            $results += Resolve-ConflictPr -PullRequestNumber $prNumber -Repository $Repository -AgentProvider $AgentProvider -Registry $registry -QuotaRegistryPath $QuotaRegistryPath
        }

        $summary = ($results | ForEach-Object { "PR #$($_.PullRequestNumber): $($_.Status) - $($_.Details)" }) -join "`n"
        Write-Host "`nConflict bundle summary:`n$summary" -ForegroundColor Cyan
        if (@($results | Where-Object { [string]$_.Status -match "^FAILED|NEEDS_MANUAL_REVIEW" }).Count -gt 0) {
            Write-Status -Status "FAILED"
            throw "One or more PR conflicts need manual review:`n$summary"
        }
        Write-Status -Status "COMPLETED"
        Write-Host "Closing issue $IssueNumber as all conflicts were resolved or skipped." -ForegroundColor Green
        gh issue close $IssueNumber --repo $Repository | Out-Null
    } else {
        Write-Host "[2/4] Setting up git branch..." -ForegroundColor Cyan
        git fetch origin main
        git checkout -B "main" origin/main
        $branchName = ($IssueTitle -replace "[^a-zA-Z0-9-]", "-") -replace "-+", "-"
        if ($branchName.Length -gt 50) { $branchName = $branchName.Substring(0, 50) }
        $branchName = "issue-$IssueNumber-$branchName"

        git checkout -b $branchName

        # 3. Running Agent
        Write-Host "[3/4] Running agent $AgentProvider..." -ForegroundColor Cyan
        $prompt = "Please solve the following issue (#${IssueNumber}: $IssueTitle).`n`nIssue Body:`n$body`n`nMake the necessary code changes. Do not commit."

        $result = Invoke-CliTask -QuotaRegistry $registry -TaskType "coding" -Prompt $prompt -WorkingDirectory (Get-Location) -ProviderOverride $AgentProvider

        Save-QuotaRegistry -Registry $registry -FilePath $QuotaRegistryPath

        if (-not $result.success) {
            throw "Agent execution failed: $($result.error)`nOutput: $($result.output)"
        }

        Write-Host "`nAgent Output:" -ForegroundColor DarkGray
        Write-Host $result.output -ForegroundColor DarkGray
        Write-Host "`n"

        # 4. Git Push & PR
        Write-Host "[4/4] Committing and creating PR..." -ForegroundColor Cyan

        $statusOutput = git status --porcelain
        if ([string]::IsNullOrWhiteSpace($statusOutput)) {
            Write-Host "No changes detected by the agent. Task completed without PR." -ForegroundColor Yellow
            Write-Status -Status "COMPLETED"
            Write-Host "Closing issue $IssueNumber as no changes were necessary." -ForegroundColor Green
            gh issue close $IssueNumber --repo $Repository | Out-Null
        } else {
            git add .
            git commit -m "Auto-commit from $AgentProvider for issue #$IssueNumber`n`n$IssueTitle"
            git push -u origin $branchName

            $prUrl = gh pr create --repo $Repository --title "$IssueTitle" --body "Automated PR by local agent $AgentProvider for issue #$IssueNumber.`nResolves #$IssueNumber"
            Write-Host "PR created: $prUrl" -ForegroundColor Green

            Write-Status -Status "COMPLETED" -PrUrl $prUrl
        }
    }

    Write-Host "`nTask completed successfully!" -ForegroundColor Green
    Start-Sleep -Seconds 5
} catch {
    Write-Host "`nTask failed: $_" -ForegroundColor Red
    Write-Status -Status "FAILED" -ErrorMessage ([string]$_)
    Start-Sleep -Seconds 10
}
