import sys
import re
import os
from auth import get_authenticated_service
from youtube_client import YouTubeClient

def extract_video_id(url):
    # Unterstützt verschiedene YouTube URL Formate
    pattern = r"(?:v=|\/|be\/)([0-9A-Za-z_-]{11}).*"
    match = re.search(pattern, url)
    return match.group(1) if match else None

def main():
    if len(sys.argv) < 2:
        print("Usage: python main.py <youtube_url>")
        return

    url = sys.argv[1]
    video_id = extract_video_id(url)
    if not video_id:
        print("Invalid YouTube URL")
        return

    try:
        print("Initialisiere YouTube Services (OAuth Flow)...")
        # Wir nutzen den OAuth-Service für alles, um API-Key-Probleme zu umgehen
        service = get_authenticated_service()
        client = YouTubeClient(service, service)

        print(f"Lese Video-Infos für {video_id}...")
        video_info = service.videos().list(part="snippet", id=video_id).execute()
        
        if not video_info.get('items'):
            print("Video nicht gefunden.")
            return
            
        source_title = video_info['items'][0]['snippet']['title']

        print(f"Suche ähnliche Tracks für: {source_title}...")
        similar_ids = client.get_related_videos(video_id)

        playlist_title = f"Smart Playlist: {source_title}"
        playlist_id = client.create_playlist(playlist_title, f"Automated discovery based on {url}")
        print(f"Playlist erstellt: https://www.youtube.com/playlist?list={playlist_id}")

        for vid in similar_ids:
            try:
                print(f"Füge hinzu: {vid}")
                client.add_to_playlist(playlist_id, vid)
            except Exception as e:
                print(f"Fehler beim Hinzufügen von {vid}: {e}")

        print("\nFertig! Deine Playlist ist bereit.")
    except Exception as e:
        print(f"Kritischer Fehler: {e}")

if __name__ == "__main__":
    main()
