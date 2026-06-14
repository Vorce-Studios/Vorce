# SUB-RUN-04_Delegation.ps1 (Vorce 3.0)
# Delegiert Proposals an Jules und erstellt GitHub Issues
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")
. (Join-Path $global:LibDir "integrations/GitHubClient.ps1")

Write-VorceStep -Message "Starte Delegation..." -Status "RUN"

# 1. Lese alle Proposals aus var/db/proposals/*.json
$proposalsDir = Join-Path $global:VarDir "db/proposals"
$proposals = @()

if (Test-Path $proposalsDir) {
    $proposalFiles = Get-ChildItem -Path $proposalsDir -Filter "proposal_*.json" | Sort-Object Name
    foreach ($file in $proposalFiles) {
        try {
            $proposal = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $proposals += $proposal
        } catch {
            Write-VorceStep -Message "Fehler beim Lesen von $($file.Name): $($_.Exception.Message)" -Status "ERROR"
        }
    }
}

if ($proposals.Count -eq 0) {
    Write-VorceStep -Message "Keine Proposals zum Delegieren gefunden." -Status "INFO"
    return @{ status="no_proposals"; delegations=@(); count=0 }
}

Write-VorceStep -Message "Found $($proposals.Count) Proposals to delegate" -Status "INFO"

# 2. Für jedes Proposal
$delegations = @()
$taskJournalDir = Join-Path $global:VarDir "db"
$taskJournalFile = Join-Path $taskJournalDir "task-journal.json"

foreach ($proposal in $proposals) {
    $delegation = @{
        proposalId = $proposal.issueId
        proposalNumber = $proposal.issueNumber
        title = $proposal.title
        status = "pending"
        timestamp = (Get-Date).ToString("o")
        delegatedTo = "jules"
        issueUrl = $null
        errorMessage = $null
    }

    Write-VorceStep -Message "Delegiere Proposal: $($proposal.title)" -Status "RUN"

    try {
        # 2a. Prüfe ob Jules-Quota verfügbar
        $quotaOK = Test-VorceQuota -AgentName "jules"
        if (-not $quotaOK) {
            throw "Jules Quota erschöpft"
        }

        # 2b. Erstelle Jules-Task via gh CLI
        $repo = $ConfigBag.Config.repository
        $title = "Strategy Task: $($proposal.title)"

        # GitHub Issue erstellen
        $ghCommand = "gh issue create --repo ""$repo"" --title ""$title"" --label ""jules-task,autopilot-created"" --body ""Delegiert von Vorce Autopilot: Deliberation für Issue #$(if ($proposal.issueNumber) { $proposal.issueNumber } else { $proposal.issueId }).`n`nDeliberation Result:`n$($proposal.deliberation | ConvertTo-Json -Depth 5)"""

        Write-VorceStep -Message "Führe aus: $ghCommand" -Status "INFO"

        # Führe gh command aus
        $result = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$repo/issues" -Method POST -Body @{
            title = $title
                    labels = @("jules-task", "autopilot-created")
                    body = "Delegiert von Vorce Autopilot: Deliberation für Issue #$(if ($proposal.issueNumber) { $proposal.issueNumber } else { $proposal.issueId }).`n`nDeliberation Result:`n$($proposal.deliberation | ConvertTo-Json -Depth 5)"
        } -Headers @{
            "Authorization" = "token $((Get-Content (Join-Path $global:VarDir "config/github-token.txt") -Raw).Trim())"
            "Accept" = "application/vnd.github.v3+json"
        }

        $delegation.status = "success"
        $delegation.issueUrl = $result.html_url
        $delegation.issueNumber = $result.number

        # 2c. Registriere Quota-Usage
        Register-VorceQuotaUsage -AgentName "jules" -Cost 0.5  # Kostenloses Jules Task

        Write-VorceStep -Message "GitHub Issue erstellt: $($result.html_url)" -Status "OK"

    } catch {
        $delegation.status = "failed"
        $delegation.errorMessage = $_.Exception.Message
        Write-VorceStep -Message "Fehler bei Delegation: $($_.Exception.Message)" -Status "ERROR"
    }

    $delegations += $delegation
}

# 3. Speichere Delegierungs-Ergebnisse in var/db/task-journal.json
$taskJournal = @{
    delegations = $delegations
    timestamp = (Get-Date).ToString("o")
    total = $delegations.Count
    successful = ($delegations | Where-Object { $_.status -eq "success" }).Count
    failed = ($delegations | Where-Object { $_.status -eq "failed" }).Count
}

if (-not (Test-Path $taskJournalDir)) {
    New-Item -ItemType Directory -Path $taskJournalDir -Force | Out-Null
}

$taskJournal | ConvertTo-Json -Depth 10 | Set-Content $taskJournalFile -Encoding UTF8

# 4. Aktualisiere $ConfigBag.GlobalState.active_delegations
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
    $ConfigBag.GlobalState | Add-Member -MemberType NoteProperty -Name "active_delegations" -Value @() -Force
}

foreach ($delegation in $delegations) {
    if ($delegation.status -eq "success") {
        $ConfigBag.GlobalState.active_delegations += @{
            issueNumber = $delegation.issueNumber
            title = $delegation.title
            url = $delegation.issueUrl
            timestamp = $delegation.timestamp
        }
    }
}

# 5. State zurückgeben
$delegationResult = @{
    status = "completed"
    delegations = $delegations
    count = $delegations.Count
    successful = $taskJournal.successful
    failed = $taskJournal.failed
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Delegation abgeschlossen: $($delegationResult.successful) erfolgreich, $($delegationResult.failed) fehlgeschlagen." -Status "OK"
return $delegationResult