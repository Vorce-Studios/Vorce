# Vorce-Autopilot/src/lib/jules-client.ps1
Set-StrictMode -Version Latest

# Setup paths relative to script root
$script:JulesScriptDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "scripts/jules"

# Dot-source the underlying jules api functions
if (Test-Path -Path (Join-Path $script:JulesScriptDir "jules-api.ps1")) {
    . (Join-Path $script:JulesScriptDir "jules-api.ps1")
}

function New-JulesSession {
    param(
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][string]$Repository,
        [string]$ApiKey,
        [switch]$AutoCreatePr
    )

    $createCmdPath = Join-Path $script:JulesScriptDir "create-jules-session.ps1"
    if (-not (Test-Path -Path $createCmdPath)) {
        throw "create-jules-session.ps1 nicht gefunden unter: $createCmdPath"
    }

    $params = @{
        IssueNumber = $IssueNumber
        Repository = $Repository
    }

    if ($ApiKey) {
        $params["ApiKey"] = $ApiKey
    }

    if ($AutoCreatePr) {
        $params["AutoCreatePr"] = $true
    }

    Write-Host "[JULES-CLIENT] Rufe create-jules-session.ps1 auf fuer Issue #$IssueNumber..." -ForegroundColor Cyan
    $sessionResult = & $createCmdPath @params

    $sessionId = "unknown"
    if ($sessionResult) {
        if ($sessionResult -is [System.Array]) {
            $targetObj = $sessionResult | Where-Object { $_ -and ($_.PSObject.Properties.Name -contains "SessionId") -and $_.SessionId } | Select-Object -First 1
            if ($targetObj) {
                $sessionId = [string]$targetObj.SessionId
            } else {
                $lastObj = $sessionResult[-1]
                if ($lastObj -and ($lastObj.PSObject.Properties.Name -contains "SessionId")) {
                    $sessionId = [string]$lastObj.SessionId
                }
            }
        } elseif (($sessionResult.PSObject.Properties.Name -contains "SessionId") -and $sessionResult.SessionId) {
            $sessionId = [string]$sessionResult.SessionId
        }
    }

    if ($sessionId -eq "unknown") {
        throw "Fehler beim Extrahieren der SessionId aus dem Ergebnis von create-jules-session"
    }

    return $sessionId
}

function Get-JulesSessionStatus {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$ApiKey
    )

    $resolvedApiKey = if ($ApiKey) { $ApiKey } else { $env:JULES_API_KEY }

    # We can use Invoke-JulesApiRequest if jules-api.ps1 is dot-sourced
    if (Get-Command "Get-JulesSession" -ErrorAction SilentlyContinue) {
        try {
            $session = Get-JulesSession -SessionIdOrName $SessionId -ApiKey $resolvedApiKey
            return $session
        } catch {
            Write-Warning "[JULES-CLIENT] Fehler beim Laden der Session ${SessionId}: $_"
            return $null
        }
    }

    # Fallback to direct REST call if jules-api is not sourced
    $headers = @{
        'x-goog-api-key' = $resolvedApiKey
        'Content-Type' = 'application/json'
    }

    $uri = "https://jules.googleapis.com/v1alpha/sessions/$SessionId"
    try {
        $session = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        return $session
    } catch {
        Write-Warning "[JULES-CLIENT] Fallback REST-Call fehlgeschlagen fuer ${SessionId}: $_"
        return $null
    }
}
