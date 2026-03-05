# Wir erzwingen UTF-8 fÃ¼r die Ausgabe, damit Umlaute im Log korrekt sind
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "--- MapFlow Orchestrator WÃ¤chter (Offizieller Modus) ---"

# Parameter-Verarbeitung
$Interval = 300
$SessionId = $null

for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Interval") { $Interval = [int]$args[$i+1]; $i++ }
    if ($args[$i] -eq "-SessionId") { $SessionId = $args[$i+1]; $i++ }
}

if ($null -eq $SessionId -or $SessionId -eq "") {
    $SessionId = $env:GEMINI_SESSION_ID
    if ($null -eq $SessionId -or $SessionId -eq "") {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Suche nach Session-ID..."
        try {
            $sessionsText = gemini --list-sessions | Out-String
            if ($sessionsText -match "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})") {
                $matches = [regex]::Matches($sessionsText, "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})")
                $SessionId = $matches[0].Value
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Nutze Session-ID: $SessionId"
            }
        } catch {
            Write-Host "Konnte Sessions nicht auflisten."
        }
    }
}

if ($null -eq $SessionId -or $SessionId -eq "") {
    Write-Host "FEHLER: Keine Session-ID gefunden!"
    exit 1
}

Write-Host "Ziel-Session: $SessionId"
Write-Host "Intervall: $Interval Sekunden"
Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring startet..."

while ($true) {
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] === CHECK START ==="

    $julesStatus = try { jules remote list --session | Out-String } catch { "Fehler Jules" }
    $prStatus = try { gh pr status | Out-String } catch { "Fehler GitHub Status" }
    $openPrs = try { gh pr list --state open | Out-String } catch { "Fehler GitHub List" }

    $msg = @"
[ORCHESTRATOR-HEARTBEAT]
Zeitstempel: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Session-ID: $SessionId

--- JULES REMOTE SESSIONS ---
$julesStatus

--- GITHUB PR STATUS ---
$prStatus

--- OFFENE PULL REQUESTS ---
$openPrs

ANWEISUNG:
Analysiere kurz den Status von Jules und den PRs und gib eine knappe RÃ¼ckmeldung hier im Chat.
"@

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sende Update..."
    
    # Sicherer Versand Ã¼ber temporÃ¤re Datei
    $tempFile = [IO.Path]::Combine($env:TEMP, "gemini_hb_$(Get-Random).txt")
    $msg | Out-File -FilePath $tempFile -Encoding utf8
    
    try {
        # Wir nutzen -r fÃ¼r Resume und -p @file fÃ¼r den Prompt
        # Wir lassen --raw-output weg, um Warnungen zu vermeiden
        $res = & gemini -p "@$tempFile" -r $SessionId --approval-mode yolo 2>&1 | Out-String
        if ($res -match "Loaded cached credentials") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OK: Nachricht erfolgreich injiziert."
        } else {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] INFO: Gemini CLI Antwort:`n$res"
        }
    } catch {
        Write-Host "FEHLER: $_"
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile }
    }

    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Warte $Interval Sekunden..."
    Start-Sleep -Seconds $Interval
}
