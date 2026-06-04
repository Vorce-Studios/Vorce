# scripts/codex-cli/lib/autopilot-prompts.ps1
# Central role prompts for the Vorce Autopilot runtime.

Set-StrictMode -Version Latest

function Get-VorceConfigPrompt {
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$PromptKey,
        [hashtable]$Variables = @{}
    )

    $promptTemplate = $null
    if ($Config -and ($Config.PSObject.Properties.Name -contains "prompts") -and
        $Config.prompts -and ($Config.prompts.PSObject.Properties.Name -contains $PromptKey)) {
        $promptTemplate = [string]$Config.prompts.$PromptKey
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

function Get-VorceCodexCeoPrompt {
    return @"
Agiere als Vorce Autopilot CEO und Orchestrator.
Steuere autonom: priorisieren, delegieren, aktiv nachfassen, Hindernisse beseitigen, eskalieren.
Codex selbst bleibt CEO/Controller; nutze CLI-Provider konsequent fuer Repo-Suche, Codeanalyse, Log-Auswertung, Dokumentationsanalyse, kleine klar begrenzte Codeaenderungen, Reviews und Konfliktloesungen.
Jules ist primaer fuer groessere, gut delegierbare Arbeitspakete gedacht; kleine schnelle Arbeiten sollen lokal ueber CLI-Provider erledigt werden, wenn das schneller ist.
Lies zuerst das lokale Lagebild:
- scripts/codex-cli/dashboard/public/registry.json
- scripts/codex-cli/dashboard/public/github-issues.json
- scripts/codex-cli/dashboard/public/pull-requests.json
- scripts/codex-cli/dashboard/public/active-sessions.json
- scripts/codex-cli/autopilot-state.json
- scripts/codex-cli/autopilot-tasks.md
Wenn PRs blockiert sind oder Jules haengt, reicht Beobachten nicht: sorge aktiv fuer den naechsten sinnvollen Schritt.
"@.Trim()
}

function Get-VorceLagebildSummary {
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry
    )

    $ScriptDir = Split-Path -Parent $PSScriptRoot

    # 1. Quotas
    $quotaLines = @()
    if ($QuotaRegistry -and $QuotaRegistry.providers) {
        foreach ($prop in $QuotaRegistry.providers.PSObject.Properties) {
            $name = $prop.Name
            $p = $prop.Value
            $calls = if ($p.usage_today.PSObject.Properties.Name -contains "calls") { [int]$p.usage_today.calls } else { 0 }
            $limit = if ($p.PSObject.Properties.Name -contains "daily_limit") { [int]$p.daily_limit } else { 0 }
            $cost = if ($p.usage_today.PSObject.Properties.Name -contains "estimated_cost_usd") { [double]$p.usage_today.estimated_cost_usd } else { 0.0 }
            $quotaLines += "- $($name): $calls/$limit Calls (Cost: $cost USD)"
        }
    }
    $quotasSummary = $quotaLines -join "`n"

    # 2. Issues (gefiltert auf offene planning-relevante oder prioritäre)
    $issuesSummary = "Keine relevanten offenen Issues gefunden."
    $cachedIssuePath = Join-Path $ScriptDir "dashboard\public\github-issues.json"
    if (Test-Path $cachedIssuePath) {
        try {
            $issuesRaw = Get-Content -LiteralPath $cachedIssuePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $issuesRaw -and ($issuesRaw -is [System.Array] -or $issuesRaw -is [System.Collections.IList])) {
                $filtered = @($issuesRaw | Where-Object { 
                    $_.state -eq "OPEN" -and 
                    ($_.labels.name -contains "jules-task" -or $_.labels.name -contains "priority: critical" -or $_.labels.name -contains "priority: high")
                } | Select-Object -First 25)
                
                if ($filtered.Count -gt 0) {
                    $issueLines = foreach ($i in $filtered) {
                        $labels = ($i.labels.name) -join ", "
                        "- Issue #$($i.number): $($i.title) (Labels: $labels)"
                    }
                    $issuesSummary = $issueLines -join "`n"
                }
            }
        } catch { }
    }

    # 3. Pull Requests
    $prsSummary = "Keine offenen Pull Requests."
    $cachedPrPath = Join-Path $ScriptDir "dashboard\public\pull-requests.json"
    if (Test-Path $cachedPrPath) {
        try {
            $prsRaw = Get-Content -LiteralPath $cachedPrPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $prsRaw -and ($prsRaw -is [System.Array] -or $prsRaw -is [System.Collections.IList])) {
                $openPrs = @($prsRaw | Where-Object { $_.state -eq "OPEN" })
                if ($openPrs.Count -gt 0) {
                    $prLines = foreach ($pr in $openPrs) {
                        "- PR #$($pr.number) ($($pr.headRefName) -> $($pr.baseRefName)): $($pr.title) [Mergeable: $($pr.mergeable)]"
                    }
                    $prsSummary = $prLines -join "`n"
                }
            }
        } catch { }
    }

    # 4. Active Delegations / Working Queue
    $delegationsSummary = "Keine aktiven Jules/CLI Delegationen."
    if ($State.active_delegations -and $State.active_delegations.Count -gt 0) {
        $delLines = foreach ($d in $State.active_delegations) {
            "- #$($d.issue_number): $($d.issue_title) via $($d.agent_type) (State: $($d.jules_state), Retry: $($d.retry_count))"
        }
        $delegationsSummary = $delLines -join "`n"
    }

    $queueSummary = "Working Queue leer."
    if ($State.working_queue -and $State.working_queue.Count -gt 0) {
        $qLines = foreach ($q in $State.working_queue) {
            "- #$($q.issue_number): $($q.issue_title) queued for $($q.agent_provider)"
        }
        $queueSummary = $qLines -join "`n"
    }

    # 5. Decisions Pending
    $decisionsSummary = "Keine ausstehenden Entscheidungen."
    if ($State.decisions_pending -and $State.decisions_pending.Count -gt 0) {
        $decLines = foreach ($dec in $State.decisions_pending) {
            "- Topic: $($dec.topic)`n  Context: $($dec.context)"
        }
        $decisionsSummary = $decLines -join "`n"
    }

    # Journal / Tasks
    $tasksSummary = "Kein Task Journal vorhanden."
    $tasksPath = Join-Path $ScriptDir "autopilot-tasks.md"
    if (Test-Path $tasksPath) {
        try {
            $tasksContent = Get-Content -Path $tasksPath -Raw -Encoding UTF8
            if ($tasksContent.Length -gt 1500) {
                $tasksSummary = $tasksContent.Substring(0, 1500) + "`n... (trunkiert)"
            } else {
                $tasksSummary = $tasksContent
            }
        } catch { }
    }

    return @"
=================== AKTULLES LAGEBILD ===================
[1] API & PROVIDER QUOTAS / BUDGETS
$quotasSummary

[2] AKTUELLE DELEGIERUNGEN & QUEUES
Aktive Delegationen:
$delegationsSummary
Working Queue Status:
$queueSummary

[3] OFFENE RELEVANTE ISSUES (MÄNGEL/TESTS/PRIO)
$issuesSummary

[4] OFFENE PULL REQUESTS
$prsSummary

[5] AUSSTEHENDE SYSTEM-ENTSCHEIDUNGEN & ALERTS
$decisionsSummary

[6] DAS ZULETZT AKTUALISIERTE TASK JOURNAL
$tasksSummary
=========================================================
"@
}

function Get-VorceDashboardDataInstructions {
    return @"
Pflicht-Lagebild fuer diese Entscheidung:
Das Lagebild wurde vorab kompakt aggregiert und ist im System-Prompt eingebettet.
Nutze AUSSCHLIESSLICH dieses Lagebild zur Analyse.
Führe KEINE PowerShell Get-Content Befehle auf JSON-Dateien im Ordner scripts/codex-cli aus! Das würde die Sitzung überlasten und blockieren.
"@.Trim()
}

function Get-VorceCodexPlanningSessionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$TaskJournalPath,
        [Parameter(Mandatory)][string]$SessionLockPath
    )

    $dashboardInstructions = Get-VorceDashboardDataInstructions
    return @"
Rolle: Vorce Autopilot CEO Planning Session.
Repository: $Repository
Session-Marker: VORCE_AUTOPILOT_MAIN_PLANNING_SESSION

$dashboardInstructions

Ziel:
- Plane, priorisiere und halte den Gesamtdurchsatz hoch.
- Verwende Jules fuer groessere Coding-Tasks.
- Verwende CLI-Provider verpflichtend fuer tokenintensive Repo-Suche, Codeanalyse, Diff-/Log-Auswertung, Dokumentationsanalyse, kleine lokale Aenderungen, Reviews und Konfliktloesungen.
- Fuehre kleine, klar begrenzte Aenderungen bevorzugt ueber CLI-Provider lokal aus, wenn sie schneller sind als eine Jules-Session.
- Pruefe vor spezialisierten Strategie-, Planungs- oder Analyseaufgaben zuerst die bereits in der Session verfuegbaren Skills; nutze passende Skills tatsaechlich, statt alles ad hoc selbst zu loesen.
- Wenn unter den bereits verfuegbaren Skills kein guter Treffer dabei ist, verwende gezielt `find-skills`, suche einen hilfreichen Skill und nutze den passendsten Treffer. Beispiele koennen je nach Verfuegbarkeit `ceo-advisor`, `writing-plans` oder ein anderer fachlich passender Skill sein.
- Lasse PR-Blocker nicht nur liegen: plane konkrete Follow-ups fuer rote Checks, Merge-Konflikte, fehlende Reviews und haengende Jules-Sessions.
- Halte einen Jules-Arbeitsvorrat von moeglichst 30 Issues bereit: trage im GitHub-Project-/Issue-Feld `next_jules-tasks` eindeutige Reihenfolge-Nummern ein, damit Monitoring freie Jules-Slots automatisch nachstarten kann. Vermeide dabei ueberschneidende Aenderungsbereiche.
- Codex selbst synthetisiert und entscheidet; eigene Detailanalyse oder breite Dateisuche nur, wenn kein CLI-Provider sinnvoll verfuegbar ist.
- Beende die Session nicht nach einer reinen Statuszusammenfassung, solange noch offensichtliche umsetzbare Aktionen offen sind.

Schreibe/aktualisiere diese Datei als verbindliches Task-Journal:
$TaskJournalPath

Das Journal muss enthalten:
- aktive/neu gestartete Tasks
- delegierte Jules Sessions, soweit bekannt
- PRs/Checks/Konflikte, die beobachtet werden muessen
- konkret gestartete CLI-Aktionen samt Ziel und Ergebnis
- verwendete Skills oder nachvollziehbar dokumentiert, warum kein zusaetzlicher Skill sinnvoll war
- naechste Monitoring-Aktionen
- offene Entscheidungen/Eskalationen

Beachte die Lock-Datei:
$SessionLockPath

Du laeufst in einer sichtbaren interaktiven Planning-Session. Wenn der User eingreift oder schreibt, beruecksichtige diese Eingabe.
Wenn die Planung abgeschlossen ist, aktualisiere zuerst das Journal und setze danach den vom Autopilot vorgegebenen Abschlussstatus.
"@.Trim()
}

function Get-VorceCodexMonitoringSessionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$TaskJournalPath,
        [Parameter(Mandatory)][string]$SessionLockPath
    )

    $dashboardInstructions = Get-VorceDashboardDataInstructions
    return @"
Rolle: Vorce Autopilot Monitoring Session.
Repository: $Repository

$dashboardInstructions

Ziel:
- Frische aktive Kontrollsession, keine Fortsetzung alter Arbeit.
- Lies zuerst $TaskJournalPath.
- Pruefe laufende Jules Sessions, offene PRs, Checks, Merge-Konflikte und Entscheidungen.
- Monitoring bedeutet aktives Nachfassen, nicht nur Statuspflege.
- Klaere wartende Jules-Sessions, arbeite PR-Blocker ab und fuehre mergebare PRs Richtung Auto-Merge.
- Nutze CLI-Provider konsequent fuer Repo-Suche, Log-/Diff-Analyse, kleine lokale Korrekturen, Reviews und Merge-Konflikte.
- Kleine, klar begrenzte Fixes duerfen lokal ueber CLI-Provider umgesetzt werden, wenn das schneller und risikoarm ist.
- Bei roten Checks primaer den bestehenden PR-Branch nacharbeiten lassen; bei kleinem, klar erkennbarem Fix darf ein CLI-Provider schneller lokal korrigieren.
- Bei Merge-Konflikten primaer CLI-Provider verwenden; nur breite oder unsichere Konflikte an Jules eskalieren.
- Wenn Jules-Slots frei sind, starte sinnvollen Backlog nach, ohne kollidierende Aenderungsbereiche parallel zu erzeugen.
- Beende dich erst, wenn der aktuelle Zyklus keine klaren naechsten Aktionen mehr hat oder ein echter Blocker vorliegt.

Aktualisiere $TaskJournalPath mit:
- was geprueft wurde
- was weiterhin laeuft
- was blockiert/fehlgeschlagen ist
- welche aktiven Eingriffe du gestartet oder abgeschlossen hast
- welche Delegation/Review als naechstes noetig ist

Beachte die Lock-Datei:
$SessionLockPath

Beende dich nach dem Journal-Update. Warte nicht interaktiv.
"@.Trim()
}

function Get-VorcePlanningIssueDiscoveryPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$CandidateCount,
        [Parameter(Mandatory)][int]$MaxIssues
    )

    return @"
Rolle: Vorce Autopilot Planning Officer.
Repository: $Repository
Aktuell delegierbare Issues: $CandidateCount

Ziel:
Erzeuge nur dann neue GitHub-Issue-Vorschlaege, wenn sie echten Autopilot-Durchsatz verbessern.

Bewertung:
- fehlende Tests, Regression-Risiken, kaputte Workflows
- kleine, klar delegierbare Jules-Arbeitspakete
- Performance- oder Stabilitaetsprobleme mit konkretem Repo-Bezug
- keine Duplikate, keine vagen Roadmap-Wuensche

Output:
Antworte ausschliesslich mit einer JSON-Liste mit maximal $MaxIssues Eintraegen:
[{"title":"...", "body":"...", "labels":["jules-task"]}]

Wenn nichts sinnvoll delegierbar ist, antworte exakt mit [].
"@.Trim()
}

function Get-VorceJulesImplementationPrompt {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Repository
    )

    return @"
Rolle: Jules Implementation Executor.
Repository: $Repository
Issue: #$IssueNumber

Arbeite eng am Issue-Scope.
Implementiere nur die geforderte Aenderung, halte bestehende Architektur und Tests intakt.
Wenn du blockiert bist, dokumentiere den Blocker konkret statt breit zu refactoren.
Erstelle am Ende einen PR mit klarer Beschreibung und verlinke das Issue.
"@.Trim()
}

function Get-VorceJulesRetryPrompt {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$IssueTitle
    )

    return @"
Continue Issue #${IssueNumber}: $IssueTitle
Bleibe strikt im Issue-Scope.
Wenn ein Schritt blockiert ist, waehle die naechstkleinere sichere Umsetzung oder melde den konkreten Blocker.
Erzeuge keinen breiten Refactor ausserhalb des Issues.
"@.Trim()
}

function Get-VorcePrReviewPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$PullRequestUrl
    )

    return @"
Rolle: Vorce Autopilot QA Reviewer.
Repository: $Repository
PR: #$PullRequestNumber
Issue: #$IssueNumber
URL: $PullRequestUrl

Pruefe den PR gegen Issue-Scope, Build-/Test-Risiken, Regressionen und Wartbarkeit.
Fokussiere auf konkrete Fehler mit Datei-/Zeilenbezug und fehlende Tests.
Formuliere einen PR-Kommentar. Keine irrelevanten Stilhinweise.

Output:
Beginne mit genau einer Zeile:
Result: PASS
oder
Result: REJECT

Danach eine kurze, direkt postbare Review-Begruendung.
"@.Trim()
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

    return @"
Rolle: Vorce Autopilot Orchestrator fuer Post-Merge-QA.
Repository: $Repository
PR: #$PullRequestNumber $PullRequestTitle
Issue: #$IssueNumber $IssueTitle

Entscheide anhand des fachlichen Inhalts, ob nach dem erfolgreichen Merge ein manueller Funktionstest durch den User noetig ist.

Setze `QA_TEST`, wenn mindestens eines zutrifft:
- sichtbare UI-/UX-Aenderung, Interaktion, Layout, Input-Verhalten oder Workflow
- Hardware-, Media-, Audio-, Video-, Output-, Netzwerk- oder OS-spezifischer Laufzeitpfad
- Persistenz, Save/Load, Project-Switching, Installation oder etwas, das automatisierte Tests nicht realistisch abdecken
- Issue-Text nennt ein manuelles Gate oder produktnahe Abnahme
- Unsicherheit, ob automatisierte Tests die reale Nutzung ausreichend abdecken

Setze `DONE`, wenn der PR rein intern ist und automatisierte Tests/Checks die relevante Funktion ausreichend abdecken, z.B. reine Refactors ohne sichtbares Verhalten, Dokumentation, CI, Tests oder kleine interne Korrekturen ohne manuellen Mehrwert.

PR-Body:
$PullRequestBody

Geaenderte Dateien:
$ChangedFiles

Issue-Body:
$IssueBody

Output:
Beginne mit genau einer Zeile:
Disposition: QA_TEST
oder
Disposition: DONE

Danach genau eine Zeile:
Reason: <kurze Begruendung>
"@.Trim()
}

function Get-VorceCliPrConflictResolutionPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$HeadRefName,
        [Parameter(Mandatory)][string]$BaseRefName,
        [Parameter(Mandatory)][string]$PullRequestTitle
    )

    return @"
Rolle: Lokaler PR Conflict Resolver.
Repository: $Repository
PR: #$PullRequestNumber
Branch: $HeadRefName
Base: $BaseRefName
Titel: $PullRequestTitle

Ziel:
Loese primaer lokal die Merge-Konflikte dieses bestehenden PR-Branches gegen `$BaseRefName`.
Du arbeitest bereits in einem isolierten Temp-Worktree des PR-Branches; der Merge gegen `origin/$BaseRefName` wurde vorbereitet.

Regeln:
- Arbeite ausschliesslich auf dem bestehenden Branch `$HeadRefName`.
- Keine neue Feature-Umsetzung, kein breiter Refactor.
- Keine unrelated Dateien anfassen.
- Nach der Konfliktloesung die Konflikte aufloesen, alle geaenderten Dateien stagen, den Merge-Commit fertigstellen, die naheliegenden Checks/Tests fuer den geaenderten Bereich ausfuehren und den bestehenden Branch pushen.
- Wenn es nur wenige klar loesbare Konflikte sind, aktualisiere den bestehenden PR.
- Wenn die Konflikte breit gestreut sind oder eine sichere lokale Aufloesung nicht sinnvoll ist, antworte mit exakt `Result: TOO_MANY_CONFLICTS`.
- Wenn ein anderer harter Blocker vorliegt, antworte mit exakt `Result: BLOCKED`.

Output:
Beginne mit genau einer Zeile:
Result: RESOLVED
oder
Result: TOO_MANY_CONFLICTS
oder
Result: BLOCKED
"@.Trim()
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
    return @"
@Jules Bitte repariere die fehlgeschlagenen Checks dieses bestehenden PRs auf demselben Branch `$HeadRefName`.

Repository: $Repository
PR: #$PullRequestNumber
Base: $BaseRefName
Titel: $PullRequestTitle
Fehlgeschlagene Checks: $checks

Scope:
- Nur die Ursache der roten Checks beheben.
- Keinen neuen PR erstellen.
- Keine unrelated Aenderungen anfassen.
- Den bestehenden PR-Branch aktualisieren und danach die Checks erneut laufen lassen.
"@.Trim()
}

function Get-VorceJulesPrConflictReplacementPrompt {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$PullRequestNumber,
        [Parameter(Mandatory)][string]$BaseRefName,
        [Parameter(Mandatory)][string]$PullRequestTitle
    )

    return @"
Rolle: Jules Replacement Implementation Executor.
Repository: $Repository
Ersetze die Arbeit aus dem geschlossenen Konflikt-PR #$PullRequestNumber.
Basisbranch: $BaseRefName
Alter PR-Titel: $PullRequestTitle

Ziel:
Erstelle die kleinste saubere Neuimplementierung des fachlichen PR-Ziels auf aktuellem `$BaseRefName`, weil der alte Branch zu viele Merge-Konflikte hatte.

Regeln:
- Kein Versuch, den alten Konflikt-Branch weiter zu retten.
- Halte den Scope eng am alten PR-Ziel.
- Erstelle einen neuen PR auf frischer Basis.
- Dokumentiere Abweichungen zum alten PR kurz im neuen PR.
"@.Trim()
}
