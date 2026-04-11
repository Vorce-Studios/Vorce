[CmdletBinding()]
param(
    [string]$Repository,
    [string]$ApiKey,
    [string]$LogFile = ".Jules/session-monitor-log.md",
    [int]$Interval1MaxHours = 6,
    [int]$Interval2MaxHours = 24,
    [int]$Interval3MaxHours = 48,
    [string]$EscalationUser = "@MrLongNight",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir "jules-api.ps1")
. (Join-Path $ScriptDir "jules-github.ps1")

# Ensure UTF-8 for Markdown
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-CurrentLogState {
    param([string]$Path)
    $state = @{}
    if (Test-Path $Path) {
        $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        # Parse: | Session ID | Intervall | Status |
        # Parse: | 11217710755568478899 | 1/3 | ... |
        $matches = [regex]::Matches($content, '\| (?<id>\d+) \| (?<interval>\d)/3 \|')
        foreach ($m in $matches) {
            $state[$m.Groups["id"].Value] = [int]$m.Groups["interval"].Value
        }
    }
    return $state
}

function Update-LogFile {
    param([string]$Path, [hashtable]$ActiveSessions, [hashtable]$History)

    $date = Get-Date -Format "yyyy-MM-dd"
    $lines = @(
        "# Session Monitor Log (Ben)",
        "",
        "## $date - Automated Session Monitoring Run",
        "",
        "### Aktive hängende Sessions:",
        "| Session ID | State | Titel | Aktion |",
        "|---|---|---|---| "
    )

    foreach ($id in ($ActiveSessions.Keys | Sort-Object)) {
        $session = $ActiveSessions[$id]
        $action = if ($History.ContainsKey($id)) { "Eskalation Stufe $($History[$id])" } else { "Neu erfasst" }
        $lines += "| $id | $($session.State) | $($session.Title) | $action |"
    }

    $lines += ""
    $lines += "### Eskalations-Tracker:"
    $lines += "| Session ID | Intervall | Status |"
    $lines += "|---|---|---|"

    foreach ($id in ($History.Keys | Sort-Object)) {
        $interval = $History[$id]
        $status = if ($ActiveSessions.ContainsKey($id)) { "AWAITING_USER_FEEDBACK" } else { "RESOLVED/OTHER" }
        $icon = if ($ActiveSessions.ContainsKey($id)) { "⚠️" } else { "✅" }
        $lines += "| $id | $interval/3 | $icon Intervall $interval`: $status |"
    }

    $content = $lines -join "`n"
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($Path, $content, $utf8NoBom)
        Write-JulesInfo "Log-Datei aktualisiert: $Path"
    } else {
        Write-Host "DRY-RUN: Log-Datei würde aktualisiert werden:`n$content"
    }
}

$resolvedRepository = Resolve-GitHubRepository -Repository $Repository
$sessionApiKey = Get-JulesApiKey -ApiKey $ApiKey

Write-JulesInfo "Starte Ben's Eskalations-Logik..."
$allSessions = Get-AllJulesSessions -ApiKey $sessionApiKey
$stuckSessions = @{}
foreach ($s in $allSessions) {
    if ([string]$s.state -eq "AWAITING_USER_FEEDBACK") {
        $id = Resolve-JulesSessionId -SessionIdOrName ([string]$s.name)
        $stuckSessions[$id] = @{
            Session = $s
            State   = "AWAITING_USER_FEEDBACK"
            Title   = [string]$s.title
        }
    }
}

$history = Get-CurrentLogState -Path $LogFile
$newHistory = $history.Clone()

foreach ($id in $stuckSessions.Keys) {
    $sessionData = $stuckSessions[$id]
    $session = $sessionData.Session
    $currentInterval = if ($history.ContainsKey($id)) { $history[$id] } else { 0 }
    $nextInterval = $currentInterval + 1

    Write-JulesInfo "Session $id ist hängend (Stufe $currentInterval -> $nextInterval)."

    if ($nextInterval -le 2) {
        # Intervall 1 & 2: Continue with task
        Write-JulesInfo "Sende 'Continue with the task.' an Session $id..."
        if (-not $DryRun) {
            Send-JulesMessage -SessionIdOrName $id -Message "Continue with the task." -ApiKey $sessionApiKey
        }
        $newHistory[$id] = $nextInterval
    }
    elseif ($nextInterval -eq 3) {
        # Intervall 3: Eskalation
        Write-JulesInfo "Eskalation Stufe 3 für Session $id..."
        $issueId = Get-IssueNumberFromSession -Session $session
        if ($issueId) {
            $comment = "$EscalationUser Diese Jules-Session hängt seit über 24h in `AWAITING_USER_FEEDBACK`. Bitte prüfen.`n`nSession: $($session.url)"
            Write-JulesInfo "Erstelle GitHub Kommentar für Issue #$issueId..."
            if (-not $DryRun) {
                Add-GitHubIssueComment -Repository $resolvedRepository -IssueNumber $issueId -Body $comment
                Add-GitHubIssueLabels -Repository $resolvedRepository -IssueNumber $issueId -LabelNames @("status: blocked")
            }
        } else {
            Write-JulesWarn "Keine Issue-Nummer für Session $id gefunden. Eskalation nur via Log."
        }
        $newHistory[$id] = $nextInterval
    }
    else {
        # Über Intervall 3 hinaus
        Write-JulesInfo "Session $id bleibt hängend (Stufe $nextInterval). Keine weitere automatische Aktion."
        $newHistory[$id] = $nextInterval
    }
}

# Bereinige History von Sessions, die nicht mehr hängen
foreach ($id in ($history.Keys | Where-Object { -not $stuckSessions.ContainsKey($_) })) {
    Write-JulesInfo "Session $id hängt nicht mehr. Markiere als erledigt im Log."
    # Wir behalten sie im Tracker aber setzen den Intervall auf 0 oder entfernen sie?
    # Im manuellen Log bleiben sie stehen. Wir lassen sie mal drin mit altem Intervall,
    # aber die Update-Log Funktion markiert sie als RESOLVED.
}

Update-LogFile -Path $LogFile -ActiveSessions $stuckSessions -History $newHistory

Write-JulesInfo "Ben's Eskalations-Run abgeschlossen."
