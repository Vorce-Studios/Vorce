[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    Split-Path -Parent $PSScriptRoot
} else {
    [System.IO.Path]::GetFullPath($ProjectRoot)
}

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $ProjectRoot 'src/lib/integrations/GitHubClient.ps1')

$test = New-VorceTestContext -Name 'GitHubCommandSafety'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'vorce-github-safety-{0}' -f [guid]::NewGuid().ToString('N')
)

function Assert-SafetyCheck {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [bool]$Condition
    )

    Write-VorceTestResult -Context $test -Message $Message -Passed $Condition
}

function Get-ArgumentAfter {
    param(
        [Parameter(Mandatory)]
        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($index = 0; $index -lt $Arguments.Count - 1; $index++) {
        if ([string]$Arguments[$index] -eq $Name) {
            return [string]$Arguments[$index + 1]
        }
    }
    return $null
}

function Write-TestScript {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

try {
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $hostExecutable = (Get-Process -Id $PID).Path
    $fakeCliDir = Join-Path $tempRoot 'fake-cli'
    $echoScript = Join-Path $fakeCliDir 'echo-arguments.ps1'
    $authScript = Join-Path $fakeCliDir 'auth-failure.ps1'
    $timeoutScript = Join-Path $fakeCliDir 'timeout.ps1'

    Write-TestScript -Path $echoScript -Content @'
[Console]::Error.Write('fixture-stderr')
$encoded = @($args | ForEach-Object {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$_))
})
[Console]::Out.Write(($encoded -join "`n"))
exit 0
'@
    Write-TestScript -Path $authScript -Content @'
[Console]::Error.Write('authentication failed: run gh auth login')
exit 4
'@
    Write-TestScript -Path $timeoutScript -Content @'
Start-Sleep -Seconds 5
[Console]::Out.Write('too-late')
exit 0
'@

    $title = 'Title "quoted"' + [Environment]::NewLine + 'line; & $() `tick'
    $body = 'Body "quoted"' + [Environment]::NewLine + 'line; & $() `tick'
    $repository = 'owner/repo; & $() `repo'
    $commandArguments = @(
        'issue', 'create',
        '--repo', $repository,
        '--title', $title,
        '--body', $body
    )
    $hostPrefix = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $echoScript
    )

    $argumentResult = Invoke-VorceGitHubCommand `
        -Arguments $commandArguments `
        -ExecutablePath $hostExecutable `
        -ArgumentPrefix $hostPrefix `
        -TimeoutSeconds 10 `
        -WorkingDirectory $tempRoot
    $receivedArguments = @($argumentResult.StdOut -split "`r?`n" | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | ForEach-Object {
        [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
    })

    Assert-SafetyCheck 'Fake-CLI liefert getrennten ExitCode/stdout/stderr-Vertrag' (
        $argumentResult.Succeeded -and
        $argumentResult.ExitCode -eq 0 -and
        $argumentResult.StdErr -eq 'fixture-stderr' -and
        -not $argumentResult.TimedOut
    )
    Assert-SafetyCheck 'Repository bleibt genau ein argv-Element' (
        (Get-ArgumentAfter -Arguments $receivedArguments -Name '--repo') -ceq $repository
    )
    Assert-SafetyCheck 'Titel mit Quotes/Newline/Semikolon/&/$()/Backtick bleibt genau ein argv-Element' (
        (Get-ArgumentAfter -Arguments $receivedArguments -Name '--title') -ceq $title
    )
    Assert-SafetyCheck 'Body mit Quotes/Newline/Semikolon/&/$()/Backtick bleibt genau ein argv-Element' (
        (Get-ArgumentAfter -Arguments $receivedArguments -Name '--body') -ceq $body
    )
    Assert-SafetyCheck 'Argumentreihenfolge und Anzahl bleiben unveraendert' (
        $receivedArguments.Count -eq $commandArguments.Count -and
        (@(for ($index = 0; $index -lt $commandArguments.Count; $index++) {
            if ([string]$receivedArguments[$index] -cne [string]$commandArguments[$index]) { $index }
        }).Count -eq 0)
    )

    $missingResult = Invoke-VorceGitHubCommand `
        -Arguments @('--version') `
        -ExecutablePath (Join-Path $tempRoot 'missing-gh.exe') `
        -TimeoutSeconds 2
    Assert-SafetyCheck 'Fehlendes gh wird strukturiert als command_not_found gemeldet' (
        -not $missingResult.Succeeded -and
        -not $missingResult.Started -and
        $null -eq $missingResult.ExitCode -and
        $missingResult.ErrorClass -eq 'command_not_found'
    )

    $authResult = Invoke-VorceGitHubCommand `
        -Arguments @('issue', 'list') `
        -ExecutablePath $hostExecutable `
        -ArgumentPrefix @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $authScript
        ) `
        -TimeoutSeconds 10 `
        -WorkingDirectory $tempRoot
    Assert-SafetyCheck 'Authfehler behaelt ExitCode und stderr und wird klassifiziert' (
        -not $authResult.Succeeded -and
        $authResult.ExitCode -eq 4 -and
        $authResult.StdErr -match 'authentication failed' -and
        $authResult.ErrorClass -eq 'auth_failed'
    )

    $timeoutResult = Invoke-VorceGitHubCommand `
        -Arguments @('issue', 'list') `
        -ExecutablePath $hostExecutable `
        -ArgumentPrefix @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy', 'Bypass',
            '-File', $timeoutScript
        ) `
        -TimeoutSeconds 1 `
        -WorkingDirectory $tempRoot
    Assert-SafetyCheck 'Timeout beendet den Prozess und liefert strukturierten Timeout' (
        -not $timeoutResult.Succeeded -and
        $timeoutResult.Timeout -and
        $timeoutResult.TimedOut -and
        $timeoutResult.ErrorClass -eq 'timeout'
    )

    $ownedFiles = @(
        'src/lib/integrations/GitHubClient.ps1',
        'src/lib/utils/ProjectManager.ps1',
        'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/SUB-RUN-04_MR-01_Planning__Delegation/PART-RUNS/PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations.ps1',
        'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__ReviewDispatch__DispatchReviews.ps1',
        'src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/PART-RUNS/PART-RUN-01_MR-02_CheckAndDoing__JulesRefill__RefillJulesQueue.ps1'
    )
    $unsafeCommands = @()
    $unsafeText = @()
    foreach ($relativePath in $ownedFiles) {
        $path = Join-Path $ProjectRoot $relativePath
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path,
            [ref]$tokens,
            [ref]$parseErrors
        )
        foreach ($commandAst in $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)) {
            if ($commandAst.GetCommandName() -in @('gh', 'gh.exe', 'Invoke-Expression', 'iex')) {
                $unsafeCommands += "${relativePath}:$($commandAst.Extent.StartLineNumber):$($commandAst.GetCommandName())"
            }
        }

        $content = Get-Content -LiteralPath $path -Raw
        if ($content -match '\$ghCommand|(?i)\bcmd(?:\.exe)?\s+/c\b|(?i)\bexecSync\s*\(') {
            $unsafeText += $relativePath
        }
    }
    Assert-SafetyCheck 'Owned Scope enthaelt keinen direkten gh/iex-Aufruf' ($unsafeCommands.Count -eq 0)
    Assert-SafetyCheck 'Owned Scope enthaelt keinen zusammengesetzten gh/cmd/execSync-Shellstring' ($unsafeText.Count -eq 0)

    $delegationScript = Join-Path $ProjectRoot (
        'src/runs/MAIN-RUN-01_Planning/SUB-RUNS/' +
        'SUB-RUN-04_MR-01_Planning__Delegation/PART-RUNS/' +
        'PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations.ps1'
    )
    $delegationRoot = Join-Path $tempRoot 'delegation'
    $fakeLib = Join-Path $delegationRoot 'lib'
    $fakeVar = Join-Path $delegationRoot 'var'
    $proposalDir = Join-Path $fakeVar 'db/proposals'
    $null = New-Item -ItemType Directory -Path $proposalDir -Force

    Write-TestScript -Path (Join-Path $fakeLib 'utils/StatusPrinter.ps1') -Content @'
function Write-VorceStep {
    param([string]$Message, [string]$Status)
}
'@
    Write-TestScript -Path (Join-Path $fakeLib 'engines/QuotaManager.ps1') -Content @'
function Test-VorceQuota {
    param([string]$AgentName)
    return $true
}
function Register-VorceQuotaUsage {
    param([string]$AgentName, [double]$Cost)
    return [pscustomobject]@{ registered = $true }
}
'@
    Write-TestScript -Path (Join-Path $fakeLib 'integrations/GitHubClient.ps1') -Content @'
function Invoke-VorceGitHubCommand {
    param([string[]]$Arguments)
    $global:VorceSafetyCapturedCalls.Add([string[]]@($Arguments))
    if ($global:VorceSafetyJournalPath -and (Test-Path -LiteralPath $global:VorceSafetyJournalPath)) {
        $intentJournal = Get-Content -LiteralPath $global:VorceSafetyJournalPath -Raw | ConvertFrom-Json
        $global:VorceSafetyIntentObserved = @($intentJournal.delegations | Where-Object {
            $_.status -eq 'creating' -and $_.side_effect -eq 'intent_persisted'
        }).Count -eq 1
    }
    return [pscustomobject]@{
        Succeeded = $true
        ExitCode = 0
        StdOut = 'https://github.example/owner/repo/issues/4242'
        StdErr = ''
        TimedOut = $false
        ErrorClass = $null
    }
}
function Get-VorceGitHubCommandDiagnostic {
    param([object]$Result)
    return 'fixture failure'
}
'@

    $proposal = [pscustomobject]@{
        issueId = 'proposal-17'
        issueNumber = 17
        title = $title
        deliberation = $body
    }
    $proposal | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $proposalDir 'proposal_17.json') -Encoding UTF8

    $global:VorceSafetyCapturedCalls = New-Object 'System.Collections.Generic.List[object]'
    $global:VorceSafetyJournalPath = Join-Path $fakeVar 'db/task-journal.json'
    $global:VorceSafetyIntentObserved = $false
    $config = [pscustomobject]@{
        repository = $repository
    }
    $firstGlobalState = [pscustomobject]@{ active_delegations = @() }
    $configBag = @{
        VorceRoot = $ProjectRoot
        VarDir = $fakeVar
        LibDir = $fakeLib
        Config = $config
        GlobalState = $firstGlobalState
        DryRun = $false
    }
    $firstResult = & $delegationScript -ConfigBag $configBag -ParentState ([pscustomobject]@{ results = @() })
    $firstCall = [object[]]$global:VorceSafetyCapturedCalls[0]
    $firstDelegation = @($firstResult.delegations)[0]

    Assert-SafetyCheck 'CreateDelegations uebergibt Repo und Titel als einzelne Argumente' (
        $global:VorceSafetyCapturedCalls.Count -eq 1 -and
        (Get-ArgumentAfter -Arguments $firstCall -Name '--repo') -ceq $repository -and
        (Get-ArgumentAfter -Arguments $firstCall -Name '--title') -ceq "Strategy Task: $title"
    )
    Assert-SafetyCheck 'CreateDelegations uebergibt Body samt Injection-Fixture als einzelnes Argument' (
        (Get-ArgumentAfter -Arguments $firstCall -Name '--body') -match [regex]::Escape('; & $() `tick') -and
        @($firstCall | Where-Object { $_ -eq '--body' }).Count -eq 1
    )
    Assert-SafetyCheck 'Delegation speichert stabilen Idempotency-Key und bestaetigtes Resultat' (
        $firstDelegation.idempotency_key -match '^delegation:v1:[0-9a-f]{64}$' -and
        $firstDelegation.issueUrl -eq 'https://github.example/owner/repo/issues/4242' -and
        $firstDelegation.issueNumber -eq 4242 -and
        $global:VorceSafetyIntentObserved
    )

    $secondGlobalState = [pscustomobject]@{ active_delegations = @() }
    $configBag.GlobalState = $secondGlobalState
    $secondResult = & $delegationScript -ConfigBag $configBag -ParentState ([pscustomobject]@{ results = @() })
    $secondDelegation = @($secondResult.delegations)[0]
    Assert-SafetyCheck 'Duplicate im Task-Journal unterdrueckt zweiten GitHub-Write' (
        $global:VorceSafetyCapturedCalls.Count -eq 1 -and
        $secondDelegation.status -eq 'reused' -and
        $secondDelegation.side_effect -eq 'reused' -and
        $secondDelegation.idempotency_key -eq $firstDelegation.idempotency_key
    )

    $journalPath = Join-Path $fakeVar 'db/task-journal.json'
    Remove-Item -LiteralPath $journalPath -Force
    $resultArtifactDir = Join-Path $fakeVar (
        'run-results/run_fixture/' +
        'PART-RUN-01_MR-01_Planning__Delegation__CreateDelegations'
    )
    $null = New-Item -ItemType Directory -Path $resultArtifactDir -Force
    [pscustomobject]@{
        schema_version = 1
        result_id = 'result_fixture'
        result = $firstResult
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $resultArtifactDir 'result_fixture.json') -Encoding UTF8
    $thirdGlobalState = [pscustomobject]@{ active_delegations = @() }
    $configBag.GlobalState = $thirdGlobalState
    $thirdParentState = [pscustomobject]@{ results = @() }
    $thirdResult = & $delegationScript -ConfigBag $configBag -ParentState $thirdParentState
    $thirdDelegation = @($thirdResult.delegations)[0]
    Assert-SafetyCheck 'Duplicate im persistierten Resultat unterdrueckt GitHub-Write ohne Journal' (
        $global:VorceSafetyCapturedCalls.Count -eq 1 -and
        $thirdDelegation.status -eq 'reused' -and
        $thirdDelegation.issueUrl -eq $firstDelegation.issueUrl
    )
} catch {
    $failureLocation = if ($_.InvocationInfo) { $_.InvocationInfo.PositionMessage } else { '' }
    Write-VorceTestResult `
        -Context $test `
        -Message "Unerwartete Ausnahme: $($_.Exception.Message) $failureLocation" `
        -Passed $false
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name VorceSafetyCapturedCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name VorceSafetyJournalPath -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name VorceSafetyIntentObserved -Scope Global -ErrorAction SilentlyContinue
}

Complete-VorceTest -Context $test
