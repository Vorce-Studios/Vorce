[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ceo', 'lena_assistant', 'chief_of_staff', 'discovery', 'jules', 'jules_monitor', 'pr_monitor', 'gemini_review', 'qwen_review', 'codex_review', 'ops', 'atlas', 'antigravity')]
    [string]$Role
)

Set-StrictMode -Version Latest

# 1. Capture prompt from stdin
$prompt = $input | Out-String

# 2. Resolve instructions
$instrPath = $env:INSTRUCTION_PATH
if ($instrPath -and (Test-Path $instrPath)) {
    $instructions = Get-Content $instrPath -Raw
    $prompt = "$instructions`n`n---`n`n$prompt"
}

# 3. Determine tool
$tool = 'gemini'
if ($Role -eq 'ceo' -or $Role -eq 'codex_review') {
    $tool = 'codex'
}

# 4. Execute with the Paperclip environment
# We pass -p - to read from stdin
$args = @('-p', '-')

Write-Host "[Vorce-Studios] Invoking $tool for role $Role..." -ForegroundColor Cyan

$prompt | & "$tool.cmd" @args

exit $LASTEXITCODE
