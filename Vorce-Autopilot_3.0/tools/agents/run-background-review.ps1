param(
    [Parameter(Mandatory)][int]$PullRequestNumber,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$ReviewPrompt,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$QuotaRegistryPath,
    [Parameter(Mandatory)][string]$SubStatePath,
    [Parameter(Mandatory)][string]$OutputFilePath
)

$ScriptDir = Resolve-Path (Join-Path $PSScriptRoot "../..")

# Load essential modules
. (Join-Path $ScriptDir "src/lib/utils/planning-utils.ps1")
. (Join-Path $ScriptDir "src/lib/state/state-manager.ps1")
. (Join-Path $ScriptDir "src/core/Invoke-MainRun.ps1") # Contains Invoke-PartRun

$Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$QuotaRegistry = Get-Content -LiteralPath $QuotaRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$SubState = Get-Content -LiteralPath $SubStatePath -Raw -Encoding UTF8 | ConvertFrom-Json

$partRunName = "PART-RUN-01_SR-04_MR-02_CheckAndDoing__PRReview-PR-$PullRequestNumber"

try {
    $reviewResult = Invoke-PartRun `
        -PartRunName $partRunName `
        -AgentType "QA-Manager" `
        -Prompt $ReviewPrompt `
        -SubState $SubState `
        -Config $Config `
        -QuotaRegistry $QuotaRegistry

    $resultData = [pscustomobject]@{
        pr_number = $PullRequestNumber
        success = $reviewResult.success
        provider = if (Test-ObjectProperty -Object $reviewResult -Name "provider") { $reviewResult.provider } else { "unknown" }
        output = $reviewResult.output
        completed_at = (Get-Date).ToString('o')
    }

    Write-SafeJson -FilePath $OutputFilePath -Data $resultData
} catch {
    $resultData = [pscustomobject]@{
        pr_number = $PullRequestNumber
        success = $false
        provider = "error"
        output = $_.Exception.Message
        completed_at = (Get-Date).ToString('o')
    }
    Write-SafeJson -FilePath $OutputFilePath -Data $resultData
}
