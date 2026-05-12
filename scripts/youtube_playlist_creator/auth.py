import os
import google.oauth2.credentials
from google.auth.transport.requests import Request
import google_auth_oauthlib.flow
import googleapiclient.discovery
from dotenv import load_dotenv

load_dotenv()

SCOPES = ["https://www.googleapis.com/auth/youtube.force-ssl"]

def get_authenticated_service():
    creds = None
    token_file = os.path.join(os.path.dirname(__file__), "token.json")
    client_secrets_file = os.path.join(os.path.dirname(__file__), "client_secret.json")

    if os.path.exists(token_file):
        creds = google.oauth2.credentials.Credentials.from_authorized_user_file(token_file, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(client_secrets_file):
                raise FileNotFoundError(f"Missing {client_secrets_file}")
            
            flow = google_auth_oauthlib.flow.InstalledAppFlow.from_client_secrets_file(
                client_secrets_file, SCOPES)
            creds = flow.run_local_server(port=0)
        
        with open(token_file, 'w') as token:
            token.write(creds.to_json())

    return googleapiclient.discovery.build("youtube", "v3", credentials=creds)

def get_api_key_service():
    api_key = os.environ.get('YT-API-KEY') or os.environ.get('YT_API_KEY')
    if not api_key:
        return None
    return googleapiclient.discovery.build("youtube", "v3", developerKey=api_key)
