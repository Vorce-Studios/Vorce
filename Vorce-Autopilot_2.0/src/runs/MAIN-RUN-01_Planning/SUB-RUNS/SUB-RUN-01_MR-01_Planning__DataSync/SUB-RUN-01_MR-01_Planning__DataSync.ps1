# src/runs/SUB-RUN/SUB-RUN-01_MR-01_Planning__DataSync.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-01 DataSync: Lade offene Issues..." -ForegroundColor Cyan

$repo = $Config.repository
$issues = @()
try {
    # Use github-client wrapper
    $issues = Get-GitHubIssues -Repository $repo -Limit 50
} catch {
    Write-Warning "Issue-Fetch fehlgeschlagen: $_"
}

# Filter by include labels
$includeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($l in $Config.issue_filters.include_labels) { $includeSet.Add($l) | Out-Null }
$excludeSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($l in $Config.issue_filters.exclude_labels) { $excludeSet.Add($l) | Out-Null }

$candidates = @($issues | Where-Object {
    $labelNames = @($_.labels | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    $hasInclude = @($labelNames | Where-Object { $includeSet.Contains($_) }).Count -gt 0
    $hasExclude = @($labelNames | Where-Object { $excludeSet.Contains($_) }).Count -gt 0
    $title = [string]$_.title
    $body = [string]$_.body
    $isMasterIssue = Test-VorceMasterIssueTitle -Title $title

    $issueNum = [int]$_.number
    $isEscalatedRetry = $false
    if ($null -ne $GlobalState.escalated_issues) {
        $esc = $GlobalState.escalated_issues | Where-Object { [int]$_.issue_number -eq $issueNum }
        if ($esc -and ($esc.status -eq "QUEUED_FOR_RETRY" -or $esc.status -eq "RESOLVED_BY_PLANNING")) {
            $isEscalatedRetry = $true
        }
    }

    $hasExistingJulesSession = ($body -match "<!--\s*jules-session-id:") -or ($body -match "<!--\s*jules-session-name:") -or ($body -match "<!--\s*vorce-queue-state:\s*dispatched")
    $hasInclude -and (-not $hasExclude) -and (-not $isMasterIssue) -and (-not $hasExistingJulesSession -or $isEscalatedRetry)
})

$releaseRank = @{
    "662" = 10
    "655" = 20
    "107" = 30
    "43"  = 40
    "652" = 50
    "653" = 60
}
$candidates = @($candidates | Sort-Object `
    @{ Expression = { $key = [string]$_.number; if ($releaseRank.ContainsKey($key)) { $releaseRank[$key] } else { 999 } } }, `
    @{ Expression = { [int]$_.number } })

# Exclude already delegated issues
$delegatedNumbers = @($GlobalState.active_delegations | ForEach-Object { [int]$_.issue_number })
if ($delegatedNumbers.Count -gt 0) {
    $candidates = @($candidates | Where-Object {
        $val = $_.number
        if ($val -is [System.Collections.IList]) { $val = $val[0] }
        if ($null -eq $val) { $true } else { $delegatedNumbers -notcontains [int]$val }
    })
}

Write-Host "[SUB-RUN] SR-01 DataSync: $($candidates.Count) Issues bereit fuer Delegation." -ForegroundColor Green

# Speichere Kandidaten im MainState fuer die naechsten Sub-Runs
if (-not ($MainState.PSObject.Properties.Name -contains "PlanningCandidates")) {
    $MainState | Add-Member -MemberType NoteProperty -Name "PlanningCandidates" -Value @() -Force
}
$MainState.PlanningCandidates = $candidates

$SubState.status = "completed"
$SubState.artifacts += @{
    type = "DataSyncReport"
    timestamp = (Get-Date).ToString('o')
    candidates_found = $candidates.Count
}
