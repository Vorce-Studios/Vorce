---
name: youtube-playlist-creator
description: Erstellt automatisch YouTube-Playlists mit ähnlichen Tracks basierend auf einer Quell-URL. Nutzt die YouTube Data API v3 (API-Key für Suche, OAuth2 für Schreibzugriff).
---

# YouTube Smart Playlist Creator

Dieses Skill ermöglicht es, basierend auf einem YouTube-Video oder Set (z.B. ein DJ-Mix), automatisch eine neue Playlist mit musikalisch ähnlichen Titeln im eigenen YouTube-Konto zu erstellen.

## Voraussetzungen

Bevor das Tool genutzt werden kann, müssen folgende Voraussetzungen erfüllt sein:

1.  **YT-API-KEY:** Muss als Windows-Umgebungsvariable gesetzt sein. Wird für die Suche nach ähnlichen Videos verwendet.
2.  **client_secret.json:** Muss im Skill-Ordner unter `scripts/` hinterlegt sein. Wird für den OAuth2-Login benötigt, um Playlists in deinem Konto zu erstellen.
3.  **YouTube Data API v3:** Muss in der Google Cloud Console für das entsprechende Projekt aktiviert sein.

## Funktionsweise

Das Tool folgt einem dreistufigen Prozess:
1.  **Analyse:** Extraktion der Video-ID aus der bereitgestellten URL und Abruf der Metadaten (Titel, Kategorie).
2.  **Ähnlichkeitssuche:** Abfrage der "Related Videos" via YouTube API (Kategorie "Music"). Falls keine direkten Verwandten gefunden werden, erfolgt eine Titelsuche nach ähnlichen Begriffen.
3.  **Playlist-Erstellung:** Automatisierter OAuth2-Login (Browser öffnet sich), Erstellung einer neuen privaten Playlist und Hinzufügen der gefundenen Tracks.

## Verwendung

Führe das Hauptskript im Verzeichnis des Skills aus:

```powershell
python scripts/main.py "<youtube_url>"
```

Beispiel:
```powershell
python scripts/main.py "https://www.youtube.com/watch?v=xZA4QmhS5fw"
```

## Ressourcen

### scripts/
- `main.py`: CLI-Einstiegspunkt.
- `auth.py`: Logik für API-Key und OAuth2-Authentifizierung.
- `youtube_client.py`: API-Wrapper für Suche und Playlist-Aktionen.
- `requirements.txt`: Python-Abhängigkeiten.

### references/
- `design-spec.md`: Technische Dokumentation der Architektur und Filterlogik.
