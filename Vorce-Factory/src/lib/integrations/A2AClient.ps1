# A2AClient.ps1 (Vorce 3.0)
# JSON-RPC 2.0 A2A Client fuer Dashboard-Kommunikation

function Send-VorceA2AMessage {
    param(
        [Parameter(Mandatory)][string]$TargetAgent,
        [Parameter(Mandatory)][string]$MessageType,
        [Parameter(Mandatory)][hashtable]$Payload,
        [Parameter(Mandatory)][string]$CorrelationId
    )

    $body = @{
        jsonrpc = "2.0"
        method  = "sendMessage"
        params  = @{
            target        = $TargetAgent
            type          = $MessageType
            payload       = $Payload
            correlationId = $CorrelationId
        }
        id      = [guid]::NewGuid().ToString()
    }

    try {
        $null = Invoke-RestMethod `
            -Uri "http://localhost:5174/api/a2a" `
            -Method Post `
            -Body ($body | ConvertTo-Json -Depth 10) `
            -ContentType "application/json" `
            -ErrorAction Stop
    } catch {
        # Dashboard/A2A Hub nicht verfuegbar – non-blocking, stumm ignorieren
    }
}

function Initialize-VorceA2AClient {
    . $PSScriptRoot\A2AClient.ps1
}

# Keine Export-ModuleMember noetig — diese Datei wird per Dot-Sourcing (.) geladen.
