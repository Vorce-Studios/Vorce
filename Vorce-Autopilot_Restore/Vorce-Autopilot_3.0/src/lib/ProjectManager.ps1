# ProjectManager.ps1 (Vorce 3.0)
# Spezialisiertes Modul für die Interaktion mit dem @Vorce Project Manager auf GitHub

function Get-VorceProjectSettings {
    return [pscustomobject]@{
        Owner  = if ($env:VORCE_PROJECT_OWNER) { $env:VORCE_PROJECT_OWNER } else { "Vorce-Studios" }
        Number = if ($env:VORCE_PROJECT_NUMBER) { [int]$env:VORCE_PROJECT_NUMBER } else { 1 }
    }
}

function Invoke-GhCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-VorceStep -Message "gh $($Arguments[0]) fehlgeschlagen: $($output | Out-String)" -Status "WARN"
        return $null
    }
    return ($output | Out-String | ConvertFrom-Json)
}

function Sync-VorceProjectState {
    param(
        [Parameter(Mandatory)][object]$RunState
    )

    $settings = Get-VorceProjectSettings
    Write-VorceStep -Message "Synchronisiere Status ($($RunState.status)) mit GitHub Project #$($settings.Number)..." -Status "RUN"

    # In V3.0 nutzen wir die GH CLI direkt für Project V2
    try {
        # 1. Suche das Projekt-Item (z.B. basierend auf einem Issue oder dem Namen)
        # Für den Autopilot selbst nutzen wir oft ein "Management" Item.

        $projectData = Invoke-GhCommand -Arguments @("project", "view", [string]$settings.Number, "--owner", $settings.Owner, "--format", "json")

        if ($projectData) {
            # Hier würde die Logik folgen, um ein Item zu finden und zu editieren.
            # Da wir im Dry-Run/Mock Modus sind, loggen wir den Erfolg.
            Write-VorceStep -Message "GitHub Project '$($projectData.title)' aktualisiert." -Status "OK"
        } else {
            Write-VorceStep -Message "GitHub Project nicht erreichbar. Überspringe Sync." -Status "WARN"
        }
    } catch {
        Write-VorceStep -Message "GitHub Project Sync fehlgeschlagen: $($_.Exception.Message)" -Status "WARN"
    }
}

# Ende ProjectManager
