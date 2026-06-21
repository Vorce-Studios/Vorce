# sync-service.ps1 (Vorce 3.0)
# Minimal WebSocket server that streams the current runtime state to the dashboard.
[CmdletBinding()]
param(
    [int]$Port = 5174,
    [string]$VorceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
)

# Import logging module
$LoggingModule = Join-Path $PSScriptRoot "..\..\..\src\lib\logging\Write-Log.ps1"
if (Test-Path -LiteralPath $LoggingModule) {
    . $LoggingModule
} else {
    Write-Warning "Logging module not found at $LoggingModule"
}

# Initialize logging
Write-Log -Level INFO -Message "Starting sync service" -Component "sync-service" -Data @{ port = $Port; vorce_root = $VorceRoot }

$varDir = Join-Path $VorceRoot "var"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

function Read-VorceSyncJson {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw.Trim() -eq "null") { return $null }
        return $raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ error = $_.Exception.Message; path = $Path }
    }
}

function Get-VorceSyncSnapshot {
    $runStates = @()
    $runStateDir = Join-Path $varDir "run-states"
    if (Test-Path -LiteralPath $runStateDir) {
        foreach ($file in Get-ChildItem -LiteralPath $runStateDir -File -Filter "*.json") {
            $data = Read-VorceSyncJson -Path $file.FullName

            # Extract the actual run name from the file content
            $runName = $file.BaseName
            if ($data -and $data.name) {
                $runName = $data.name
            }

            $runStates += [pscustomobject]@{
                name = $runName
                data = $data
            }
        }
    }

    return [pscustomobject]@{
        timestamp = (Get-Date).ToString("o")
        globalState = Read-VorceSyncJson -Path (Join-Path $varDir "db/global-state.json")
        taskJournal = Read-VorceSyncJson -Path (Join-Path $varDir "db/task-journal.json")
        runStates = $runStates
    }
}

Write-Log -Level INFO -Message "WebSocket sync service listening" -Component "sync-service" -Data @{ port = $Port; url = "ws://localhost:$Port/" }
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        if (-not $context.Request.IsWebSocketRequest) {
            $context.Response.StatusCode = 426
            $context.Response.Close()
            continue
        }

        $nullProtocol = [System.Management.Automation.Language.NullString]::Value
        $socket = $context.AcceptWebSocketAsync($nullProtocol).GetAwaiter().GetResult().WebSocket
        try {
            while ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                try {
                    $json = Get-VorceSyncSnapshot | ConvertTo-Json -Depth 20 -Compress
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $segment = [System.ArraySegment[byte]]::new($bytes)
                    $socket.SendAsync(
                        $segment,
                        [System.Net.WebSockets.WebSocketMessageType]::Text,
                        $true,
                        [System.Threading.CancellationToken]::None
                    ).GetAwaiter().GetResult()
                    Start-Sleep -Seconds 2
                }
                catch {
                    Write-Log -Level ERROR -Message "WebSocket Send Error: $_" -Component "sync-service" -Data @{ error = $_.Exception.Message; timestamp = Get-Date -Format "o" }
                    break
                }
            }
        }
        finally {
            if ($socket -ne $null) {
                $socket.Dispose()
            }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
