# SUB-RUN-04_ReviewDispatch.ps1 (Vorce 3.0)
# Findet PRs mit Status "ready for review" und dispatcht an Code-Review Agents
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
. (Join-Path $global:LibDir "integrations/ApiClient.ps1")

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/DeliberationEngine.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

Write-VorceStep -Message "Starte ReviewDispatch..." -Status "RUN"

# 1. Finde PRs mit Status "ready for review"
$repo = $ConfigBag.Config.repository
$reviewDir = Join-Path $global:VarDir "db/reviews"
if (-not (Test-Path $reviewDir)) {
    New-Item -ItemType Directory -Path $reviewDir -Force | Out-Null
}

if ($ConfigBag.DryRun) {
    Write-VorceStep -Message "DryRun: GitHub-Abfrage und Review-Dispatch werden nicht ausgeführt." -Status "INFO"
    return @{ status="dry_run"; prs_found=0; reviews_dispatched=0; timestamp=(Get-Date).ToString("o") }
}

try {
    # GitHub API Aufruf für PRs mit Status "ready_for_review"
    $prResponse = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$repo/pulls?state=open&sort=created&direction=asc" -Method GET

    $prData = $prResponse | Where-Object { $_.draft -ne $true -and $_.labels.name -notcontains "no-review" } |
               Where-Object { $_.review_requests.requested_reviewers.login -contains "claude" -or $_.review_requests.requested_reviewers.login -contains "gemini" } |
               Where-Object { $_.commits -lt 20 }  # Nur PRs mit weniger als 20 Commits

    if (-not $prData) {
        Write-VorceStep -Message "Keine PRs im Review-Status gefunden." -Status "INFO"
        return @{ status="no_prs_for_review"; prs_found=0; reviews_dispatched=0; timestamp=(Get-Date).ToString("o") }
    }

    Write-VorceStep -Message "Gefunden $($prData.Count) PRs für Review" -Status "INFO"

} catch {
    Write-VorceStep -Message "Fehler beim Abrufen von PRs: $($_.Exception.Message)" -Status "ERROR"
    return @{ status="error"; error=$_.Exception.Message; prs_found=0; reviews_dispatched=0; timestamp=(Get-Date).ToString("o") }
}

$reviewsDispatched = 0

# 2. Für jeden PR: Dispatche an Gemini/Claude für Code-Review
foreach ($pr in $prData) {
    Write-VorceStep -Message "Dispatche Review für PR #$($pr.number): $($pr.title)" -Status "RUN"

    try {
        # Prüfe Quota für Code-Review Agent
        $agentName = if ($pr.labels.name -contains "ai-review-gemini") { "gemini" } else { "claude" }

        $quotaOK = Test-VorceQuota -AgentName $agentName
        if (-not $quotaOK) {
            Write-VorceStep -Message "Quota für $agentName erschöpft, überspringe PR" -Status "WARN"
            continue
        }

        # Erstelle Review-Ergebnis Datei
        $reviewFile = Join-Path $reviewDir "review_$($pr.number)_$((Get-Date).ToString('yyyyMMdd_HHmmss')).json"

        $reviewRequest = @{
            pr_number = $pr.number
            pr_title = $pr.title
            pr_url = $pr.html_url
            requested_agent = $agentName
            created_at = $pr.created_at
            head_branch = $pr.head.ref
            base_branch = $pr.base.ref
            diff_url = $pr.diff_url
            files_changed = $pr.changed_files
            additions = $pr.additions
            deletions = $pr.deletions
            commit_count = $pr.commits
        }

        # Speichere Review Request
        $reviewRequest | ConvertTo-Json -Depth 10 | Set-Content $reviewFile -Encoding UTF8

        # Aktualisiere ParentState mit Review-Informationen
        if (-not $ParentState.reviews) {
            $ParentState | Add-Member -MemberType NoteProperty -Name "reviews" -Value @() -Force
        }
        $ParentState.reviews += $reviewRequest

        $reviewsDispatched++

        Write-VorceStep -Message "Review für PR #$($pr.number) an $agentName dispatched" -Status "OK"

    } catch {
        Write-VorceStep -Message "Fehler bei Review Dispatch für #$($pr.number): $($_.Exception.Message)" -Status "ERROR"
    }
}

# 3. Speichere Dispatch-Statistik
$reviewDispatchResult = @{
    status = "completed"
    prs_found = $prData.Count
    reviews_dispatched = $reviewsDispatched
    quota_available_for_claude = (Test-VorceQuota -AgentName "claude")
    quota_available_for_gemini = (Test-VorceQuota -AgentName "gemini")
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "ReviewDispatch abgeschlossen: $reviewsDispatched von $($prData.Count) Reviews dispatched." -Status "OK"
return $reviewDispatchResult
