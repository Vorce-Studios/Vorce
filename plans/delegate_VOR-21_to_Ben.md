# Plan to delegate VOR-21 to Ben

This plan is to be executed when the Paperclip API is back online.

## Action

Create a subtask for Ben to analyze the repository and break down the roadmap.

## Command (PowerShell)

```powershell
$payloadObject = @{
    title = "Roadmap-Analyse und Zerlegung"
    description = "Bitte analysiere das Repository und zerlege die kurzfristige Roadmap in umsetzbare technische Schritte."
    assigneeAgentId = "1cbda117-0f42-4558-b6d9-793e3782a5dc"
    parentId = "VOR-21"
}
$payloadJson = $payloadObject | ConvertTo-Json -Depth 3
curl.exe -s -X POST -H "Authorization: Bearer $env:PAPERCLIP_API_KEY" -H "Content-Type: application/json" -H "X-Paperclip-Run-Id: $env:PAPERCLIP_RUN_ID" -d $payloadJson "$env:PAPERCLIP_API_URL/api/companies/$env:PAPERCLIP_COMPANY_ID/issues"
```
