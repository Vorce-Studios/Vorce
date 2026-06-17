# SUB-RUN-04_AlertDisposition.ps1 (Vorce 3.0)
# Handhabt aktive System-Alerts und Warnungen
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

Write-VorceStep -Message "Starte AlertDisposition..." -Status "RUN"

# Prüfe ob Alerts vorhanden sind
if (-not $ConfigBag.GlobalState.PSObject.Properties.Name -contains "alerts") {
    Write-VorceStep -Message "Keine aktiven Alerts zum Handhaben." -Status "INFO"
    return @{ status="no_alerts"; alerts_processed=0; alert_resolution="none"; timestamp=(Get-Date).ToString("o") }
}

$alerts = @($ConfigBag.GlobalState.alerts | Where-Object { $null -ne $_ })
if ($alerts.Count -eq 0) {
    Write-VorceStep -Message "Keine aktiven Alerts zum Handhaben." -Status "INFO"
    return @{ status="no_alerts"; alerts_processed=0; alert_resolution="none"; timestamp=(Get-Date).ToString("o") }
}

$alertsProcessed = 0
$resolvedAlerts = 0
$escalatedAlerts = 0
$alertDisposition = @()

foreach ($alert in $alerts) {
    $alertsProcessed++

    Write-VorceStep -Message "Handhabe Alert: $($alert.type) - $($alert.severity)" -Status "RUN"

    $disposition = @{
        alert_id = $(if ($null -ne $alert.id) { $alert.id } else { "unknown" })
        alert_type = $alert.type
        alert_severity = $alert.severity
        timestamp = $(if ($null -ne $alert.timestamp) { $alert.timestamp } else { "unknown" })
        disposition = "unhandled"
        resolution = "none"
    }

    # Basierend auf Severity und Alert Type entscheiden was zu tun ist
    switch ($alert.severity) {
        "critical" {
            # Critical Alerts sofort eskalieren
            if ($alert.type -eq "system_error") {
                # System Error: Notifizieren und potenziell System stoppen
                $disposition.disposition = "escalated"
                $disposition.resolution = "escalated_to_admin"
                $disposition.message = "System Error eskaliert an Administrator"

                # Speichere Eskalations-Informationen
                if (-not $ParentState.alert_escalations) {
                    $ParentState | Add-Member -MemberType NoteProperty -Name "alert_escalations" -Value @() -Force
                }
                $ParentState.alert_escalations += @{
                    alert_id = $alert.id;
                    type = $alert.type;
                    severity = "critical";
                    escalated_at = (Get-Date).ToString("o");
                    resolved = $false
                }

                $escalatedAlerts++
            } elseif ($alert.type -eq "quota_exhausted") {
                # Quota Exhausted: Benachrichtigen und Quota prüfen
                $disposition.disposition = "notified"
                $disposition.resolution = "quota_check_requested"
                $disposition.message = "Quota Exhausted Benachrichtigung gesendet"
            }
        }

        "high" {
            # High Alerts eskalieren oder manuell handhaben
            $disposition.disposition = "escalated"
            $disposition.resolution = "manual_review_required"
            $disposition.message = "High Alert benötigt manuelle Überprüfung"

            $escalatedAlerts++
        }

        "medium" {
            # Medium Alerts automatisch handhaben
            if ($alert.type -eq "session_timeout") {
                # Session Timeout: Bereinigen
                $disposition.disposition = "resolved"
                $disposition.resolution = "session_cleaned"
                $disposition.message = "Timeout Session bereinigt"

                # Bereinige timeout Session
                if ($ConfigBag.GlobalState.active_delegations) {
                    $cleanedSessions = $ConfigBag.GlobalState.active_delegations | Where-Object {
                        ($_.timestamp -and ((Get-Date) - [datetime]$_.timestamp).TotalHours -gt 48) -or $_.status -eq "timeout"
                    }
                    $ConfigBag.GlobalState.active_delegations = $ConfigBag.GlobalState.active_delegations | Where-Object {
                        not (($_.timestamp -and ((Get-Date) - [datetime]$_.timestamp).TotalHours -gt 48) -or $_.status -eq "timeout")
                    }
                }

                $resolvedAlerts++
            } else {
                # Andere Medium Alerts automatisch auflösen
                $disposition.disposition = "resolved"
                $disposition.resolution = "auto_resolved"
                $disposition.message = "Medium Alert automatisch gelöst"

                $resolvedAlerts++
            }
        }

        "low" {
            # Low Alerts ignorieren oder automatisch auflösen
            $disposition.disposition = "ignored"
            $disposition.resolution = "auto_ignored"
            $disposition.message = "Low Alert ignoriert (automatisiert)"
        }

        default {
            # Unbekannte Severity: Notifizieren
            $disposition.disposition = "notified"
            $disposition.resolution = "unknown_severity"
            $disposition.message = "Alert mit unbekannter Severity notifiziert"
        }
    }

    # Speichere Disposition in ParentState
    if (-not $ParentState.alert_dispositions) {
        $ParentState | Add-Member -MemberType NoteProperty -Name "alert_dispositions" -Value @() -Force
    }
    $ParentState.alert_dispositions += $disposition

    $alertDisposition += $disposition
}

# Aktualisiere GlobalState - entferne behandelte Alerts
$handledAlertIds = $alertDisposition | Where-Object { $_.disposition -ne "ignored" } | ForEach-Object { $_.alert_id }
$remainingAlerts = @($alerts | Where-Object { $handledAlertIds -notcontains $_.id })

if ($remainingAlerts.Count -ne $alerts.Count) {
    $ConfigBag.GlobalState.alerts = $remainingAlerts
    Write-VorceStep -Message "Aktualisiere Alerts: $($alerts.Count) → $($remainingAlerts.Count)" -Status "INFO"
}

# Alert-Disposition Ergebnis
$alertDispositionResult = @{
    status = "completed"
    alerts_processed = $alertsProcessed
    alerts_resolved = $resolvedAlerts
    alerts_escalated = $escalatedAlerts
    alerts_ignored = ($alertDisposition | Where-Object { $_.disposition -eq "ignored" }).Count
    remaining_alerts = $remainingAlerts.Count
    disposition_details = $alertDisposition
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "AlertDisposition abgeschlossen: $resolvedAlerts gelöst, $escalatedAlerts eskaliert, $($remainingAlerts.Count) verbleiben." -Status "OK"
return $alertDispositionResult
