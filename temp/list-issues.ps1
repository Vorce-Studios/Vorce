$r = Invoke-RestMethod -Uri 'http://127.0.0.1:3100/api/issues/df9e18f9-13b0-445a-ae2d-7b897addca65' -Method Get
$r | ConvertTo-Json -Depth 10