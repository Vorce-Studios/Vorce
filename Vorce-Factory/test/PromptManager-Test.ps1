[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHelpers.ps1')

$test = New-VorceTestContext -Name 'PromptManager'
$testVarDir = Join-Path $projectRoot 'var/tmp/test-promptmanager'

if (Test-Path $testVarDir) {
    Remove-Item -LiteralPath $testVarDir -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    $null = New-Item -ItemType Directory -Path (Join-Path $testVarDir 'prompts/shared/snippets') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $testVarDir 'prompts/runs/MAIN-01/SUB-01') -Force

    $global:VarDir = $testVarDir

    . (Join-Path $projectRoot 'src/lib/utils/StatusPrinter.ps1')
    . (Join-Path $projectRoot 'src/lib/utils/PromptManager.ps1')

    Set-Content -LiteralPath (Join-Path $testVarDir 'prompts/shared/snippets/Dashboard-Link-Context.md') -Encoding UTF8 -Value @'
Snippet for dashboard context.
'@

    Set-Content -LiteralPath (Join-Path $testVarDir 'prompts/runs/MAIN-01/SUB-01/PART-01.md') -Encoding UTF8 -Value @'
Prompt body with [[SNIPPET:Dashboard-Link-Context]] and variables:
- repository: {{TARGET_REPOSITORY}}
- approval: ${AUTO_APPROVE}
'@

    Write-Host '=== PromptManager Test ===' -ForegroundColor Cyan

    $snippet = Get-VorcePromptSnippet -SnippetName 'Dashboard-Link-Context'
    Write-VorceTestResult -Context $test -Message 'Snippet laden' -Passed ($snippet -match 'dashboard context')

    $snippets = @(Get-VorcePromptSnippets)
    Write-VorceTestResult -Context $test -Message 'Snippet-Liste enthält Fixture' -Passed ($snippets.Count -eq 1 -and $snippets[0].Name -eq 'Dashboard-Link-Context')

    $replacedContent = Resolve-VorcePromptSnippets -Content 'X [[SNIPPET:Dashboard-Link-Context]] Y'
    Write-VorceTestResult -Context $test -Message 'Snippet-Ersetzung arbeitet' -Passed ($replacedContent -notmatch '\[\[SNIPPET:Dashboard-Link-Context\]\]' -and $replacedContent -match 'dashboard context')

    $prompt = Get-VorcePrompt -PromptId 'TEST' -MainRun 'MAIN-01' -SubRun 'SUB-01' -PartRun 'PART-01' -Variables @{
        TARGET_REPOSITORY = 'Vorce-Studios/Vorce'
        AUTO_APPROVE = $true
    }

    Write-VorceTestResult -Context $test -Message 'Prompt wird generiert' -Passed (-not [string]::IsNullOrWhiteSpace($prompt))
    Write-VorceTestResult -Context $test -Message 'Variablen werden ersetzt' -Passed ($prompt -match 'Vorce-Studios/Vorce' -and $prompt -match 'True')
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path $testVarDir) {
        Remove-Item -LiteralPath $testVarDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
