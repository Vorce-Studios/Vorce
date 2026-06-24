# ProjectManager.ps1 (Vorce 3.0)
# GitHub Project integration through the central shell-free GitHub client.

$githubClientPath = Join-Path $PSScriptRoot '../integrations/GitHubClient.ps1'
if (-not (Get-Command Invoke-VorceGitHubCommand -ErrorAction SilentlyContinue)) {
    . $githubClientPath
}

function Get-VorceProjectSettings {
    return [pscustomobject]@{
        Owner = if ($env:VORCE_PROJECT_OWNER) { $env:VORCE_PROJECT_OWNER } else { 'Vorce-Studios' }
        Number = if ($env:VORCE_PROJECT_NUMBER) { [int]$env:VORCE_PROJECT_NUMBER } else { 1 }
    }
}

function Invoke-GhCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 30
    )

    $result = Invoke-VorceGitHubCommand -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
    if (-not $result.Succeeded) {
        Write-VorceStep `
            -Message "gh $($Arguments[0]) fehlgeschlagen: $(Get-VorceGitHubCommandDiagnostic -Result $result)" `
            -Status 'WARN'
        return $null
    }

    try {
        return ConvertFrom-VorceGitHubJson -CommandResult $result
    } catch {
        Write-VorceStep -Message "gh $($Arguments[0]) lieferte ungueltiges JSON: $($_.Exception.Message)" -Status 'WARN'
        return $null
    }
}

function Sync-VorceProjectState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunState
    )

    $settings = Get-VorceProjectSettings
    Write-VorceStep -Message "Synchronisiere Status ($($RunState.status)) mit GitHub Project #$($settings.Number)..." -Status 'RUN'

    try {
        $projectData = Invoke-GhCommand -Arguments @(
            'project', 'view', [string]$settings.Number,
            '--owner', $settings.Owner,
            '--format', 'json'
        )

        if ($projectData) {
            Write-VorceStep -Message "GitHub Project '$($projectData.title)' gelesen." -Status 'OK'
        } else {
            Write-VorceStep -Message 'GitHub Project nicht erreichbar. Ueberspringe Sync.' -Status 'WARN'
        }
    } catch {
        Write-VorceStep -Message "GitHub Project Sync fehlgeschlagen: $($_.Exception.Message)" -Status 'WARN'
    }
}
