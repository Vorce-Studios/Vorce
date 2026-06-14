# YouTube Authentication Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the OAuth2 authentication module for the YouTube Playlist Creator.

**Architecture:** Use `google-auth-oauthlib` for the Installed App Flow to obtain credentials and `google-api-python-client` to build the YouTube service. The module expects `client_secret.json` in its directory.

**Tech Stack:** Python, google-auth-oauthlib, google-api-python-client.

---

### Task 1: Authentication Module Implementation

**Files:**
- Create: `scripts/youtube_playlist_creator/auth.py`
- Test: `scripts/youtube_playlist_creator/test_auth_stub.py`

- [ ] **Step 1: Create the auth module**

```python
import os
import google_auth_oauthlib.flow
import googleapiclient.discovery
import googleapiclient.errors

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
```

- [ ] **Step 2: Create a stub test to verify imports and basic structure**

```python
import pytest
import os
from scripts.youtube_playlist_creator.auth import SCOPES

def test_scopes():
    assert SCOPES == ["https://www.googleapis.com/auth/youtube.force-ssl"]

def test_file_not_found_error():
    from scripts.youtube_playlist_creator.auth import get_authenticated_service
    # Ensure it raises FileNotFoundError when client_secret.json is missing
    with pytest.raises(FileNotFoundError):
        get_authenticated_service()
```

- [ ] **Step 3: Run the stub test**

Run: `pytest scripts/youtube_playlist_creator/test_auth_stub.py`
Expected: PASS (if dependencies are installed)

- [ ] **Step 4: Commit the changes**

```bash
git add scripts/youtube_playlist_creator/auth.py scripts/youtube_playlist_creator/test_auth_stub.py
git commit -m "feat(youtube_playlist_creator): implement OAuth2 authentication module"
```
