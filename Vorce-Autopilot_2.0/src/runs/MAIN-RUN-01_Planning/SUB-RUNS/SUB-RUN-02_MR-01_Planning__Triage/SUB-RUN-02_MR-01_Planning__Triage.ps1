# src/runs/SUB-RUN/SUB-RUN-02_MR-01_Planning__Triage.ps1
param($MainState, $SubState, $GlobalState, $Config, $QuotaRegistry, $DryRun)

Write-Host "`n[SUB-RUN] SR-02 Triage: Pruefe Eskalationen und Konflikte..." -ForegroundColor Cyan

$repo = $Config.repository

# --- Step 1: Process escalated issues (CEO Re-Planning) ---
$escalated = @($GlobalState.escalated_issues | Where-Object { $_.status -eq "NEEDS_PLANNING" })
if ($escalated.Count -gt 0) {
    Write-Host "[PLANNING] Gefunden: $($escalated.Count) eskalierte Issues zur Re-Planung." -ForegroundColor Yellow
    foreach ($escIssue in $escalated) {
        $issueNum = [int]$escIssue.issue_number
        $issueTitle = [string]$escIssue.issue_title
        $lastSessionId = [string]$escIssue.last_jules_session_id

        Write-Host "[PLANNING] Re-Planning fuer eskaliertes Issue #$issueNum ($issueTitle) via CEO + QA Manager Deliberation..." -ForegroundColor Yellow

        $promptText = @"
Das Issue #$issueNum ("$issueTitle") wurde an Jules delegiert (letzte Session: $lastSessionId), ist aber im Check&Doing-Modus fehlgeschlagen oder hängengeblieben (Timeout/Fehler).

Erstelle jetzt eine neue, präzisere Handlungsanweisung (Prompt-Ergänzung oder überarbeitete Issue-Beschreibung), um Jules beim nächsten Versuch erfolgreich zu leiten.
Antworte mit einem konkreten, korrigierten Handlungsplan für Jules.
"@

        # Hierarchische Deliberation via PART-RUNS
        Write-Host "[PLANNING] Starte hierarchische Deliberation..." -ForegroundColor Gray

        # 1. Proposal (CEO)
        $proposalPartName = "PART-RUN-01_SR-02_MR-01_Planning__ReplanProposal"
        $proposalResult = Invoke-PartRun `
            -PartRunName $proposalPartName `
            -AgentType "CEO" `
            -Prompt $promptText `
            -SubState $SubState `
            -Config $Config `
            -QuotaRegistry $QuotaRegistry `
            -DryRun:$DryRun

        if ($proposalResult.success) {
            $ceoProposal = $proposalResult.output

            # 2. Critique (QA-Manager)
            $critiquePrompt = "Analysiere den folgenden Vorschlag des CEO für Issue #$issueNum und gib konstruktive Kritik:`n`n$ceoProposal"
            $critiquePartName = "PART-RUN-02_SR-02_MR-01_Planning__ReplanCritique"
            $critiqueResult = Invoke-PartRun `
                -PartRunName $critiquePartName `
                -AgentType "QA-Manager" `
                -Prompt $critiquePrompt `
                -SubState $SubState `
                -Config $Config `
                -QuotaRegistry $QuotaRegistry `
                -DryRun:$DryRun

            $finalPlan = $ceoProposal
            if ($critiqueResult.success) {
                $qaCritique = $critiqueResult.output
                # 3. Synthesis (CEO)
                $synthesisPrompt = "Berücksichtige die Kritik des QA-Managers und finalisiere den Plan für Issue #$($issueNum):`n`nKRITIK:`n$qaCritique`n`nVORSCHLAG:`n$ceoProposal"
                $synthesisPartName = "PART-RUN-03_SR-02_MR-01_Planning__ReplanSynthesis"
                $synthesisResult = Invoke-PartRun `
                    -PartRunName $synthesisPartName `
                    -AgentType "CEO" `
                    -Prompt $synthesisPrompt `
                    -SubState $SubState `
                    -Config $Config `
                    -QuotaRegistry $QuotaRegistry `
                    -DryRun:$DryRun

                if ($synthesisResult.success) {
                    $finalPlan = $synthesisResult.output
                }
            }

            $ceoPlan = $finalPlan
            Write-Host "[PLANNING] Re-Planning erfolgreich für #$issueNum." -ForegroundColor Green

            if (-not $DryRun.IsPresent) {
                $commentBody = "CEO Re-Planning Handlungsplan (V2.0 Hierarchie) für den nächsten Versuch:`n`n$ceoPlan"
                $null = New-GitHubIssueComment -Repository $repo -IssueNumber $issueNum -Body $commentBody
                Write-Host "[PLANNING] CEO-Plan auf GitHub-Issue #$issueNum gepostet." -ForegroundColor Green

                $escIssue.planning_resolutions = [int]$escIssue.planning_resolutions + 1
                $escIssue.status = "RESOLVED_BY_PLANNING"
                Save-AutopilotState -State $GlobalState
            }
        } else {
            Write-Host "[PLANNING] Re-Planning fuer #$issueNum fehlgeschlagen: Success=$($proposalResult.success), Provider=$($proposalResult.provider), Error=$($proposalResult.error)" -ForegroundColor Red
        }
    }
}

# --- Step 2: Check for PR Conflicts ---
Write-Host "[PLANNING] Pruefe auf ungeloeste PR Merge-Konflikte..." -ForegroundColor Cyan
try {
    $prs = Get-GitHubPullRequests -Repository $repo -Limit 100
    $conflictingPrs = @($prs | Where-Object { $_.mergeable -eq "CONFLICTING" })

    if ($conflictingPrs.Count -gt 0) {
        # Check if a conflict-resolution issue was already created in the last 24 hours
        $recentConflictIssue = $false
        if ($null -ne $GlobalState.autopilot_created_issues) {
            foreach ($entry in $GlobalState.autopilot_created_issues) {
                $isConflictTag = $false
                if ((Test-ObjectProperty -Object $entry -Name "tag") -and [string]$entry.tag -match "^resolve-conflicts-") {
                    $isConflictTag = $true
                }
                if ($isConflictTag -and (Test-ObjectProperty -Object $entry -Name "created_at")) {
                    try {
                        $createdAt = [datetimeoffset]::Parse([string]$entry.created_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        $ageHours = ((Get-Date) - $createdAt.LocalDateTime).TotalHours
                        if ($ageHours -lt 24) {
                            $recentConflictIssue = $true
                            Write-Host "[PLANNING]   Merge-Konflikt-Issue wurde vor $([Math]::Round($ageHours,1))h erstellt (Issue #$($entry.issue_number)). Ueberspringe Neuerstellung." -ForegroundColor DarkGray
                            break
                        }
                    } catch {}
                }
            }
        }

        if (-not $recentConflictIssue) {
            $prNumbers = @($conflictingPrs | Sort-Object number | ForEach-Object { $_.number }) -join "-"
            $conflictTag = "resolve-conflicts-$prNumbers"
            Write-Host "[PLANNING]   Erstelle gebuendeltes Konflikt-Issue fuer $($conflictingPrs.Count) Konflikte" -ForegroundColor Yellow

            if (-not $DryRun.IsPresent) {
                $allIssuesForNaming = Get-AllGitHubIssues -Repository $repo -Limit 1000
                $nextIssueId = Get-NextVorceIssueId -Issues $allIssuesForNaming
                $issueTitle = Format-VorceIssueTitle -Type "default" -Id $nextIssueId -Title "Resolve-Merge-Conflicts-PRs-$prNumbers"
                $issueBody = "## Ziel`n"
                $issueBody += "Loese die Merge-Konflikte der unten gelisteten bestehenden PR-Branches gegen ihre jeweilige Base-Branch. Dieses Issue ist ein lokaler CLI-Agent-Auftrag und darf niemals an Jules delegiert werden.`n`n"
                $issueBody += "## Betroffene PRs`n"
                foreach ($cpr in $conflictingPrs) {
                    $baseRef = if (Test-ObjectProperty -Object $cpr -Name "baseRefName") { [string]$cpr.baseRefName } else { "main" }
                    $headRef = if (Test-ObjectProperty -Object $cpr -Name "headRefName") { [string]$cpr.headRefName } else { "" }
                    $issueBody += ('- PR #{0}: ``{1}`` -> ``{2}`` - {3}' -f $cpr.number, $headRef, $baseRef, $cpr.title) + "`n"
                }
                $issueBody += @"

## Arbeitsanweisung fuer den lokalen Agenten
- Jeden PR einzeln pruefen: `gh pr view <nr> --json state,mergeable,headRefName,baseRefName,title,files`.
- Geschlossene oder nicht mehr konfliktierende PRs ueberspringen und im Abschlussbericht nennen.
- Fuer konfliktierende PRs: Head-Branch auschecken, Base-Branch mergen, Konfliktdateien mit `git diff --name-only --diff-filter=U` ermitteln, Konflikte minimal und fachlich passend aufloesen, Tests/Checks soweit sinnvoll ausfuehren, Commit auf denselben Head-Branch pushen.
- Keinen neuen PR erstellen und keinen leeren Commit erzeugen.
- Wenn ein PR inhaltlich nicht mehr rettbar ist, keine Jules-Session starten. Stattdessen im Abschlussbericht exakt PR, Branches, Konfliktdateien und Grund nennen.

## Akzeptanz
- Jeder noch offene konfliktierende PR aus der Liste ist entweder konfliktfrei gepusht oder konkret als nicht rettbar dokumentiert.
- Der Bericht nennt fuer jeden PR: Status, Branch, geaenderte Dateien, ausgefuehrte Checks.
- Es wurden keine Jules-Sessions und keine Tracking-PRs erzeugt.

Prioritaet: KRITISCH - blockiert Release-Pipeline.
"@

                # EXKLUSIV fuer gemini_cli
                $targetAgent = "gemini_cli"
                $newIssueUrl = New-GitHubIssue -Repository $repo -Title $issueTitle -Body $issueBody -Labels @("priority: critical", "bug", "agent:$targetAgent")
                if ($newIssueUrl -match "/issues/(\d+)") {
                    $newIssueNum = [int]$Matches[1]
                    Write-Host "[PLANNING]   -> Konflikt-Issue #$newIssueNum erfolgreich erstellt! Zuweisung an $targetAgent." -ForegroundColor Green

                    if ($null -eq $GlobalState.autopilot_created_issues) { $GlobalState.autopilot_created_issues = @() }
                    $GlobalState.autopilot_created_issues += [ordered]@{ tag = $conflictTag; issue_number = $newIssueNum; created_at = (Get-Date -Format 'o') }

                    Add-WorkingQueueItem -State $GlobalState -IssueNumber $newIssueNum -IssueTitle $issueTitle -AgentProvider $targetAgent
                    Save-AutopilotState -State $GlobalState
                }
            }
        }
    }
} catch {
    Write-Warning "[PLANNING] PR-Konflikt-Check fehlgeschlagen: $_"
}

$SubState.status = "completed"
