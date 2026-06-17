# SUB-RUN-01_SessionSync.ps1 (Vorce 3.0)
# Synchronisiert den Status aller aktiven Jules-Sessions
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "integrations/GitHubClient.ps1")
. (Join-Path $global:LibDir "integrations/ApiClient.ps1")

Write-VorceStep -Message "Starte SessionSync..." -Status "RUN"

# 1. Lese active_delegations aus GlobalState
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "active_delegations") {
    Write-VorceStep -Message "Keine aktiven Delegations gefunden." -Status "INFO"
    return @{ status="no_active_delegations"; updates=0; timestamp=(Get-Date).ToString("o") }
}

$activeDelegations = $ConfigBag.GlobalState.active_delegations
$updatedCount = 0

# 2. Für jede Delegation: Prüfe PR-Status via gh CLI
foreach ($delegation in $activeDelegations) {
    if ($delegation.issueNumber -and $delegation.url) {
        Write-VorceStep -Message "Prüfe Status für Delegation #$($delegation.issueNumber): $($delegation.title)" -Status "RUN"

        try {
            # PR Status via GitHub API prüfen
            $repo = $ConfigBag.Config.repository
            $prNumber = $delegation.issueNumber  # Annahme: IssueNumber ist auch PR Number

            # GitHub API Aufruf
            $prResponse = Invoke-VorceApiRequest -Uri "https://api.github.com/repos/$repo/pulls/$prNumber" -Method GET

            $newStatus = "unknown"
            switch ($prResponse.state) {
                "open" { $newStatus = "open" }
                "closed" {
                    if ($prResponse.merged_at) {
                        $newStatus = "merged"
                    } else {
                        $newStatus = "closed"
                    }
                }
                "merged" { $newStatus = "merged" }
            }

            # Aktualisiere den Status in der Delegation
            $delegation.status = $newStatus
            $delegation.lastSync = (Get-Date).ToString("o")

            # Wenn der Status sich geändert hat, zähle als Update
            if ($delegation.previousStatus -ne $newStatus) {
                $delegation.previousStatus = $newStatus
                Write-VorceStep -Message "Status geändert: $($(if ($null -ne $delegation.previousStatus) { $delegation.previousStatus } else { 'unknown' })) → $newStatus" -Status "OK"
                $updatedCount++
            } else {
                Write-VorceStep -Message "Status unverändert: $newStatus" -Status "INFO"
            }

        } catch {
            Write-VorceStep -Message "Fehler beim Prüfen von #$($delegation.issueNumber): $($_.Exception.Message)" -Status "WARN"
        }
    } else {
        Write-VorceStep -Message "Ungültige Delegation ohne Issue Number/URL" -Status "WARN"
    }
}

# 3. Speichere aktualisierten GlobalState
Save-VorceGlobalState -State $ConfigBag.GlobalState

# 4. Gib State mit Anzahl Updates zurück
$syncResult = @{
    status = "completed"
    updates = $updatedCount
    totalDelegations = $activeDelegations.Count
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "SessionSync abgeschlossen: $updatedCount von $($activeDelegations.Count) Delegations aktualisiert." -Status "OK"
return $syncResult
