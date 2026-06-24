# Test-RunStateSchema.ps1
# Tests für State-Schema 2 Konsolidierung (NA-04)

[CmdletBinding()]
param()

$TestRoot = Join-Path $PSScriptRoot "..\src"
$TestVarDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-state-schema-" + [guid]::NewGuid().ToString('N'))
$global:VarDir = $TestVarDir
$global:LibDir = Join-Path $TestRoot "lib"
$null = New-Item -ItemType Directory -Path $global:VarDir -Force

. (Join-Path $TestRoot "lib\state\StateManager.ps1")
. (Join-Path $PSScriptRoot "TestHelpers.ps1")

$Context = New-VorceTestContext -Name "RunStateSchema"

# Test: MAIN/SUB/PART Parent-IDs
Write-VorceTestResult -Context $Context -Message "MAIN-State hat eigene ID als main_run_id und leere parent_run_id" -Passed $(
    $main = New-VorceRunStateObject -RunName "TestMain" -RunType "MAIN" -MainRunId $null -ParentRunId $null -InputFingerprint "test"
    $main.main_run_id -eq $main.id -and $main.parent_run_id -eq $null
)

Write-VorceTestResult -Context $Context -Message "SUB-State hat main_run_id vom Parent und parent_run_id auf Mother-ID" -Passed $(
    $main = New-VorceRunStateObject -RunName "TestMain" -RunType "MAIN" -MainRunId $null -ParentRunId $null -InputFingerprint "test"
    $main.main_run_id = $main.id
    $sub = New-VorceRunStateObject -RunName "TestSub" -RunType "SUB" -MainRunId $main.id -ParentRunId $main.id -InputFingerprint "test"
    $sub.main_run_id -eq $main.id -and $sub.parent_run_id -eq $main.id
)

Write-VorceTestResult -Context $Context -Message "PART-State hat main_run_id vom MAIN und parent_run_id auf SUB-ID" -Passed $(
    $main = New-VorceRunStateObject -RunName "TestMain" -RunType "MAIN" -MainRunId $null -ParentRunId $null -InputFingerprint "test"
    $main.main_run_id = $main.id
    $sub = New-VorceRunStateObject -RunName "TestSub" -RunType "SUB" -MainRunId $main.id -ParentRunId $main.id -InputFingerprint "test"
    $part = New-VorceRunStateObject -RunName "TestPart" -RunType "PART" -MainRunId $main.id -ParentRunId $sub.id -InputFingerprint "test"
    $part.main_run_id -eq $main.id -and $part.parent_run_id -eq $sub.id
)

# Test: Zusatzfelder bleiben nach Save/Read erhalten
Write-VorceTestResult -Context $Context -Message "Zusatzfelder (resume, execution_graph, attempts, result_ref, result_id, reusable, error, error_class, retry_after, parts) bleiben erhalten" -Passed $(
    $state = New-VorceRunStateObject -RunName "ExtraFields" -RunType "PART" -MainRunId "main123" -ParentRunId "parent456" -InputFingerprint "finger"
    $state.resume = @{ attempt=1 }
    $state.execution_graph = @{ nodes=@("a","b") }
    $state.attempts = @(@{n=1}, @{n=2})
    $state.result_ref = "ref_value"
    $state.result_id = "result_abc"
    $state.reusable = $true
    $state.error = "test_error"
    $state.error_class = "test_class"
    $state.retry_after = 30
    $state.parts = @(@{part="a"})

    $saved = Save-VorceRunState -State $state
    $saved.resume.attempt -eq 1 -and
    $saved.execution_graph.nodes.Count -eq 2 -and
    $saved.attempts.Count -eq 2 -and
    $saved.result_ref -eq "ref_value" -and
    $saved.result_id -eq "result_abc" -and
    $saved.reusable -eq $true -and
    $saved.error -eq "test_error" -and
    $saved.error_class -eq "test_class" -and
    $saved.retry_after -eq 30 -and
    $saved.parts.Count -eq 1
)

# Test: Latest und History haben denselben finalen Status
Write-VorceTestResult -Context $Context -Message "Finaler Status wird in Latest und History synchron geschrieben" -Passed $(
    $state = New-VorceRunStateObject -RunName "FinalState" -RunType "SUB" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $state.status = "completed"
    $saved = Save-VorceRunState -State $state

    $latestPath = Join-Path (Get-VorceRunStatesDir) "SUB_FinalState.json"
    $historyPath = Join-Path (Join-Path (Get-VorceRunHistoryDir) "SUB") "FinalState"
    $historyPath = Join-Path $historyPath "$($state.id).json"

    $latestContent = Get-Content $latestPath -Raw | ConvertFrom-Json
    $historyContent = Get-Content $historyPath -Raw | ConvertFrom-Json

    $latestContent.status -eq "completed" -and $historyContent.status -eq "completed" -and
    $latestContent.id -eq $historyContent.id
)

# Test: laufender History-State wird bis zum finalen Status aktualisiert
Write-VorceTestResult -Context $Context -Message "History wird von running auf final aktualisiert" -Passed $(
    $state = New-VorceRunStateObject -RunName "HistoryTransition" -RunType "PART" -MainRunId "main" -ParentRunId "sub" -InputFingerprint "finger"
    $state = Set-VorceStateRunning -State $state
    Save-VorceRunState -State $state | Out-Null
    $state = Set-VorceStateCompleted -State $state
    Save-VorceRunState -State $state | Out-Null
    $history = Get-Content -LiteralPath (Get-VorceRunHistoryPath -State $state) -Raw | ConvertFrom-Json
    $history.status -eq "completed" -and $history.completed_at
)

# Test: finaler History-State ist immutable
Write-VorceTestResult -Context $Context -Message "Widerspruechliches Ueberschreiben eines finalen States wird verhindert" -Passed $(
    $state = New-VorceRunStateObject -RunName "ImmutableFinal" -RunType "PART" -MainRunId "main" -ParentRunId "sub" -InputFingerprint "finger"
    $state = Set-VorceStateCompleted -State $state
    Save-VorceRunState -State $state | Out-Null
    $state.status = "failed"
    try {
        Save-VorceRunState -State $state | Out-Null
        $false
    } catch {
        $_.Exception.Message -like "Finaler Run-State*"
    }
)

# Test: Null-sicheres run_settings
Write-VorceTestResult -Context $Context -Message "Safe navigation fuer run_settings funktioniert" -Passed $(
    $nullConfigBag = @{ Config = [pscustomobject]@{}; VarDir = $global:VarDir; LibDir = $global:LibDir }
    $subSettings = $nullConfigBag.Config.run_settings.sub_runs.("NonExistent")
    $null -eq $subSettings
)

# Test: Legacy-State wird erkannt, aber nicht als Schema 2 ausgegeben
Write-VorceTestResult -Context $Context -Message "Confirm-VorceStateSchema2 erkennt Schema-2 korrekt" -Passed $(
    $schema2State = New-VorceRunStateObject -RunName "Schema2Test" -RunType "MAIN" -MainRunId $null -ParentRunId $null -InputFingerprint "test"
    $schema2State.schema_version = 2
    (Confirm-VorceStateSchema2 -State $schema2State) -eq $true
)

Write-VorceTestResult -Context $Context -Message "Schema-Version 3 wird nicht als Schema 2 erkannt" -Passed $(
    $schema3State = New-VorceRunStateObject -RunName "Schema3Test" -RunType "MAIN" -MainRunId $null -ParentRunId $null -InputFingerprint "test"
    $schema3State.schema_version = 3
    (Confirm-VorceStateSchema2 -State $schema3State) -eq $false
)

Write-VorceTestResult -Context $Context -Message "Legacy-State ohne schema_version wird nicht als Schema 2 erkannt" -Passed $(
    $legacyState = [pscustomobject]@{ name = "Legacy"; status = "completed" }
    (Confirm-VorceStateSchema2 -State $legacyState) -eq $false
)

# Test: Status-Helper setzen Timestamps und Fehler konsistent
Write-VorceTestResult -Context $Context -Message "Set-VorceStateCompleted setzt completed_at" -Passed $(
    $state = New-VorceRunStateObject -RunName "HelperTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $completed = Set-VorceStateCompleted -State $state
    $null -ne $completed.completed_at -and $completed.duration_ms -ge 0
)

Write-VorceTestResult -Context $Context -Message "Set-VorceStateFailed setzt Fehlerfelder" -Passed $(
    $state = New-VorceRunStateObject -RunName "HelperTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $failed = Set-VorceStateFailed -State $state -Error "Test error" -ErrorClass "TestException"
    $failed.error -eq "Test error" -and $failed.error_class -eq "TestException" -and $failed.status -eq "failed"
)

Write-VorceTestResult -Context $Context -Message "Set-VorceStateWaitingProvider setzt retry_after" -Passed $(
    $state = New-VorceRunStateObject -RunName "HelperTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $waiting = Set-VorceStateWaitingProvider -State $state -RetryAfterSeconds 45
    $waiting.status -eq "waiting_provider" -and ([datetime]$waiting.retry_after) -gt (Get-Date)
)

Write-VorceTestResult -Context $Context -Message "Set-VorceStateReused markiert als reused" -Passed $(
    $state = New-VorceRunStateObject -RunName "HelperTest" -RunType "SUB" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $reuse = Set-VorceStateReused -State $state
    $reuse.status -eq "reused" -and $reuse.reusable -eq $true
)

# Test: Statische Predicate-Helper (NA-04)
Write-VorceTestResult -Context $Context -Message "Test-VorceStateIsCompleted erkennt completed" -Passed $(
    $state = New-VorceRunStateObject -RunName "PredicateTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $completed = Set-VorceStateCompleted -State $state
    (Test-VorceStateIsCompleted -State $completed) -eq $true -and (Test-VorceStateIsFailed -State $completed) -eq $false -and (Test-VorceStateIsSkipped -State $completed) -eq $false
)

Write-VorceTestResult -Context $Context -Message "Test-VorceStateIsFailed erkennt failed" -Passed $(
    $state = New-VorceRunStateObject -RunName "PredicateTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $failed = Set-VorceStateFailed -State $state -Error "err" -ErrorClass "test"
    (Test-VorceStateIsFailed -State $failed) -eq $true -and (Test-VorceStateIsCompleted -State $failed) -eq $false
)

Write-VorceTestResult -Context $Context -Message "Test-VorceStateIsSkipped erkennt skipped" -Passed $(
    $state = New-VorceRunStateObject -RunName "PredicateTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $skipped = Set-VorceStateSkipped -State $state -Reason "test"
    (Test-VorceStateIsSkipped -State $skipped) -eq $true -and (Test-VorceStateIsCompleted -State $skipped) -eq $false
)

Write-VorceTestResult -Context $Context -Message "Test-VorceStateIsWaitingProvider erkennt waiting_provider" -Passed $(
    $state = New-VorceRunStateObject -RunName "PredicateTest" -RunType "PART" -MainRunId "main" -ParentRunId "parent" -InputFingerprint "finger"
    $waiting = Set-VorceStateWaitingProvider -State $state -RetryAfterSeconds 30
    (Test-VorceStateIsWaitingProvider -State $waiting) -eq $true -and (Test-VorceStateIsCompleted -State $waiting) -eq $false
)

Write-VorceTestResult -Context $Context -Message "Get-VorceRunSetting ist null-sicher bei fehlender Config" -Passed $(
    $bag = @{ }
    $result = Get-VorceRunSetting -ConfigBag $bag -Key 'enabled' -Default $false
    $result -eq $false
)

Write-VorceTestResult -Context $Context -Message "Get-VorceRunSetting gibt Default bei fehlendem Key zurueck" -Passed $(
    $config = [pscustomobject]@{ }
    $bag = @{ Config = $config }
    $result = Get-VorceRunSetting -ConfigBag $bag -Key 'timeout' -Default 300
    $result -eq 300
)

Write-VorceTestResult -Context $Context -Message "Get-VorceRunSetting liest vorhandenen Key" -Passed $(
    $config = [pscustomobject]@{ run_settings = [pscustomobject]@{ max_retries = 5 } }
    $bag = @{ Config = $config }
    $result = Get-VorceRunSetting -ConfigBag $bag -Key 'max_retries' -Default 0
    $result -eq 5
)

Write-VorceTestResult -Context $Context -Message "Null-State in Predicate-Helper verursacht keinen Fehler" -Passed $(
    $errorThrown = $false
    try {
        $r1 = Test-VorceStateIsCompleted -State $null
        $r2 = Test-VorceStateIsFailed -State $null
        $r3 = Test-VorceStateIsSkipped -State $null
        $r4 = Test-VorceStateIsWaitingProvider -State $null
        $r1 -eq $false -and $r2 -eq $false -and $r3 -eq $false -and $r4 -eq $false
    } catch { $false }
)

$failed = $Context.FailCount
if (Test-Path -LiteralPath $TestVarDir) {
    Remove-Item -LiteralPath $TestVarDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Ergebnis: $($Context.PassCount)/$($Context.TotalCount) Checks bestanden"
    exit 1
}
Write-Host ""
Write-Host "Ergebnis: $($Context.PassCount)/$($Context.TotalCount) Checks bestanden"
exit 0
