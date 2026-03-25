[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [int]$MasterIssueNumber,

    [string]$Repository,
    [string]$ApiKey,
    [int]$InitialWaitMinutes = 15,
    [int]$PollMinutes = 5,
    [bool]$AutoCreatePr = $true,
    [switch]$DryRun,
    [string]$GeminiPromptTemplate,
    [string]$GeminiWorktreePath
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..")

. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

function Write-Step {
    param([string]$Message)
    Write-Host "[MASTER] $Message" -ForegroundColor Cyan
}

function Get-IssueSectionNumbers {
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$SectionHeading
    )

    $headingPattern = [regex]::Escape("## $SectionHeading")
    $sectionPattern = "(?ms)^$headingPattern\s*$\s*(?<content>.*?)(?=^##\s+|\z)"
    $match = [regex]::Match($Body, $sectionPattern)
    if (-not $match.Success) {
        throw "Sektion '$SectionHeading' wurde im Master-Issue nicht gefunden."
    }

    $numbers = @()
    foreach ($line in (($match.Groups["content"].Value) -split "`r?`n")) {
        if ($line -match '#(?<number>\d+)') {
            $numbers += [int]$Matches.number
        }
    }

    return @($numbers)
}

function Get-IssueFormFieldValue {
    param(
        [Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$FieldName
    )

    $pattern = "(?ms)^###\s+$([regex]::Escape($FieldName))\s*$\s*(?<value>.*?)(?=^###\s+|\z)"
    $match = [regex]::Match($Body, $pattern)
    if (-not $match.Success) {
        return $null
    }

    foreach ($line in ($match.Groups["value"].Value -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            return $trimmed
        }
    }

    return $null
}

function Set-IssueFormFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][hashtable]$Updates
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { "" } else { [string]$issue.body }

    foreach ($entry in $Updates.GetEnumerator()) {
        if ($null -eq $entry.Value) {
            continue
        }

        $fieldName = [string]$entry.Key
        $fieldValue = [string]$entry.Value
        $escapedField = [regex]::Escape($fieldName)
        $pattern = "(?ms)(^###\s+$escapedField\s*$\s*)(?<value>.*?)(?=^###\s+|\z)"
        if ([regex]::IsMatch($body, $pattern)) {
            $replacement = '${1}' + $fieldValue + "`n`n"
            $body = [regex]::Replace($body, $pattern, $replacement, 1)
        }
    }

    Set-GitHubIssueBody -Repository $Repository -IssueNumber $IssueNumber -Body $body
}

function Ensure-IssueOpen {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    if ([string]$issue.state -eq "CLOSED") {
        gh issue reopen $IssueNumber --repo $Repository | Out-Null
    }
}

function Test-IsFinalStatus {
    param([AllowNull()][string]$Status)

    return @("Done", "Completed", "Closed", "Merged") -contains [string]$Status
}

function Ensure-IssueOpenForStatus {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [AllowNull()][string]$TargetStatus
    )

    if (-not (Test-IsFinalStatus -Status $TargetStatus)) {
        Ensure-IssueOpen -Repository $Repository -IssueNumber $IssueNumber
    }
}

function Get-LatestVerificationVerdict {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber
    )

    $comments = @(Get-GitHubIssueComments -Repository $Repository -IssueNumber $IssueNumber)
    if ($comments.Count -eq 0) {
        return $null
    }

    $sorted = @(
        $comments |
            Sort-Object {
                if ($_.PSObject.Properties.Name -contains 'created_at') {
                    [datetimeoffset]$_.created_at
                } elseif ($_.PSObject.Properties.Name -contains 'createdAt') {
                    [datetimeoffset]$_.createdAt
                } else {
                    [datetimeoffset]::MinValue
                }
            } -Descending
    )

    foreach ($comment in $sorted) {
        $body = [string]$comment.body
        if ($body -match '(?im)\bResult:\s*PASS\b' -or $body -match '(?im)\breturned PASS\b') {
            return "PASS"
        }

        if ($body -match '(?im)\bREJECT\b' -or $body -match '(?im)\bnot verification-pass ready\b') {
            return "REJECT"
        }
    }

    return $null
}

function Get-IssueSnapshot {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber
    )

    $issue = Get-GitHubIssue -Repository $Repository -IssueNumber $IssueNumber
    $body = if ($null -eq $issue.body) { "" } else { [string]$issue.body }
    $sessionReference = Get-JulesSessionReferenceFromIssue -Repository $Repository -IssueNumber $IssueNumber

    [pscustomobject]@{
        Issue            = $issue
        Body             = $body
        Status           = Get-IssueFormFieldValue -Body $body -FieldName "Status"
        Agent            = Get-IssueFormFieldValue -Body $body -FieldName "agent"
        JulesSession     = Get-IssueFormFieldValue -Body $body -FieldName "jules_session"
        RemoteState      = Get-IssueFormFieldValue -Body $body -FieldName "remote_state"
        WorkBranch       = Get-IssueFormFieldValue -Body $body -FieldName "work_branch"
        LastUpdate       = Get-IssueFormFieldValue -Body $body -FieldName "last_update"
        SessionReference = $sessionReference
        VerifyVerdict    = Get-LatestVerificationVerdict -Repository $Repository -IssueNumber $IssueNumber
    }
}

function Test-ImplementationComplete {
    param([Parameter(Mandatory)][object]$Snapshot)

    $doneStatus = Test-IsFinalStatus -Status ([string]$Snapshot.Status)
    $mergedRemote = @("merged") -contains ([string]$Snapshot.RemoteState).ToLowerInvariant()
    return $doneStatus -and $mergedRemote
}

function Test-VerificationPassed {
    param([Parameter(Mandatory)][object]$Snapshot)

    $doneStatus = Test-IsFinalStatus -Status ([string]$Snapshot.Status)
    return $doneStatus -and [string]$Snapshot.VerifyVerdict -eq "PASS"
}

function Test-VerificationRejected {
    param([Parameter(Mandatory)][object]$Snapshot)

    return [string]$Snapshot.VerifyVerdict -eq "REJECT" -or [string]$Snapshot.Status -eq "Blocked"
}

function Update-ImplementationFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Status,
        [string]$SessionId,
        [string]$RemoteState,
        [string]$WorkBranch,
        [string]$LastUpdate
    )

    Ensure-IssueOpenForStatus -Repository $Repository -IssueNumber $IssueNumber -TargetStatus $Status
    Set-IssueFormFields -Repository $Repository -IssueNumber $IssueNumber -Updates @{
        "Status"        = $Status
        "agent"         = "Jules"
        "jules_session" = $(if ([string]::IsNullOrWhiteSpace($SessionId)) { "n/a" } else { $SessionId })
        "remote_state"  = $(if ([string]::IsNullOrWhiteSpace($RemoteState)) { "n/a" } else { $RemoteState })
        "work_branch"   = $(if ([string]::IsNullOrWhiteSpace($WorkBranch)) { "n/a" } else { $WorkBranch })
        "last_update"   = $(if ([string]::IsNullOrWhiteSpace($LastUpdate)) { (Get-Date -Format "yyyy-MM-dd") } else { $LastUpdate })
    }
}

function Update-VerificationFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Status,
        [string]$RemoteState,
        [string]$LastUpdate
    )

    Ensure-IssueOpenForStatus -Repository $Repository -IssueNumber $IssueNumber -TargetStatus $Status
    Set-IssueFormFields -Repository $Repository -IssueNumber $IssueNumber -Updates @{
        "Status"       = $Status
        "agent"        = "Codex / Gemini CLI"
        "remote_state" = $(if ([string]::IsNullOrWhiteSpace($RemoteState)) { "n/a" } else { $RemoteState })
        "last_update"  = $(if ([string]::IsNullOrWhiteSpace($LastUpdate)) { (Get-Date -Format "yyyy-MM-dd") } else { $LastUpdate })
    }
}

function Sync-TrackingAndMirrorFields {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][object]$Session,
        [string]$StartingBranch
    )

    $snapshot = Sync-JulesIssueTracking -Repository $Repository -IssueNumber $IssueNumber -Session $Session -LatestActivity $null -StartingBranch $StartingBranch -SourceName ([string]$Session.sourceContext.source)
    Set-IssueFormFields -Repository $Repository -IssueNumber $IssueNumber -Updates @{
        "jules_session" = $(if ([string]::IsNullOrWhiteSpace([string]$snapshot.SessionId)) { (Resolve-JulesSessionId -SessionIdOrName ([string]$Session.name)) } else { [string]$snapshot.SessionId })
        "remote_state"  = [string]$snapshot.RemoteState
        "work_branch"   = [string]$snapshot.WorkBranch
        "last_update"   = [string]$snapshot.LastUpdate
    }
}

function Wait-ForJulesState {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][int]$InitialWaitMinutes,
        [Parameter(Mandatory)][int]$PollMinutes,
        [string]$ApiKey
    )

    $sleptInitial = $false

    while ($true) {
        $session = Get-JulesSession -SessionIdOrName $SessionId -ApiKey $ApiKey
        $state = [string]$session.state
        Write-Step ("Jules Session {0}: {1}" -f $SessionId, $state)

        if ($state -eq "COMPLETED") {
            return $session
        }

        if (@("AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "PAUSED", "FAILED") -contains $state) {
            throw "Jules Session $SessionId braucht Aufmerksamkeit: $state"
        }

        if (@("QUEUED", "PLANNING", "IN_PROGRESS") -notcontains $state) {
            throw "Jules Session $SessionId ended with unexpected state '$state'."
        }

        if (-not $sleptInitial) {
            Write-Step "Warte $InitialWaitMinutes Minuten vor dem ersten Folgecheck."
            Start-Sleep -Seconds ($InitialWaitMinutes * 60)
            $sleptInitial = $true
        } else {
            Start-Sleep -Seconds ($PollMinutes * 60)
        }
    }
}

function Wait-ForPullRequestMerge {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$PullRequestUrl,
        [Parameter(Mandatory)][int]$PollMinutes
    )

    $prNumber = $PullRequestUrl -replace '.*/pull/(\d+)$', '$1'
    while ($true) {
        $pr = gh pr view $prNumber --repo $Repository --json number,state,mergedAt,url,title,headRefName | ConvertFrom-Json
        if ($pr.state -eq "MERGED") {
            return $pr
        }

        $checks = @(gh pr checks $prNumber --repo $Repository --required --json name,bucket,state,conclusion 2>$null | ConvertFrom-Json)
        $failing = @($checks | Where-Object { $_.bucket -eq "fail" -or $_.state -eq "FAILED" -or $_.conclusion -eq "FAILURE" })
        if ($failing.Count -gt 0) {
            throw "PR-Checks sind fehlgeschlagen: $((($failing | ForEach-Object { $_.name }) -join ', '))"
        }

        Write-Step "PR noch nicht gemerged. Nächster Check in $PollMinutes Minuten."
        Start-Sleep -Seconds ($PollMinutes * 60)
    }
}

function Resolve-PullRequestUrlForIssue {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [string]$SessionId
    )

    $searchQueries = @()
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $searchQueries += ('"{0}" in:body' -f $SessionId)
    }

    $searchQueries += @(
        ('"Fixes #{0}" in:body' -f $IssueNumber),
        ('"#{0}" in:body' -f $IssueNumber)
    )

    foreach ($query in $searchQueries | Select-Object -Unique) {
        $results = @(
            gh pr list --repo $Repository --state all --search $query --json number,url,state,headRefName,title 2>$null |
                ConvertFrom-Json
        )

        if ($results.Count -gt 0) {
            $selected = @($results | Sort-Object number -Descending | Select-Object -First 1)
            if ($selected.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$selected[0].url)) {
                return [string]$selected[0].url
            }
        }
    }

    return $null
}

function Sync-GeminiWorktree {
    param([Parameter(Mandatory)][string]$WorktreePath)

    git fetch origin | Out-Null
    if (-not (Test-Path $WorktreePath)) {
        Write-Step "Erstelle sauberen Gemini-Worktree unter $WorktreePath"
        git worktree add $WorktreePath origin/main | Out-Null
        return
    }

    git -C $WorktreePath fetch origin | Out-Null
    git -C $WorktreePath checkout --detach origin/main | Out-Null
}

function Invoke-GeminiVerification {
    param(
        [Parameter(Mandatory)][string]$WorktreePath,
        [Parameter(Mandatory)][int]$ImplementationIssueNumber,
        [Parameter(Mandatory)][int]$VerifyIssueNumber,
        [string]$PromptTemplate
    )

    Sync-GeminiWorktree -WorktreePath $WorktreePath

    $prompt = if (-not [string]::IsNullOrWhiteSpace($PromptTemplate)) {
        $PromptTemplate
    } else {
        @"
You are responsible for GitHub verify issue #$VerifyIssueNumber for implementation issue #$ImplementationIssueNumber.

Use the clean repository state at $WorktreePath and the GitHub repository $Repository.

Required:
1. Review the implementation result against the verify issue requirements.
2. Update verify issue #$VerifyIssueNumber yourself:
   - edit the verify issue body so the review checkboxes reflect the actual result
   - after the checkbox update, run `scripts/jules/set-managed-issue-state.ps1` to write the managed fields and optional GitHub Project fields
   - set 'Status' to 'Done' when the review is finished, regardless of PASS or REJECT
   - keep 'agent' as `Gemini CLI`
   - use `remote_state` `merged` for both PASS and REJECT because the review targets the merged implementation state
   - add a final comment with either PASS or REJECT and the exact blockers when rejecting
   - example PASS command:
     `powershell -ExecutionPolicy Bypass -File .\\scripts\\jules\\set-managed-issue-state.ps1 -IssueNumber $VerifyIssueNumber -Repository $Repository -Status Done -Agent 'Gemini CLI' -RemoteState merged -QueueState closed`
   - example REJECT command:
     `powershell -ExecutionPolicy Bypass -File .\\scripts\\jules\\set-managed-issue-state.ps1 -IssueNumber $VerifyIssueNumber -Repository $Repository -Status Done -Agent 'Gemini CLI' -RemoteState merged -QueueState closed`
3. Do not manually close the issue.
4. Before you finish, verify with gh issue view that the issue body now contains the final checkbox state and the final Status value.
5. Return only a short summary of what you changed and the final PASS or REJECT verdict.
"@
    }

    Push-Location $WorktreePath
    try {
        return (gemini -p $prompt --approval-mode yolo --yolo --sandbox false --output-format text 2>&1 | Out-String)
    } finally {
        Pop-Location
    }
}

function Wait-ForVerificationFinalization {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [int]$TimeoutSeconds = 120,
        [int]$PollSeconds = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $snapshot = Get-IssueSnapshot -Repository $Repository -IssueNumber $IssueNumber
        if ((Test-VerificationPassed -Snapshot $snapshot) -or (Test-VerificationRejected -Snapshot $snapshot)) {
            return $snapshot
        }

        Start-Sleep -Seconds $PollSeconds
    }

    return (Get-IssueSnapshot -Repository $Repository -IssueNumber $IssueNumber)
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$masterIssue = Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $MasterIssueNumber
$masterBody = if ($null -eq $masterIssue.body) { "" } else { [string]$masterIssue.body }

$implementationNumbers = Get-IssueSectionNumbers -Body $masterBody -SectionHeading "Implementation Subissues (Jules)"
$verificationNumbers = Get-IssueSectionNumbers -Body $masterBody -SectionHeading "Verification Subissues (4-eyes/Review immediately after each implementation)"

if ($implementationNumbers.Count -eq 0) {
    throw "Keine Implementierungs-Subissues im Master-Issue #$MasterIssueNumber gefunden."
}

if ($implementationNumbers.Count -ne $verificationNumbers.Count) {
    throw "Anzahl der Implementierungs- und Verify-Subissues stimmt nicht ueberein: $($implementationNumbers.Count) vs. $($verificationNumbers.Count)."
}

$geminiWorktree = if (-not [string]::IsNullOrWhiteSpace($GeminiWorktreePath)) { $GeminiWorktreePath } else { Join-Path (Split-Path $RepoRoot -Parent) "VjMapper-gemini" }

Write-Step ("Master-Issue #{0}: {1}" -f $MasterIssueNumber, $masterIssue.title)

if ($DryRun.IsPresent) {
    Write-Step "DRY RUN"
    for ($i = 0; $i -lt $implementationNumbers.Count; $i++) {
        $implNumber = [int]$implementationNumbers[$i]
        $verifyNumber = [int]$verificationNumbers[$i]
        $implSnapshot = Get-IssueSnapshot -Repository $resolvedRepository -IssueNumber $implNumber
        $verifySnapshot = Get-IssueSnapshot -Repository $resolvedRepository -IssueNumber $verifyNumber
        Write-Step ("Paar {0}:{1} | Impl={2}/{3} | Verify={4}/{5}/{6}" -f $implNumber, $verifyNumber, $implSnapshot.Issue.state, $implSnapshot.Status, $verifySnapshot.Issue.state, $verifySnapshot.Status, $(if ($null -eq $verifySnapshot.VerifyVerdict) { "n/a" } else { $verifySnapshot.VerifyVerdict }))
    }
    return
}

for ($i = 0; $i -lt $implementationNumbers.Count; $i++) {
    $implNumber = [int]$implementationNumbers[$i]
    $verifyNumber = [int]$verificationNumbers[$i]

    $implSnapshot = Get-IssueSnapshot -Repository $resolvedRepository -IssueNumber $implNumber
    $verifySnapshot = Get-IssueSnapshot -Repository $resolvedRepository -IssueNumber $verifyNumber

    if ((Test-ImplementationComplete -Snapshot $implSnapshot) -and (Test-VerificationPassed -Snapshot $verifySnapshot)) {
        Write-Step ("Ueberspringe abgeschlossenes Paar {0}:{1}" -f $implNumber, $verifyNumber)
        continue
    }

    if (Test-VerificationRejected -Snapshot $verifySnapshot) {
        throw ("Paar {0}:{1} ist bereits mit REJECT abgeschlossen. Vor dem naechsten Jules-Issue ist zuerst Rework oder eine manuelle Neubewertung noetig." -f $implNumber, $verifyNumber)
    }

    if (-not (Test-ImplementationComplete -Snapshot $implSnapshot) -and (Test-VerificationPassed -Snapshot $verifySnapshot)) {
        throw ("Inkonsistenter Zustand fuer Paar {0}:{1}: Verify ist PASS, Implementation aber nicht abgeschlossen." -f $implNumber, $verifyNumber)
    }

    Write-Step ("Bearbeite Paar {0}:{1}" -f $implNumber, $verifyNumber)

    $session = $null
    $sessionId = $null

    if (-not (Test-ImplementationComplete -Snapshot $implSnapshot)) {
    if ($implSnapshot.SessionReference) {
        $sessionId = [string]$implSnapshot.SessionReference.SessionId
        Write-Step ("Verwende bestehende Jules Session {0} fuer Issue #{1}" -f $sessionId, $implNumber)
        $session = Get-JulesSession -SessionIdOrName $sessionId -ApiKey $ApiKey
        Sync-TrackingAndMirrorFields -Repository $resolvedRepository -IssueNumber $implNumber -Session $session -StartingBranch "main"

            $state = [string]$session.state
            if (@("AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "PAUSED", "FAILED") -contains $state) {
                Update-ImplementationFields -Repository $resolvedRepository -IssueNumber $implNumber -Status "Blocked" -SessionId $sessionId -RemoteState ([string]$session.state).ToLowerInvariant() -WorkBranch "main" -LastUpdate (Get-Date -Format "yyyy-MM-dd")
                throw ("Jules Session fuer Issue #{0} braucht Aufmerksamkeit: {1}" -f $implNumber, $state)
            }
        } else {
            Write-Step ("Starte neue Jules Session fuer Issue #{0}" -f $implNumber)
            $sessionResult = & "$ScriptDir\create-jules-session.ps1" -IssueNumber $implNumber -Repository $resolvedRepository -AutoCreatePr:([bool]$AutoCreatePr) -ApiKey $ApiKey
            $sessionId = [string]$sessionResult.SessionId
            if ([string]::IsNullOrWhiteSpace($sessionId)) {
                throw "Konnte keine Jules Session-ID fuer Issue #$implNumber ermitteln."
            }

            if ([bool]$AutoCreatePr -and [string]$sessionResult.AutomationMode -ne "AUTO_CREATE_PR") {
                Update-ImplementationFields -Repository $resolvedRepository -IssueNumber $implNumber -Status "Blocked" -SessionId $sessionId -RemoteState "jules_created" -WorkBranch "main" -LastUpdate (Get-Date -Format "yyyy-MM-dd")
                throw ("Jules Session fuer Issue #{0} wurde ohne bestaetigtes AUTO_CREATE_PR erstellt." -f $implNumber)
            }

            Update-ImplementationFields -Repository $resolvedRepository -IssueNumber $implNumber -Status "In Progress" -SessionId $sessionId -RemoteState "queued" -WorkBranch "main" -LastUpdate (Get-Date -Format "yyyy-MM-dd")
            $session = Get-JulesSession -SessionIdOrName $sessionId -ApiKey $ApiKey
            Sync-TrackingAndMirrorFields -Repository $resolvedRepository -IssueNumber $implNumber -Session $session -StartingBranch "main"
        }

        $session = Wait-ForJulesState -SessionId $sessionId -InitialWaitMinutes $InitialWaitMinutes -PollMinutes $PollMinutes -ApiKey $ApiKey
        Sync-TrackingAndMirrorFields -Repository $resolvedRepository -IssueNumber $implNumber -Session $session -StartingBranch "main"

        $pullRequestUrl = Get-JulesSessionPullRequestUrl -Session $session
        if ([string]::IsNullOrWhiteSpace([string]$pullRequestUrl)) {
            $pullRequestUrl = Resolve-PullRequestUrlForIssue -Repository $resolvedRepository -IssueNumber $implNumber -SessionId $sessionId
        }

        if ([string]::IsNullOrWhiteSpace([string]$pullRequestUrl)) {
            throw "Jules Session $sessionId ist abgeschlossen, liefert aber keinen PR-Link und es wurde auch kein existierender PR fuer Issue #$implNumber gefunden."
        }

        $mergedPr = Wait-ForPullRequestMerge -Repository $resolvedRepository -PullRequestUrl ([string]$pullRequestUrl) -PollMinutes $PollMinutes
        Sync-TrackingAndMirrorFields -Repository $resolvedRepository -IssueNumber $implNumber -Session $session -StartingBranch ([string]$mergedPr.headRefName)
        Update-ImplementationFields -Repository $resolvedRepository -IssueNumber $implNumber -Status "Done" -SessionId $sessionId -RemoteState "merged" -WorkBranch ([string]$mergedPr.headRefName) -LastUpdate ([string]$mergedPr.mergedAt)
        gh issue comment $implNumber --repo $resolvedRepository --body ("Implementation merged in PR #{0}." -f $mergedPr.number) | Out-Null
    }

    $implSnapshot = Get-IssueSnapshot -Repository $resolvedRepository -IssueNumber $implNumber
    if (-not (Test-ImplementationComplete -Snapshot $implSnapshot)) {
        throw ("Implementation fuer Paar {0}:{1} ist noch nicht abgeschlossen." -f $implNumber, $verifyNumber)
    }

    if (Test-VerificationPassed -Snapshot $verifySnapshot) {
        Write-Step ("Verify-Issue #{0} ist bereits PASS." -f $verifyNumber)
        continue
    }

    $geminiResult = Invoke-GeminiVerification -WorktreePath $geminiWorktree -ImplementationIssueNumber $implNumber -VerifyIssueNumber $verifyNumber -PromptTemplate $GeminiPromptTemplate
    Write-Host $geminiResult

    $verifySnapshot = Wait-ForVerificationFinalization -Repository $resolvedRepository -IssueNumber $verifyNumber
    if (Test-VerificationPassed -Snapshot $verifySnapshot) {
        continue
    }

    if (Test-VerificationRejected -Snapshot $verifySnapshot) {
        throw ("Gemini verification fuer Paar {0}:{1} hat REJECT geliefert." -f $implNumber, $verifyNumber)
    }

    throw ("Gemini hat Verify-Issue {0} nicht korrekt auf einen finalen Zustand gebracht." -f $verifyNumber)
}
