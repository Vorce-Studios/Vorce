# Test-MainRunResume.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-main-resume-" + [guid]::NewGuid().ToString('N'))
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $tempRoot 'var'
$global:LibDir = Join-Path $projectRoot 'src/lib'
$null = New-Item -ItemType Directory -Path $global:VarDir -Force
$fixtureDir = Join-Path $tempRoot 'fixtures'
$null = New-Item -ItemType Directory -Path $fixtureDir -Force

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $global:LibDir 'utils/StatusPrinter.ps1')
. (Join-Path $global:LibDir 'state/StateManager.ps1')
. (Join-Path $global:LibDir 'engines/RunEngine.ps1')

$test = New-VorceTestContext -Name 'MainRunResume'

$normalFixture = Join-Path $fixtureDir 'NormalPart.ps1'
Set-Content -LiteralPath $normalFixture -Encoding UTF8 -Value @'
param(
    [hashtable]$ConfigBag,
    [object]$ParentState,
    [string]$CounterPath,
    [string]$Label
)
$count = if (Test-Path -LiteralPath $CounterPath) { [int](Get-Content -LiteralPath $CounterPath -Raw) } else { 0 }
Set-Content -LiteralPath $CounterPath -Value ($count + 1) -Encoding ASCII
[pscustomobject]@{ status = 'ok'; label = $Label; value = $count + 1 }
'@

$providerFixture = Join-Path $fixtureDir 'ProviderPart.ps1'
Set-Content -LiteralPath $providerFixture -Encoding UTF8 -Value @'
param(
    [hashtable]$ConfigBag,
    [object]$ParentState,
    [string]$CounterPath
)
$count = if (Test-Path -LiteralPath $CounterPath) { [int](Get-Content -LiteralPath $CounterPath -Raw) } else { 0 }
$count++
Set-Content -LiteralPath $CounterPath -Value $count -Encoding ASCII
if ($count -eq 1) {
    [pscustomobject]@{
        status = 'waiting_provider'
        error = 'provider unavailable'
        error_class = 'chain_exhausted'
        retry_after = (Get-Date).AddSeconds(-1).ToString('o')
        attempts = @([pscustomobject]@{ attempt_id = 'provider-a'; provider = 'a'; error_class = 'timeout' })
    }
} else {
    [pscustomobject]@{
        status = 'ok'
        summary = 'fallback succeeded'
        attempts = @([pscustomobject]@{ attempt_id = 'provider-b'; provider = 'b'; success = $true })
    }
}
'@

function Read-Counter {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return [int](Get-Content -LiteralPath $Path -Raw) }
    return 0
}

try {
    $main = New-VorceRunStateObject -RunName 'MAIN-RUN-ResumeFixture' -RunType 'MAIN'
    $main = Set-VorceStateRunning -State $main
    Save-VorceRunState -State $main | Out-Null

    $counter1 = Join-Path $tempRoot 'part1.count'
    $counter2 = Join-Path $tempRoot 'part2.count'
    $counter3 = Join-Path $tempRoot 'part3.count'
    $configBag = @{ Config = [pscustomobject]@{} }
    $parts = @(
        @{ name = 'Part1'; script = $normalFixture; input_fingerprint = 'fp-1'; arguments = @{ CounterPath = $counter1; Label = 'one' } },
        @{ name = 'Part2'; script = $normalFixture; input_fingerprint = 'fp-2'; dependency_result_ids = @('dep-1'); arguments = @{ CounterPath = $counter2; Label = 'two' } },
        @{ name = 'Part3'; script = $providerFixture; input_fingerprint = 'fp-3'; dependency_result_ids = @('dep-2'); arguments = @{ CounterPath = $counter3 } }
    )

    $first = Invoke-VorceSubRunSequential -SubRunName 'ResumeSub' -PartRuns $parts -ConfigBag $configBag -ParentState $main
    Write-VorceTestResult -Context $test -Message 'Erster Lauf stoppt als waiting_provider' -Passed ($first.status -eq 'waiting_provider')
    Write-VorceTestResult -Context $test -Message 'Alle drei Parts wurden im ersten Lauf genau einmal versucht' -Passed ((Read-Counter $counter1) -eq 1 -and (Read-Counter $counter2) -eq 1 -and (Read-Counter $counter3) -eq 1)

    $checkpoint = Set-VorceStateWaitingProvider -State $main -RetryAfter (Get-Date).AddSeconds(-1).ToString('o') -BlockedPartRun 'Part3'
    $checkpoint.results = @($first)
    Save-VorceRunState -State $checkpoint | Out-Null
    $rehydrated = Get-VorceResumableMainRun
    Write-VorceTestResult -Context $test -Message 'Unfertiger MAIN wird mit derselben ID wiedergefunden' -Passed ($rehydrated.id -eq $main.id)

    $second = Invoke-VorceSubRunSequential -SubRunName 'ResumeSub' -PartRuns $parts -ConfigBag $configBag -ParentState $rehydrated
    Write-VorceTestResult -Context $test -Message 'Resume endet completed' -Passed ($second.status -eq 'completed')
    Write-VorceTestResult -Context $test -Message 'Fertige Parts 1 und 2 werden nicht erneut ausgefuehrt' -Passed ((Read-Counter $counter1) -eq 1 -and (Read-Counter $counter2) -eq 1)
    Write-VorceTestResult -Context $test -Message 'Blockierter Part wird genau ein zweites Mal ausgefuehrt' -Passed ((Read-Counter $counter3) -eq 2)
    Write-VorceTestResult -Context $test -Message 'Reused Parts werden im Aggregat markiert' -Passed ($second.parts[0].status -eq 'reused' -and $second.parts[1].status -eq 'reused')
    Write-VorceTestResult -Context $test -Message 'Provider-Part behaelt beide Attempts' -Passed (@($second.parts[2].attempts).Count -eq 2)

    $changedPart = Invoke-VorcePartRun -PartName 'Part2' -ScriptPath $normalFixture -ParentState ([pscustomobject]@{
        id = 'sub-changed'; main_run_id = $main.id
    }) -Arguments @{ CounterPath = $counter2; Label = 'two' } -InputFingerprint 'fp-2-changed' -DependencyResultIds @('dep-1')
    Write-VorceTestResult -Context $test -Message 'Geaenderter Fingerprint invalidiert Reuse' -Passed ($changedPart.status -eq 'completed' -and (Read-Counter $counter2) -eq 2)

    $part1Ref = [string]$second.parts[0].result_ref
    Remove-Item -LiteralPath (Join-Path $global:VarDir $part1Ref) -Force
    Write-VorceTestResult -Context $test -Message 'Geloeschtes Result-Artefakt wird zentral als fehlend erkannt' -Passed (-not (Test-VorceRunResultArtifact -ResultRef $part1Ref))
    $missingArtifactPart = Invoke-VorcePartRun -PartName 'Part1' -ScriptPath $normalFixture -ParentState ([pscustomobject]@{
        id = 'sub-artifact'; main_run_id = $main.id
    }) -Arguments @{ CounterPath = $counter1; Label = 'one' } -InputFingerprint 'fp-1'
    Write-VorceTestResult -Context $test -Message 'Fehlendes Result-Artefakt verhindert Reuse' -Passed ($missingArtifactPart.status -eq 'completed' -and (Read-Counter $counter1) -eq 2)

    $sideEffectCounter = Join-Path $tempRoot 'side-effect.count'
    $action = {
        $count = if (Test-Path $sideEffectCounter) { [int](Get-Content $sideEffectCounter -Raw) } else { 0 }
        Set-Content -LiteralPath $sideEffectCounter -Value ($count + 1) -Encoding ASCII
        [pscustomobject]@{ created = $true }
    }
    $null = Invoke-VorceIdempotentAction -IdempotencyKey 'fixture:issue:42' -Action $action
    $null = Invoke-VorceIdempotentAction -IdempotencyKey 'fixture:issue:42' -Action $action
    Write-VorceTestResult -Context $test -Message 'Idempotenter Side Effect wird genau einmal ausgefuehrt' -Passed ((Read-Counter $sideEffectCounter) -eq 1)
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
