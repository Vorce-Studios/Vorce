# Vorce-Autopilot/src/lib/autopilot-prompts.ps1
Set-StrictMode -Version Latest

$script:PromptsDir = Join-Path $PSScriptRoot "../../prompts"

function Get-VorceConfigPrompt {
    param(
        [AllowNull()][object]$Config,
        [Parameter(Mandatory)][string]$PromptKey,
        [hashtable]$Variables = @{}
    )

    $promptTemplate = $null

    # 1. Resolve relative path - supporting new flat PROMPT_* naming and old fallback
    $testFiles = @(
        "$PromptKey.md",
        "PROMPT_$PromptKey.md"
    )

    foreach ($file in $testFiles) {
        $testPath = Join-Path $script:PromptsDir $file
        if (Test-Path -LiteralPath $testPath) {
            $promptTemplate = Get-Content -LiteralPath $testPath -Raw -Encoding UTF8
            break
        }
    }

    # 2. Fallback to recursive search if not found in flat prompts/ folder
    if ([string]::IsNullOrWhiteSpace($promptTemplate)) {
        $mdFiles = Get-ChildItem -Path $script:PromptsDir -Filter "*$PromptKey.md" -Recurse -File -ErrorAction SilentlyContinue
        if ($mdFiles.Count -gt 0) {
            $promptTemplate = Get-Content -LiteralPath $mdFiles[0].FullName -Raw -Encoding UTF8
        }
    }

    # 3. Fallback to config prompts JSON if still not found
    if ([string]::IsNullOrWhiteSpace($promptTemplate)) {
        if ($Config -and ($Config.PSObject.Properties.Name -contains "prompts") -and
            $Config.prompts -and ($Config.prompts.PSObject.Properties.Name -contains $PromptKey)) {
            $promptTemplate = [string]$Config.prompts.$PromptKey
        }
    }

    if ([string]::IsNullOrWhiteSpace($promptTemplate)) {
        $promptTemplate = "Missing prompt template for key: $PromptKey"
    }

    $finalPrompt = $promptTemplate
    foreach ($key in $Variables.Keys) {
        $finalPrompt = $finalPrompt.Replace("`$$key", [string]$Variables[$key])
    }

    return $finalPrompt
}

function Get-VorceDashboardDataInstructions {
    $instructionsPath = Join-Path $script:PromptsDir "PROMPT_SYSTEM_DashboardInstructions.md"
    if (Test-Path -LiteralPath $instructionsPath) {
        return (Get-Content -LiteralPath $instructionsPath -Raw -Encoding UTF8).Trim()
    }
    return @"
Pflicht-Lagebild fuer diese Entscheidung:
Das Lagebild wurde vorab kompakt aggregiert und ist im System-Prompt eingebettet.
Nutze AUSSCHLIESSLICH dieses Lagebild zur Analyse.
Führe KEINE PowerShell Get-Content Befehle auf JSON-Dateien im Ordner Vorce-Autopilot aus! Das würde die Sitzung überlasten und blockieren.
"@.Trim()
}

function Get-VorceCodexCeoPrompt {
    return Get-VorceConfigPrompt -Config $null -PromptKey "ceo_system"
}

function Get-VorceCodexPlanningSessionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$TaskJournalPath,
        [Parameter(Mandatory)][string]$SessionLockPath
    )

    $dashboardInstructions = Get-VorceDashboardDataInstructions
    return Get-VorceConfigPrompt -Config $null -PromptKey "planning_session" -Variables @{
        Repository = $Repository
        TaskJournalPath = $TaskJournalPath
        SessionLockPath = $SessionLockPath
        dashboardInstructions = $dashboardInstructions
    }
}

function Get-VorceCodexMonitoringSessionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$TaskJournalPath,
        [Parameter(Mandatory)][string]$SessionLockPath
    )

    $dashboardInstructions = Get-VorceDashboardDataInstructions
    return Get-VorceConfigPrompt -Config $null -PromptKey "monitoring_session" -Variables @{
        Repository = $Repository
        TaskJournalPath = $TaskJournalPath
        SessionLockPath = $SessionLockPath
        dashboardInstructions = $dashboardInstructions
    }
}

function Get-VorcePlanningIssueDiscoveryPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$CandidateCount,
        [Parameter(Mandatory)][int]$MaxIssues
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "issue_discovery" -Variables @{
        Repository = $Repository
        CandidateCount = $CandidateCount
        MaxIssues = $MaxIssues
    }
}

function Get-VorceJulesImplementationPrompt {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Repository
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "jules_implementation" -Variables @{
        IssueNumber = $IssueNumber
        Repository = $Repository
    }
}

function Get-VorceJulesRetryPrompt {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$IssueTitle
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "jules_retry" -Variables @{
        IssueNumber = $IssueNumber
        IssueTitle = $IssueTitle
    }
}

function Get-VorcePrReviewPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$PullRequestUrl
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "pr_review" -Variables @{
        Repository = $Repository
        PullRequestNumber = $PullRequestNumber
        IssueNumber = $IssueNumber
        PullRequestUrl = $PullRequestUrl
    }
}

function Get-VorcePostMergeQaDispositionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$PullRequestTitle,
        [Parameter(Mandatory)][string]$PullRequestBody,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ChangedFiles,
        [Parameter(Mandatory)][string]$IssueTitle,
        [Parameter(Mandatory)][string]$IssueBody
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "post_merge_qa" -Variables @{
        Repository = $Repository
        PullRequestNumber = $PullRequestNumber
        IssueNumber = $IssueNumber
        PullRequestTitle = $PullRequestTitle
        PullRequestBody = $PullRequestBody
        ChangedFiles = $ChangedFiles
        IssueTitle = $IssueTitle
        IssueBody = $IssueBody
    }
}

function Get-VorceCliPrConflictResolutionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$HeadRefName,
        [Parameter(Mandatory)][string]$BaseRefName,
        [Parameter(Mandatory)][string]$PullRequestTitle
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "pr_conflict_resolution" -Variables @{
        Repository = $Repository
        PullRequestNumber = $PullRequestNumber
        HeadRefName = $HeadRefName
        BaseRefName = $BaseRefName
        PullRequestTitle = $PullRequestTitle
    }
}

function Get-VorceJulesPrCheckFixComment {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$HeadRefName,
        [Parameter(Mandatory)][string]$BaseRefName,
        [Parameter(Mandatory)][string]$PullRequestTitle,
        [string[]]$FailingChecks = @()
    )

    $checks = if ($FailingChecks.Count -gt 0) { $FailingChecks -join ", " } else { "unknown failing checks" }
    return Get-VorceConfigPrompt -Config $null -PromptKey "jules_pr_check_fix" -Variables @{
        Repository = $Repository
        PullRequestNumber = $PullRequestNumber
        HeadRefName = $HeadRefName
        BaseRefName = $BaseRefName
        PullRequestTitle = $PullRequestTitle
        checks = $checks
    }
}

function Get-VorceJulesPrConflictReplacementPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$BaseRefName,
        [Parameter(Mandatory)][string]$PullRequestTitle
    )

    return Get-VorceConfigPrompt -Config $null -PromptKey "jules_pr_conflict_replacement" -Variables @{
        Repository = $Repository
        PullRequestNumber = $PullRequestNumber
        BaseRefName = $BaseRefName
        PullRequestTitle = $PullRequestTitle
    }
}
