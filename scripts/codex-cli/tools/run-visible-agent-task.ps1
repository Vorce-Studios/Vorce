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
$libDir = Join-Path (Split-Path -Parent $scriptDir) "lib"
$tmpDir = Join-Path (Split-Path -Parent $scriptDir) "tmp"
$tasksDir = Join-Path $tmpDir "agent-tasks"

if (-not (Test-Path $tasksDir)) { New-Item -ItemType Directory -Path $tasksDir | Out-Null }

$statusFile = Join-Path $tasksDir "$IssueNumber.json"

function Write-Status {
    param([string]$Status, [string]$PrUrl = "")
    $data = @{
        status = $Status
        pr_url = $PrUrl
        updated_at = (Get-Date -Format 'o')
    }
    $data | ConvertTo-Json -Depth 5 | Set-Content $statusFile -Encoding UTF8
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
    . (Join-Path $libDir "quota-manager.ps1")
    . (Join-Path $libDir "cli-router.ps1")

    $registry = Read-QuotaRegistry -FilePath $QuotaRegistryPath

    # 1. Fetch Issue Details
    Write-Host "[1/4] Fetching issue details..." -ForegroundColor Cyan
    $issueJson = gh issue view $IssueNumber --repo $Repository --json body | ConvertFrom-Json
    $body = $issueJson.body

    # 2. Branch setup and running Agent
    $isConflict = $false
    $conflictPrNum = 0
    if ($IssueTitle -match "MF-StIs_Resolve-Merge-Conflict-PR-(\d+)") {
        $isConflict = $true
        $conflictPrNum = [int]$Matches[1]
    }

    if ($isConflict) {
        Write-Host "[2/4] Fetching conflict PR #$conflictPrNum details..." -ForegroundColor Cyan
        $prDetails = gh pr view $conflictPrNum --repo $Repository --json headRefName,baseRefName,title | ConvertFrom-Json
        $headBranch = $prDetails.headRefName
        $baseBranch = $prDetails.baseRefName
        $prTitle = $prDetails.title

        Write-Host "Conflict PR Branch: $headBranch" -ForegroundColor Cyan
        Write-Host "Base Branch: $baseBranch" -ForegroundColor Cyan

        # Checkout PR branch
        git fetch origin $headBranch
        git checkout -B $headBranch origin/$headBranch

        # Merge base branch to prepare conflicts
        git fetch origin $baseBranch
        Write-Host "Merging origin/$baseBranch into $headBranch to trigger conflict resolution..." -ForegroundColor Yellow
        $mergeOutput = git merge origin/$baseBranch --no-commit --no-ff 2>&1 | Out-String
        Write-Host $mergeOutput -ForegroundColor DarkGray

        # Get Conflict Prompt from lib/autopilot-prompts.ps1
        . (Join-Path $libDir "autopilot-prompts.ps1")
        $prompt = Get-VorceCliPrConflictResolutionPrompt -Repository $Repository -PullRequestNumber $conflictPrNum -HeadRefName $headBranch -BaseRefName $baseBranch -PullRequestTitle $prTitle

        # 3. Running Agent on merge_conflict_resolution task
        Write-Host "[3/4] Running agent $AgentProvider for conflict resolution..." -ForegroundColor Cyan
        $result = Invoke-CliTask -QuotaRegistry $registry -TaskType "merge_conflict_resolution" -Prompt $prompt -WorkingDirectory (Get-Location) -ProviderOverride $AgentProvider

        Save-QuotaRegistry -Registry $registry -FilePath $QuotaRegistryPath

        if (-not $result.success) {
            if ($result.output -match "Result: TOO_MANY_CONFLICTS") {
                Write-Host "Agent reported TOO_MANY_CONFLICTS. Closing PR #$conflictPrNum..." -ForegroundColor Red
                gh pr close $conflictPrNum --repo $Repository --comment "Closing PR due to unresolvable merge conflicts. Autopilot will launch a fresh implementation." 2>&1 | Out-Null
                git checkout main
                git branch -D $headBranch 2>&1 | Out-Null
                Write-Status -Status "COMPLETED"
                return
            }
            throw "Agent conflict resolution failed: $($result.error)`nOutput: $($result.output)"
        }

        Write-Host "`nAgent Output:" -ForegroundColor DarkGray
        Write-Host $result.output -ForegroundColor DarkGray
        Write-Host "`n"

        # 4. Commit and push the resolved conflicts
        Write-Host "[4/4] Committing resolved conflicts..." -ForegroundColor Cyan
        $statusOutput = git status --porcelain
        if ([string]::IsNullOrWhiteSpace($statusOutput)) {
            Write-Host "No changes detected (conflicts resolved but no changes?)." -ForegroundColor Yellow
            git merge --abort 2>&1 | Out-Null
            Write-Status -Status "COMPLETED"
        } else {
            git add .
            git commit -m "Auto-resolve conflicts by $AgentProvider via PR #$conflictPrNum"
            git push origin $headBranch

            Write-Host "Conflict PR #$conflictPrNum resolved and pushed successfully!" -ForegroundColor Green
            Write-Status -Status "COMPLETED"
        }

        # Return to main
        git checkout main
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
        $prompt = "Please solve the following issue (#$IssueNumber: $IssueTitle).`n`nIssue Body:`n$body`n`nMake the necessary code changes. Do not commit."

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
    Write-Status -Status "FAILED"
    Start-Sleep -Seconds 10
}
