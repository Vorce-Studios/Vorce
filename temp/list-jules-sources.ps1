Set-StrictMode -Version 1.0
. C:\Users\Vinyl\Desktop\VJMapper\VjMapper\scripts\jules\jules-api.ps1
$apiKey = $env:JULES_API_KEY
Get-JulesSources -ApiKey $apiKey
