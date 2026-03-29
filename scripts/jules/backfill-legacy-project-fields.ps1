[CmdletBinding()]
param(
    [int[]]$IssueNumber,
    [string]$Repository = "Vorce-Studios/Vorce",
    [string]$LegacyRepository = "MrLongNight/MapFlow",
    [int]$IssueLimit = 200,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-github.ps1")

function Write-JulesWarn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning $Message
}

function BodyText {
    param([AllowNull()][string]$Body)
    if ($null -eq $Body) { return "" }
    return ([string]$Body).TrimStart([char]0xFEFF)
}

function CleanVal {
    param([AllowNull()][string]$Value, [int]$MaxLength = 220)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Replace("`r", "").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -match '^`(?<code>.+)`$') { $text = $Matches["code"].Trim() }
    if ($text -match '^\[(?<label>[^\]]+)\]\((?<url>https?://[^)]+)\)$') { $text = $Matches["url"].Trim() }
    if ($text -in @("_No response_", "_n/a_", "n/a", "N/A", "none", "None", "null", "Null")) { return $null }
    return Normalize-TrackingText -Value $text -MaxLength $MaxLength
}

function HeadingText {
    param([string]$Body, [string[]]$Names)
    $text = BodyText -Body $Body
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    foreach ($name in $Names) {
        $pattern = "(?ims)^#{2,3}\s+$([regex]::Escape($name))\s*$\s*(?<value>.*?)(?=^#{2,3}\s+|\z)"
        $match = [regex]::Match($text, $pattern)
        if ($match.Success) { return $match.Groups["value"].Value.Trim() }
    }
    return $null
}

function ProjectFieldVal {
    param([string]$Body, [string]$Field)
    $block = HeadingText -Body $Body -Names @("Vorce Project Manager")
    if ([string]::IsNullOrWhiteSpace($block)) { return $null }
    $pattern = "(?ims)^###\s+$([regex]::Escape($Field))\s*$\s*(?<value>.*?)(?=^###\s+|\z)"
    $match = [regex]::Match($block, $pattern)
    if (-not $match.Success) { return $null }
    return CleanVal -Value $match.Groups["value"].Value
}

function SectionSummary {
    param([string]$Body, [string[]]$Names, [int]$MaxLength = 220)
    $block = HeadingText -Body $Body -Names $Names
    if ([string]::IsNullOrWhiteSpace($block)) { return $null }
    $lines = @(
        $block -split "`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notin @('---', '```', '```shell') }
    )
    if ($lines.Count -eq 0) { return $null }
    $picked = @()
    foreach ($line in $lines) {
        if ($line -match '^(?:[-*]|\d+\.)\s+') { continue }
        $picked += $line
        if (($picked -join " ").Length -ge $MaxLength) { break }
    }
    if ($picked.Count -eq 0) { $picked = @($lines[0]) }
    return CleanVal -Value ($picked -join " ") -MaxLength $MaxLength
}

function BulletVal {
    param([string]$Body, [string[]]$Labels, [string[]]$Sections, [int]$MaxLength = 180)
    $scope = if ($Sections -and $Sections.Count -gt 0) { HeadingText -Body $Body -Names $Sections } else { BodyText -Body $Body }
    if ([string]::IsNullOrWhiteSpace($scope)) { return $null }
    foreach ($label in $Labels) {
        $pattern = "(?im)^[\-\*]\s+$([regex]::Escape($label))\s*:\s*(?<value>.+?)\s*$"
        $match = [regex]::Match($scope, $pattern)
        if ($match.Success) { return CleanVal -Value $match.Groups["value"].Value -MaxLength $MaxLength }
    }
    return $null
}

function CommentVal {
    param([string]$Body, [string[]]$Names, [int]$MaxLength = 180)
    $text = BodyText -Body $Body
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    foreach ($name in $Names) {
        $pattern = "<!--\s*$([regex]::Escape($name)):\s*(?<value>.*?)\s*-->"
        $match = [regex]::Match($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) { return CleanVal -Value $match.Groups["value"].Value -MaxLength $MaxLength }
    }
    return $null
}

function FirstFromBodies {
    param([string[]]$Bodies, [scriptblock]$Getter)
    foreach ($body in $Bodies) {
        if ([string]::IsNullOrWhiteSpace($body)) { continue }
        $value = & $Getter $body
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $null
}

function LegacyNumber {
    param([string]$Body)
    $match = [regex]::Match((BodyText -Body $Body), 'Migrated from legacy issue MrLongNight/MapFlow#(?<number>\d+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups["number"].Value
}

function TitleTaskId {
    param([string]$Title)
    $text = CleanVal -Value $Title -MaxLength 140
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    if ($text -match '^MFuser_#\d+-(?<id>.+)$') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    if ($text -match '^(?<id>[^:]+):') { return CleanVal -Value $Matches["id"] -MaxLength 140 }
    return $text
}

function ResolveTaskType {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels, [string]$Title, [string]$Body)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^Verification$' { return "Test" }
            '^Implementation$' { return "Feature" }
            '^(Bug|Feature|Fix|Polish|Refactor|Test)$' { return $candidate }
        }
    }
    $joinedLabels = (($Labels | ForEach-Object { [string]$_ }) -join " ").ToLowerInvariant()
    $titleText = ([string]$Title).ToLowerInvariant()
    $bodyText = (BodyText -Body $Body).ToLowerInvariant()
    if ($joinedLabels.Contains("bug") -or $titleText.Contains("[bug]") -or $bodyText.Contains("bug description")) { return "Bug" }
    if ($joinedLabels.Contains("refactoring")) { return "Refactor" }
    if ($joinedLabels.Contains("testing") -or $titleText.Contains("verify") -or $titleText.Contains("verification") -or $titleText.Contains("test") -or $titleText.Contains("qa")) { return "Test" }
    if ($joinedLabels.Contains("documentation")) { return "Polish" }
    if ($joinedLabels.Contains("feature-request") -or $joinedLabels.Contains("enhancement")) { return "Feature" }
    return $null
}

function ResolvePriority {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^(A|Critical|High)$' { return "A" }
            '^(B|Medium)$' { return "B" }
            '^(C|Low)$' { return "C" }
        }
    }
    foreach ($label in $Labels) {
        switch ([string]$label) {
            "priority: critical" { return "A" }
            "priority: high" { return "A" }
            "priority: medium" { return "B" }
            "priority: low" { return "C" }
        }
    }
    return $null
}

function ResolveAgent {
    param([AllowNull()][string]$ExplicitValue, [string[]]$Labels, [AllowNull()][string]$SessionId, [string]$Body, [string]$Title)
    $candidate = CleanVal -Value $ExplicitValue -MaxLength 40
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        switch -Regex ($candidate) {
            '^(Jules|AgentJules)$' { return "AgentJules" }
            '^(Gemini CLI|Codex / Gemini CLI)$' { return "Gemini CLI" }
            '^(Codex CLI|Codex)$' { return "Codex CLI" }
            '^Codex Web$' { return "Codex Web" }
            '^Maestro$' { return "Maestro" }
        }
    }
    if ($Labels -contains "jules-task") { return "AgentJules" }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) { return "AgentJules" }
    $text = ("{0} {1}" -f $Title, (BodyText -Body $Body)).ToLowerInvariant()
    if ($text.Contains("gemini cli")) { return "Gemini CLI" }
    return $null
}

function SessionIdVal {
    param([string]$Body)
    $value = CommentVal -Body $Body -Names @("jules-session-id") -MaxLength 80
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    return BulletVal -Body $Body -Labels @("Jules Session ID") -Sections @("Jules Automation", "Roadmap Task") -MaxLength 80
}

function Set-ProjectFieldByName {
    param([object]$Context, [string]$ItemId, [string]$FieldName, [AllowNull()][string]$Value)
    $field = Get-VorceProjectField -Context $Context -FieldName $FieldName
    if ($null -eq $field) { return }
    Set-VorceProjectFieldValue -Context $Context -ItemId $ItemId -Field $field -Value $Value
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$projectContext = Get-VorceProjectContext -Repository $resolvedRepository
if ($null -eq $projectContext) {
    throw "GitHub Project fuer '$resolvedRepository' konnte nicht ermittelt werden."
}

$issues = @(
    if ($IssueNumber) {
        $IssueNumber | ForEach-Object { Get-GitHubIssue -Repository $resolvedRepository -IssueNumber $_ }
    } else {
        Get-GitHubIssues -Repository $resolvedRepository -State "all" -Limit $IssueLimit
    }
)

$legacyNumbers = @(
    $issues |
        ForEach-Object {
            $number = LegacyNumber -Body ([string]$_.body)
            if ($null -ne $number) { $number }
        } |
        Sort-Object -Unique
)

$legacyMap = @{}
if ($legacyNumbers.Count -gt 0) {
    foreach ($legacyIssue in @(Get-GitHubIssues -Repository $LegacyRepository -State "all" -Limit 500)) {
        $legacyMap[[int]$legacyIssue.number] = $legacyIssue
    }
}

$results = foreach ($issue in @($issues | Sort-Object number)) {
    $number = [int]$issue.number
    $body = BodyText -Body ([string]$issue.body)
    $title = [string]$issue.title
    $labels = @(
        Get-GitHubIssueLabelNames -Issue $issue |
            ForEach-Object { [string]$_ }
    )

    $legacyNumber = LegacyNumber -Body $body
    $legacyBody = if ($null -ne $legacyNumber -and $legacyMap.ContainsKey($legacyNumber)) {
        BodyText -Body ([string]$legacyMap[$legacyNumber].body)
    } else {
        ""
    }
    $bodies = @($body, $legacyBody)

    $status = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "Status" }
    if ([string]::IsNullOrWhiteSpace($status) -and [string]$issue.state -eq "CLOSED") { $status = "Done" }

    $taskId = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "task_id" }
    if ([string]::IsNullOrWhiteSpace($taskId)) {
        $taskId = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("MF-ID") -Sections @("Roadmap Task", "Roadmap Source") -MaxLength 140 }
    }
    if ([string]::IsNullOrWhiteSpace($taskId)) { $taskId = TitleTaskId -Title $title }

    $area = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "area" }
    if ([string]::IsNullOrWhiteSpace($area)) {
        $area = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Bereich", "Area") -Sections @("Roadmap Task") -MaxLength 180 }
    }
    if ([string]::IsNullOrWhiteSpace($area)) {
        $area = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Project Phase", "Projektphase") -MaxLength 120 }
    }

    $taskTypeSource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "task_type" }
    if ([string]::IsNullOrWhiteSpace($taskTypeSource)) {
        $taskTypeSource = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Typ", "Type") -Sections @("Roadmap Task") -MaxLength 40 }
    }
    $taskType = ResolveTaskType -ExplicitValue $taskTypeSource -Labels $labels -Title $title -Body $body

    $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "priority" }
    if ([string]::IsNullOrWhiteSpace($prioritySource)) {
        $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Prioritaet", "Priority") -Sections @("Roadmap Task") -MaxLength 40 }
    }
    if ([string]::IsNullOrWhiteSpace($prioritySource)) {
        $prioritySource = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Priority", "Severity") -MaxLength 60 }
    }
    $priority = ResolvePriority -ExplicitValue $prioritySource -Labels $labels

    $permitIssue = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "permit_issue" }
    if ($permitIssue -notin @("approved", "rejected", "clarification")) { $permitIssue = $null }

    $sessionId = FirstFromBodies -Bodies $bodies -Getter { param($b) SessionIdVal -Body $b }
    $agentSource = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "agent" }
    $agent = ResolveAgent -ExplicitValue $agentSource -Labels $labels -SessionId $sessionId -Body $body -Title $title

    $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "work_branch" }
    if ([string]::IsNullOrWhiteSpace($workBranch)) {
        $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-work-branch") -MaxLength 180 }
    }
    if ([string]::IsNullOrWhiteSpace($workBranch)) {
        $workBranch = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Work Branch", "Branch", "Start Branch") -Sections @("Vorce Project Manager", "Jules Automation", "Roadmap Task") -MaxLength 180 }
    }

    $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "last_update" }
    if ([string]::IsNullOrWhiteSpace($lastUpdate)) {
        $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) CommentVal -Body $b -Names @("vorce-last-update") -MaxLength 80 }
    }
    if ([string]::IsNullOrWhiteSpace($lastUpdate)) {
        $lastUpdate = FirstFromBodies -Bodies $bodies -Getter { param($b) BulletVal -Body $b -Labels @("Letztes Roadmap-Update", "Aktualisiert", "Last Update") -Sections @("Roadmap Task", "Jules Automation", "Vorce Project Manager") -MaxLength 80 }
    }

    $description = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "description" }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Beschreibung", "Task Description", "Description") -MaxLength 220 }
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Goal", "Ziel") -MaxLength 220 }
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = FirstFromBodies -Bodies $bodies -Getter { param($b) SectionSummary -Body $b -Names @("Problem", "Bug Description", "Scope") -MaxLength 220 }
    }

    $subAgent = FirstFromBodies -Bodies $bodies -Getter { param($b) ProjectFieldVal -Body $b -Field "sub_agent" }

    $issueContentId = Get-GitHubIssueContentId -Repository $resolvedRepository -IssueNumber $number
    $itemId = Ensure-VorceProjectItem -Context $projectContext -IssueContentId $issueContentId

    $updates = [ordered]@{
        "Status"        = $status
        "task_id"       = $taskId
        "area"          = $area
        "task_type"     = $taskType
        "priority"      = $priority
        "permit_issue"  = $permitIssue
        "agent"         = $agent
        "jules_session" = $sessionId
        "work_branch"   = $workBranch
        "last_update"   = $lastUpdate
        "description"   = $description
        "sub_agent"     = $subAgent
    }

    $applied = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $updates.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
        if (-not $DryRun.IsPresent) {
            Set-ProjectFieldByName -Context $projectContext -ItemId $itemId -FieldName ([string]$entry.Key) -Value ([string]$entry.Value)
        }
        $applied.Add(([string]$entry.Key)) | Out-Null
    }

    [pscustomobject]@{
        IssueNumber   = $number
        Title         = $title
        LegacyIssue   = $legacyNumber
        UpdatedFields = @($applied)
    }
}

$results = @($results)
$results
