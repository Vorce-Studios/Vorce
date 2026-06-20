# Vorce Dashboard Watcher Service
# Überwacht Änderungen in db/ und run-states/ und sendet Updates via WebSocket

param(
    [string]$ServerHost = "localhost",
    [int]$ServerPort = 5174,
    [string]$WatchPaths = "db,run-states"
)

# Importiere erforderliche Module
Import-Module -Name Microsoft.PowerShell.Management -ErrorAction Stop

# Konfigurationsvariablen
$WebSocketServerScriptPath = Join-Path $PSScriptRoot "..\..\web\Dashboard\server\WebSocketServer.js"
$LogPath = Join-Path $PSScriptRoot "watcher.log"

# Globale Variablen
$WebSocketClient = $null
$Running = $false
$FileWatchers = @()

# Logging-Funktion
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    Write-Host $logEntry
    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
}

# WebSocket Verbindung herstellen
function Connect-WebSocket {
    try {
        # Prüfe, ob Node.js und npm installiert sind
        $nodeCheck = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCheck) {
            Write-Log "Node.js nicht gefunden. Bitte installieren Node.js zuerst." "ERROR"
            return $false
        }

        # Starte den WebSocket Server
        Write-Log "Starte WebSocket Server auf ws://$ServerHost:$ServerPort"
        Start-Job -Name "WebSocketServer" -FilePath $WebSocketServerScriptPath -ArgumentList $ServerHost, $ServerPort

        # Warte, bis der Server gestartet ist
        Start-Sleep -Seconds 2

        # Erstelle WebSocket Client
        $url = "ws://$ServerHost:$ServerPort"
        Write-Log "Verbinde mit WebSocket Server: $url"

        $script:WebSocketClient = New-Object System.Net.WebSocketClient($url)
        $script:WebSocketClient.OnOpen = {
            Write-Log "WebSocket Verbindung hergestellt"
        }

        $script:WebSocketClient.OnMessage = {
            param($message)
            Write-Log "Nachricht empfangen: $message"
        }

        $script:WebSocketClient.OnClose = {
            Write-Log "WebSocket Verbindung geschlossen"
        }

        $script:WebSocketClient.OnError = {
            param($error)
            Write-Log "WebSocket Fehler: $error" "ERROR"
        }

        return $true
    }
    catch {
        Write-Log "Fehler beim Verbindungsaufbau: $_" "ERROR"
        return $false
    }
}

# Dateiänderungen senden
function Send-FileUpdate {
    param(
        [string]$Path,
        [string]$EventType,
        [string]$FileName
    )

    try {
        if ($script:WebSocketClient -and $script:WebSocketClient.State -eq "Open") {
            $update = @{
                type = "file-update"
                path = $Path
                eventType = $EventType
                fileName = $FileName
                timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
                data = @{
                    fullPath = Join-Path $Path $FileName
                    size = (Get-Item -Path (Join-Path $Path $FileName) -ErrorAction SilentlyContinue).Length
                    modified = (Get-Item -Path (Join-Path $Path $FileName) -ErrorAction SilentlyContinue).LastWriteTimeUtc
                }
            } | ConvertTo-Json -Compress

            $script:WebSocketClient.Send($update)
            Write-Log "Update gesendet: $EventType - $FileName"
        }
    }
    catch {
        Write-Log "Fehler beim Senden des Updates: $_" "ERROR"
    }
}

# FileSystemWatcher erstellen
function Start-Watchers {
    $watchPaths = $WatchPaths -split ","

    foreach ($path in $watchPaths) {
        $fullPath = Join-Path $PSScriptRoot "..\$path"

        if (Test-Path $fullPath) {
            Write-Log "Starte Watcher für: $fullPath"

            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path = $fullPath
            $watcher.IncludeSubdirectories = $true
            $watcher.EnableRaisingEvents = $true

            # Filter für bestimmte Dateitypen
            $watcher.Filter = "*.json,*.log,*.md"

            # Ereignishandler
            $created = Register-ObjectEvent -InputObject $watcher -EventName Created -Action {
                Send-FileUpdate -Path $sender.Path -EventType "Created" -FileName $Name
            }

            $changed = Register-ObjectEvent -InputObject $watcher -EventName Changed -Action {
                Send-FileUpdate -Path $sender.Path -EventType "Changed" -FileName $Name
            }

            $deleted = Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action {
                Send-FileUpdate -Path $sender.Path -EventType "Deleted" -FileName $Name
            }

            $script:FileWatchers += @($watcher, $created, $changed, $deleted)
        }
        else {
            Write-Log "Verzeichnis nicht gefunden: $fullPath" "WARNING"
        }
    }
}

# Watcher stoppen
function Stop-Watchers {
    foreach ($item in $script:FileWatchers) {
        if ($item -is [System.IO.FileSystemWatcher]) {
            $item.EnableRaisingEvents = $false
        }
        else {
            Unregister-Event -SubscriptionId $item.Id -Force
        }
    }
    $script:FileWatchers = @()
    Write-Log "Alle Watcher gestoppt"
}

# Cleanup
function Stop-Service {
    Write-Log "Stoppe Watcher Service"

    $script:Running = $false

    Stop-Watchers

    if ($script:WebSocketClient) {
        $script:WebSocketClient.Close()
        $script:WebSocketClient = $null
    }

    Stop-Job -Name "WebSocketServer" -Force
    Remove-Job -Name "WebSocketServer" -Force

    Write-Log "Watcher Service gestoppt"
}

# Signal Handler
$job = Start-Job -ScriptBlock {
    param($ScriptRoot)
    while ($true) { Start-Sleep -Seconds 1 }
} -ArgumentList $PSScriptRoot

$job | Wait-Job -Timeout 1

# Hauptprogramm
try {
    Write-Log "Starte Vorce Dashboard Watcher Service"

    # Verzeichnisse erstellen, falls nicht vorhanden
    $watchDirs = $WatchPaths -split ","
    foreach ($dir in $watchDirs) {
        $fullPath = Join-Path $PSScriptRoot "..\$dir"
        if (-not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            Write-Log "Verzeichnis erstellt: $fullPath"
        }
    }

    # WebSocket Verbindung herstellen
    if (-not (Connect-WebSocket)) {
        throw "Konnte keine WebSocket Verbindung herstellen"
    }

    # Watcher starten
    Start-Watchers

    $script:Running = $true
    Write-Log "Watcher Service läuft. Drücke STRG+C zum Beenden"

    # Warte auf Beenden
    [Console]::TreatControlCAsInput = $false
    while ($script:Running) {
        Start-Sleep -Milliseconds 100
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control') {
                Stop-Service
                break
            }
        }
    }
}
catch {
    Write-Log "Fataler Fehler: $_" "ERROR"
    Stop-Service
}
finally {
    Stop-Job -Job $job -Force
    Write-Log "Watcher Service beendet"
}
