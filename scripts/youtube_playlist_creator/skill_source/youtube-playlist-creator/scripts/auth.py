import os
from dotenv import load_dotenv
import google_auth_oauthlib.flow
import googleapiclient.discovery
import googleapiclient.errors

# Lade .env Datei falls vorhanden
load_dotenv()

SCOPES = ["https://www.googleapis.com/auth/youtube.force-ssl"]

def get_authenticated_service():
    """
    Starts the OAuth2 flow and returns an authenticated YouTube service object.
    Expects client_secret.json in the same directory.
    """
    client_secrets_file = os.path.join(os.path.dirname(__file__), "client_secret.json")
    if not os.path.exists(client_secrets_file):
        raise FileNotFoundError(f"Missing {client_secrets_file}. Bitte erstelle diese in der Google Cloud Console.")
        
    flow = google_auth_oauthlib.flow.InstalledAppFlow.from_client_secrets_file(
        client_secrets_file, SCOPES)
    credentials = flow.run_local_server(port=0)
    return googleapiclient.discovery.build("youtube", "v3", credentials=credentials)

def get_api_key_service():
    """
    Returns a YouTube service object using an API Key from environment variables.
    Checks for 'YT-API-KEY' and 'YT_API_KEY'.
    """
    api_key = os.environ.get('YT-API-KEY') or os.environ.get('YT_API_KEY')
    
    if not api_key:
        print("ERROR: Die Umgebungsvariable 'YT-API-KEY' oder 'YT_API_KEY' fehlt.")
        print("Tipp: Wenn du sie gerade erst in Windows gesetzt hast, starte Gemini CLI neu.")
        raise ValueError("Missing environment variable 'YT-API-KEY'")
        
    return googleapiclient.discovery.build("youtube", "v3", developerKey=api_key)
