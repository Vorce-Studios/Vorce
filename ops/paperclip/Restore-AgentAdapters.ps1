$env:PAPERCLIP_API_URL = 'http://127.0.0.1:3141'
$companyId = '8381e429-a2c5-475c-834e-b78d690becfe'

$agentsJson = pnpm dlx "paperclipai@2026.403.0" agent list --company-id $companyId --json
$agents = $agentsJson | ConvertFrom-Json

foreach ($agent in $agents) {
    $adapterType = 'gemini_local'
    $model = 'gemini-2.5-pro'

    if ($agent.name -match 'Qwen') {
        $adapterType = 'opencode_local'
        $model = 'qwen2.5-coder'
    } elseif ($agent.name -match 'Codex' -or $agent.name -match 'CEO') {
        $adapterType = 'codex_local'
        $model = 'gpt-5.3-codex'
    } elseif ($agent.name -match 'Discovery Scout') {
        $model = 'gemini-2.5-flash-lite'
    } elseif ($agent.name -match 'Gemini Reviewer') {
        $model = 'gemini-2.5-flash'
    }

    $command = 'pwsh.exe'
    $shimPath = (Resolve-Path 'ops/paperclip/gemini-shim.ps1').Path

    if ($adapterType -eq 'opencode_local') {
        $command = 'qwen.cmd'
    } elseif ($adapterType -eq 'codex_local') {
        $command = 'codex.cmd'
    }

    $adapterConfig = @{
        model = $model
        command = $command
    }

    if ($adapterType -eq 'gemini_local') {
        $adapterConfig.command = 'pwsh.exe'
        $adapterConfig.args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $shimPath)
    }

    $payload = @{
        adapterType = $adapterType
        adapterConfig = $adapterConfig
    } | ConvertTo-Json -Depth 10

    Write-Host "Restoring $($agent.name) to $adapterType"
    Invoke-RestMethod -Method PATCH -Uri "$($env:PAPERCLIP_API_URL)/api/agents/$($agent.id)" -Body $payload -ContentType "application/json" | Out-Null
}

Write-Host "All agents restored to local adapters."
