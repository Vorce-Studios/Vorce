[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('qwen_reviewer')]
    [string]$Role
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')

function Get-VorceStudiosActiveAssignedIssues {
    param(
        [Parameter(Mandatory)][string]$ApiBaseUrl,
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$AgentId
    )

    $issues = Invoke-RestMethod -Method GET -Uri ('{0}/api/companies/{1}/issues' -f $ApiBaseUrl.TrimEnd('/'), $CompanyId) -ErrorAction Stop
    return @(
        $issues |
            Where-Object {
                [string]$_.assigneeAgentId -eq $AgentId -and
                [string]$_.status -ne 'done' -and
                [string]$_.status -ne 'cancelled'
            }
    )
}

function Get-VorceStudiosBundlePrompt {
    param(
        [Parameter(Mandatory)][string]$InstructionsFile
    )

    $bundleDir = Split-Path -Parent $InstructionsFile
    $content = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @('AGENTS.md', 'SOUL.md', 'GOALS.md', 'SKILLS.md', 'HEARTBEAT.md', 'TOOLS.md')) {
        $path = Join-Path $bundleDir $fileName
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $content.Add(("===== {0} =====" -f $fileName)) | Out-Null
        $content.Add((Get-Content -LiteralPath $path -Raw -ErrorAction Stop).Trim()) | Out-Null
        $content.Add('') | Out-Null
    }

    return ($content -join "`n")
}

$apiBase = [string]$env:PAPERCLIP_API_URL
$companyId = [string]$env:PAPERCLIP_COMPANY_ID
$agentId = [string]$env:PAPERCLIP_AGENT_ID
$instructionsFile = [string]$env:VORCE_STUDIOS_INSTRUCTIONS_FILE

if ([string]::IsNullOrWhiteSpace($apiBase) -or [string]::IsNullOrWhiteSpace($companyId) -or [string]::IsNullOrWhiteSpace($agentId)) {
    throw 'Paperclip-Laufzeitvariablen fehlen fuer den Process-Adapter.'
}

if ([string]::IsNullOrWhiteSpace($instructionsFile) -or -not (Test-Path -LiteralPath $instructionsFile)) {
    $instructionsFile = Join-Path (Get-VorceStudiosPaths).InstructionsDir 'qwen-reviewer.md'
}

$assignedIssues = @(Get-VorceStudiosActiveAssignedIssues -ApiBaseUrl $apiBase -CompanyId $companyId -AgentId $agentId)
if ($assignedIssues.Count -eq 0) {
    Write-Output '[paperclip] No assigned issue for qwen_reviewer. No-op.'
    exit 0
}

$issue = $assignedIssues[0]
$bundlePrompt = Get-VorceStudiosBundlePrompt -InstructionsFile $instructionsFile
$issueDescription = if ($null -eq $issue.description) { '' } else { [string]$issue.description }
$prompt = @"
$bundlePrompt

===== ASSIGNED ISSUE =====
ID: $([string]$issue.id)
Identifier: $([string]$issue.identifier)
Title: $([string]$issue.title)
Status: $([string]$issue.status)
Priority: $([string]$issue.priority)
Description:
$issueDescription

Task:
- Review only this assigned issue scope.
- If there is no concrete diff/PR/evidence inside the issue, report that briefly and stop.
- Findings first. Be precise and concise.
"@

qwen -y -p $prompt
exit $LASTEXITCODE
