Set-StrictMode -Version Latest

$script:JulesApiBaseUri = "https://jules.googleapis.com/v1alpha"

$script:JulesMaxConcurrentSessions = if ($env:JULES_MAX_CONCURRENT_SESSIONS) { [int]$env:JULES_MAX_CONCURRENT_SESSIONS } else { 10 }
$script:JulesRateLimitDelayMs = if ($env:JULES_RATE_LIMIT_DELAY_MS) { [int]$env:JULES_RATE_LIMIT_DELAY_MS } else { 800 }
$script:JulesActiveSessions = @()
$script:JulesSessionThrottleLock = [System.Threading.Mutex]::new($false)

function Initialize-JulesConsole {
    $utf8 = [System.Text.Encoding]::UTF8
    $global:OutputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding = $utf8
}

function Write-JulesInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-JulesWarn {
    param([string]$Message)
    Write-Warning $Message
}

function Get-JulesMaxConcurrentSessions {
    param([int]$Override)
    if ($Override -gt 0) { return $Override }
    if ($env:JULES_MAX_CONCURRENT_SESSIONS) { return [int]$env:JULES_MAX_CONCURRENT_SESSIONS }
    return $script:JulesMaxConcurrentSessions
}

function Get-JulesRateLimitDelayMs {
    param([int]$Override)
    if ($Override -gt 0) { return $Override }
    if ($env:JULES_RATE_LIMIT_DELAY_MS) { return [int]$env:JULES_RATE_LIMIT_DELAY_MS }
    return $script:JulesRateLimitDelayMs
}

function Register-JulesActiveSession {
    param([Parameter(Mandatory)][string]$SessionId)
    $script:JulesActiveSessions += $SessionId
}

function Unregister-JulesActiveSession {
    param([Parameter(Mandatory)][string]$SessionId)
    $script:JulesActiveSessions = $script:JulesActiveSessions | Where-Object { $_ -ne $SessionId }
}

function Get-JulesActiveSessionCount {
    return $script:JulesActiveSessions.Count
}

function Wait-ForJulesSessionSlot {
    [CmdletBinding()]
    param(
        [int]$MaxConcurrent,
        [int]$TimeoutSeconds = 300
    )

    $max = if ($MaxConcurrent -gt 0) { $MaxConcurrent } else { Get-JulesMaxConcurrentSessions }
    $start = Get-Date
    $waited = $false

    while ($script:JulesActiveSessions.Count -ge $max) {
        if ((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds -gt $TimeoutSeconds) {
            throw "Timeout beim Warten auf freien Jules Session-Slot nach $TimeoutSeconds Sekunden."
        }
        Write-JulesInfo "Warte auf freien Session-Slot... ($($script:JulesActiveSessions.Count)/$max aktiv)"
        Start-Sleep -Milliseconds 500
        $waited = $true
    }

    if ($waited) {
        Write-JulesInfo "Slot verfuegbar, starte neue Session..."
    }
}

function Invoke-ThrottledJulesApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet("GET", "POST", "DELETE")][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query,
        [AllowNull()][object]$Body,
        [string]$ApiKey,
        [string]$SessionId,
        [int]$MaxConcurrent,
        [int]$RateLimitDelayMs
    )

    Wait-ForJulesSessionSlot -MaxConcurrent $MaxConcurrent

    if ($RateLimitDelayMs -gt 0 -or $script:JulesRateLimitDelayMs -gt 0) {
        $delay = if ($RateLimitDelayMs -gt 0) { $RateLimitDelayMs } else { $script:JulesRateLimitDelayMs }
        Start-Sleep -Milliseconds $delay
    }

    if ($SessionId) {
        Register-JulesActiveSession -SessionId $SessionId
    }

    try {
        return Invoke-JulesApiRequest -Method $Method -Path $Path -Query $Query -Body $Body -ApiKey $ApiKey
    } finally {
        if ($SessionId) {
            Unregister-JulesActiveSession -SessionId $SessionId
        }
    }
}

function Get-JulesApiKey {
    param([string]$ApiKey)

    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        return $ApiKey.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($env:JULES_API_KEY)) {
        return $env:JULES_API_KEY.Trim()
    }

    throw "JULES_API_KEY fehlt. Bitte -ApiKey angeben oder JULES_API_KEY setzen."
}

function Get-JulesHttpErrorMessage {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -eq $ErrorRecord) {
        return "Unbekannter HTTP-Fehler."
    }

    if ($null -ne $ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        return $ErrorRecord.ErrorDetails.Message
    }

    if ($null -ne $ErrorRecord.Exception) {
        return $ErrorRecord.Exception.Message
    }

    return "Unbekannter Fehler: $ErrorRecord"
}

function ConvertTo-JulesQueryString {
    param([hashtable]$Query)

    if (-not $Query -or $Query.Count -eq 0) {
        return ""
    }

    $parts = foreach ($key in $Query.Keys) {
        $value = $Query[$key]
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            continue
        }

        "{0}={1}" -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$value)
    }

    if (-not $parts) {
        return ""
    }

    return "?" + ($parts -join "&")
}

function Invoke-JulesApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet("GET", "POST", "DELETE")][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Query,
        [AllowNull()][object]$Body,
        [string]$ApiKey
    )

    $uri = "{0}/{1}{2}" -f $script:JulesApiBaseUri, $Path.TrimStart("/"), (ConvertTo-JulesQueryString -Query $Query)
    $headers = @{ "x-goog-api-key" = (Get-JulesApiKey -ApiKey $ApiKey) }

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = "Stop"
    }

    if ($Method -eq "POST") {
        $invokeParams["ContentType"] = "application/json"
        $invokeParams["Body"] = if ($null -eq $Body) { "{}" } else { $Body | ConvertTo-Json -Depth 20 }
    }

    try {
        return Invoke-RestMethod @invokeParams
    } catch {
        throw ("Jules API Fehler bei {0} {1}: {2}" -f $Method, $uri, (Get-JulesHttpErrorMessage -ErrorRecord $_))
    }
}

function Resolve-JulesSessionName {
    param([Parameter(Mandatory)][string]$SessionIdOrName)

    if ($SessionIdOrName -match "^sessions/[^/]+$") {
        return $SessionIdOrName
    }

    return "sessions/$SessionIdOrName"
}

function Resolve-JulesSessionId {
    param([Parameter(Mandatory)][string]$SessionIdOrName)

    if ($SessionIdOrName -match "^sessions/(?<id>[^/]+)$") {
        return $Matches["id"]
    }

    return $SessionIdOrName
}

function Test-JulesObjectProperty {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }

    $property = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    return $null -ne $property
}

function Get-JulesObjectPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-JulesObjectProperty -Object $Object -Name $Name)) {
        return $null
    }

    $property = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-JulesSession {
    param([Parameter(Mandatory)][string]$SessionIdOrName, [string]$ApiKey)

    Invoke-JulesApiRequest -Method GET -Path (Resolve-JulesSessionName -SessionIdOrName $SessionIdOrName) -ApiKey $ApiKey
}

function Get-AllJulesSessions {
    param([int]$PageSize = 50, [int]$MaxPages = 5, [string]$ApiKey)

    $sessions = @()
    $pageToken = $null

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ pageSize = $PageSize }
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) {
            $query["pageToken"] = $pageToken
        }

        $response = Invoke-JulesApiRequest -Method GET -Path "sessions" -Query $query -ApiKey $ApiKey
        if ($null -eq $response) {
            break
        }

        $responseSessions = Get-JulesObjectPropertyValue -Object $response -Name "sessions"
        if ($null -ne $responseSessions) {
            $sessions += @($responseSessions)
        }

        $nextPageToken = [string](Get-JulesObjectPropertyValue -Object $response -Name "nextPageToken")
        if ([string]::IsNullOrWhiteSpace($nextPageToken)) {
            break
        }

        $pageToken = $nextPageToken
    }

    return $sessions
}

function Get-AllJulesActivities {
    param(
        [Parameter(Mandatory)][string]$SessionIdOrName,
        [int]$PageSize = 20,
        [int]$MaxPages = 3,
        [string]$ApiKey
    )

    $activities = @()
    $pageToken = $null
    $path = "{0}/activities" -f (Resolve-JulesSessionName -SessionIdOrName $SessionIdOrName)

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $query = @{ pageSize = $PageSize }
        if (-not [string]::IsNullOrWhiteSpace($pageToken)) {
            $query["pageToken"] = $pageToken
        }

        $response = Invoke-JulesApiRequest -Method GET -Path $path -Query $query -ApiKey $ApiKey
        if ($null -eq $response) {
            break
        }

        $responseActivities = Get-JulesObjectPropertyValue -Object $response -Name "activities"
        if ($null -ne $responseActivities) {
            $activities += @($responseActivities)
        }

        $nextPageToken = [string](Get-JulesObjectPropertyValue -Object $response -Name "nextPageToken")
        if ([string]::IsNullOrWhiteSpace($nextPageToken)) {
            break
        }

        $pageToken = $nextPageToken
    }

    return $activities
}

function Get-JulesSources {
    param([int]$PageSize = 100, [string]$ApiKey)

    Invoke-JulesApiRequest -Method GET -Path "sources" -Query @{ pageSize = $PageSize } -ApiKey $ApiKey
}

function Confirm-JulesSourceExists {
    param([Parameter(Mandatory)][string]$SourceName, [string]$ApiKey)

    $response = Get-JulesSources -ApiKey $ApiKey
    $match = @($response.sources | Where-Object { $_.name -eq $SourceName } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        throw "Die Jules-Quelle '$SourceName' wurde nicht gefunden."
    }

    return $match[0]
}

function Approve-JulesPlan {
    param([Parameter(Mandatory)][string]$SessionIdOrName, [string]$ApiKey)

    $path = "{0}:approvePlan" -f (Resolve-JulesSessionName -SessionIdOrName $SessionIdOrName)
    Invoke-JulesApiRequest -Method POST -Path $path -Body @{} -ApiKey $ApiKey | Out-Null
}

function Send-JulesMessage {
    param([Parameter(Mandatory)][string]$SessionIdOrName, [Parameter(Mandatory)][string]$Message, [string]$ApiKey)

    $path = "{0}:sendMessage" -f (Resolve-JulesSessionName -SessionIdOrName $SessionIdOrName)
    Invoke-JulesApiRequest -Method POST -Path $path -Body @{ prompt = $Message } -ApiKey $ApiKey | Out-Null
}

function Get-JulesSessionPullRequestUrl {
    param([AllowNull()][object]$Session)

    if ($null -eq $Session) {
        return $null
    }

    foreach ($output in @(Get-JulesObjectPropertyValue -Object $Session -Name "outputs")) {
        $pullRequest = Get-JulesObjectPropertyValue -Object $output -Name "pullRequest"
        if ($null -ne $pullRequest -and -not [string]::IsNullOrWhiteSpace([string](Get-JulesObjectPropertyValue -Object $pullRequest -Name "url"))) {
            return [string]$output.pullRequest.url
        }
    }

    return $null
}

function Get-JulesLatestActivity {
    param([AllowNull()][object[]]$Activities)

    if (-not $Activities) {
        return $null
    }

    $Activities | Sort-Object createTime -Descending | Select-Object -First 1
}

function Get-JulesActivitySummary {
    param([AllowNull()][object]$Activity)

    if ($null -eq $Activity) { return $null }

    $sessionFailed = Get-JulesObjectPropertyValue -Object $Activity -Name "sessionFailed"
    if ($null -ne $sessionFailed) {
        $reason = [string](Get-JulesObjectPropertyValue -Object $sessionFailed -Name "reason")
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            return "Session fehlgeschlagen: $reason"
        }

        return "Session fehlgeschlagen"
    }

    $agentMessaged = Get-JulesObjectPropertyValue -Object $Activity -Name "agentMessaged"
    if ($null -ne $agentMessaged) {
        $agentMessage = [string](Get-JulesObjectPropertyValue -Object $agentMessaged -Name "agentMessage")
        if (-not [string]::IsNullOrWhiteSpace($agentMessage)) {
            return "Jules: $agentMessage"
        }

        return "Jules-Antwort"
    }

    $progressUpdated = Get-JulesObjectPropertyValue -Object $Activity -Name "progressUpdated"
    if ($null -ne $progressUpdated) {
        $title = [string](Get-JulesObjectPropertyValue -Object $progressUpdated -Name "title")
        $description = [string](Get-JulesObjectPropertyValue -Object $progressUpdated -Name "description")
        if (-not [string]::IsNullOrWhiteSpace($description)) {
            if ([string]::IsNullOrWhiteSpace($title)) {
                return $description
            }

            return "$title - $description"
        }

        if (-not [string]::IsNullOrWhiteSpace($title)) {
            return $title
        }

        return "Fortschritt aktualisiert"
    }

    if ($null -ne (Get-JulesObjectPropertyValue -Object $Activity -Name "planGenerated")) { return "Plan erstellt" }
    if ($null -ne (Get-JulesObjectPropertyValue -Object $Activity -Name "planApproved")) { return "Plan freigegeben" }
    if ($null -ne (Get-JulesObjectPropertyValue -Object $Activity -Name "sessionCompleted")) { return "Session abgeschlossen" }

    $userMessaged = Get-JulesObjectPropertyValue -Object $Activity -Name "userMessaged"
    if ($null -ne $userMessaged) {
        $userMessage = [string](Get-JulesObjectPropertyValue -Object $userMessaged -Name "userMessage")
        if (-not [string]::IsNullOrWhiteSpace($userMessage)) {
            return "User: $userMessage"
        }

        return "User-Nachricht"
    }

    $description = [string](Get-JulesObjectPropertyValue -Object $Activity -Name "description")
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        return $description
    }

    return "Aktivitaet aktualisiert"
}

function Test-JulesAttentionRequired {
    param([AllowNull()][object]$Session)

    if ($null -eq $Session) { return $false }

    @("AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "PAUSED", "FAILED") -contains [string]$Session.state
}

function Get-IssueNumberFromSession {
    param([Parameter(Mandatory)][object]$Session)

    foreach ($candidate in @([string]$Session.title, [string]$Session.prompt)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match "Issue\s+#(?<id>\d+)") {
            return [int]$Matches["id"]
        }
    }

    return $null
}

Initialize-JulesConsole
