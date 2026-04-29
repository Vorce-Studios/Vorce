$body = @{
    status = "blocked"
    executionState = "waiting_for_jules_api_key"
} | ConvertTo-Json

Invoke-RestMethod -Uri 'http://127.0.0.1:3100/api/issues/df9e18f9-13b0-445a-ae2d-7b897addca65' -Method Patch -Body $body -ContentType 'application/json'
