[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-agent-runner-" + [guid]::NewGuid().ToString('N'))
$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $tempRoot 'var'
$global:LibDir = Join-Path $projectRoot 'src/lib'
$configDir = Join-Path $global:VarDir 'config'
$fixtureDir = Join-Path $tempRoot 'fixtures'
$null = New-Item -ItemType Directory -Path $configDir -Force
$null = New-Item -ItemType Directory -Path $fixtureDir -Force

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
$test = New-VorceTestContext -Name 'AgentRunner'

$fakeCliPath = Join-Path $fixtureDir 'FakeCli.ps1'
Set-Content -LiteralPath $fakeCliPath -Encoding UTF8 -Value @'
[CmdletBinding()]
param(
    [string]$Mode = 'success',
    [string]$Capture,
    [string]$PromptValue,
    [string]$PromptFile
)

$prompt = if ($PSBoundParameters.ContainsKey('PromptValue')) {
    $PromptValue
} elseif ($PromptFile) {
    [System.IO.File]::ReadAllText($PromptFile)
} else {
    [Console]::In.ReadToEnd()
}

if ($Capture) {
    [System.IO.File]::WriteAllText($Capture, $prompt, [System.Text.UTF8Encoding]::new($false))
}

switch ($Mode) {
    'success' { [Console]::Out.Write('OK') }
    'json' { [Console]::Out.Write('{"status":"ok","count":1}') }
    'stderr' {
        [Console]::Error.Write('diagnostic-only')
        [Console]::Out.Write('OK')
    }
    'invalidjson' { [Console]::Out.Write('{"status":') }
    'empty' { }
    'exit1' {
        [Console]::Error.Write('generic failure')
        exit 1
    }
    'timeout' {
        Start-Sleep -Seconds 5
        [Console]::Out.Write('TOO LATE')
    }
}
'@

$pwshCommand = (Get-Command pwsh -ErrorAction Stop).Source

function New-TestProvider {
    param(
        [bool]$Enabled = $true,
        [string]$Command = $pwshCommand,
        [string[]]$CliArgs = @(),
        [string]$PromptTransport = 'argument',
        [AllowNull()][string]$AuthEnvVar = $null,
        [int]$DailyLimit = 100,
        [int]$Calls = 0
    )

    return [pscustomobject]@{
        enabled = $Enabled
        command = $Command
        cli_args = @($CliArgs)
        prompt_transport = $PromptTransport
        auth_env_var = $AuthEnvVar
        models = [pscustomobject]@{
            default = [pscustomobject]@{
                name = 'fake-model'
                estimated_cost_per_call_usd = 0
            }
        }
        daily_limit = $DailyLimit
        daily_budget_usd = $null
        usage_today = [pscustomobject]@{
            calls = $Calls
            attempted_calls = 0
            successful_calls = 0
            retryable_failures = 0
            failed_calls = 0
            estimated_cost_usd = 0
        }
    }
}

$captureArgument = Join-Path $fixtureDir 'argument.txt'
$captureStdin = Join-Path $fixtureDir 'stdin.txt'
$captureTempfile = Join-Path $fixtureDir 'tempfile.txt'

$registry = [pscustomobject]@{
    schema_version = 1
    routing_rules = [pscustomobject]@{}
    providers = [pscustomobject]@{
        gemini_cli = New-TestProvider -CliArgs @(
            '-NoProfile', '-File', $fakeCliPath,
            '-Mode', 'success',
            '-Capture', $captureArgument,
            '-PromptValue', '{PROMPT}'
        )
        claude_code = New-TestProvider -PromptTransport 'stdin' -CliArgs @(
            '-NoProfile', '-File', $fakeCliPath,
            '-Mode', 'success',
            '-Capture', $captureStdin
        )
        codex_orchestrator = New-TestProvider -PromptTransport 'tempfile' -CliArgs @(
            '-NoProfile', '-File', $fakeCliPath,
            '-Mode', 'success',
            '-Capture', $captureTempfile,
            '-PromptFile', '{PROMPT_FILE}'
        )
        kiro_cli = New-TestProvider -Command 'vorce-command-does-not-exist' -CliArgs @('{PROMPT}')
        cline_cli = New-TestProvider -Enabled $false -CliArgs @('{PROMPT}')
        copilot_cli = New-TestProvider -AuthEnvVar 'VORCE_TEST_MISSING_AUTH' -CliArgs @('{PROMPT}')
        cursor_agent = New-TestProvider -DailyLimit 1 -Calls 1 -CliArgs @('{PROMPT}')
        jules = [pscustomobject]@{
            enabled = $true
            daily_limit = 100
            usage_today = [pscustomobject]@{
                calls = 0
                attempted_calls = 0
                successful_calls = 0
                retryable_failures = 0
                failed_calls = 0
                estimated_cost_usd = 0
            }
        }
    }
}

function Save-TestRegistry {
    $registryPath = Join-Path $global:VarDir 'config/quota-registry.json'
    $script:registry | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $registryPath -Encoding UTF8
}

function Set-TestProviderMode {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$Capture,
        [ValidateSet('argument', 'stdin', 'tempfile')]
        [string]$Transport = 'argument'
    )

    $provider = $script:registry.providers.$ProviderId
    $provider.prompt_transport = $Transport
    $args = @('-NoProfile', '-File', $fakeCliPath, '-Mode', $Mode, '-Capture', $Capture)
    switch ($Transport) {
        'argument' { $args += @('-PromptValue', '{PROMPT}') }
        'tempfile' { $args += @('-PromptFile', '{PROMPT_FILE}') }
    }
    $provider.cli_args = $args
    Save-TestRegistry
}

Save-TestRegistry
Set-Content -LiteralPath (Join-Path $configDir 'autopilot-config.json') -Encoding UTF8 -Value @'
{
  "fallback": {
    "retry_after_minutes": 1,
    "max_chain_cycles": 3
  }
}
'@
[Environment]::SetEnvironmentVariable('VORCE_TEST_MISSING_AUTH', $null)

. (Join-Path $projectRoot 'src/lib/integrations/AgentRunner.ps1')

try {
    $prompt = "alpha beta`nline two --literal"
    $runContext = @{
        main_run_id = 'main-1'
        part_run_id = 'part-1'
        working_directory = $tempRoot
    }

    $argumentResult = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt $prompt `
        -RunContext $runContext `
        -ExpectedOutput @{ type = 'exact'; value = 'OK' }
    Write-VorceTestResult -Context $test -Message 'Argument-Transport bewahrt Prompt als einzelnes Argument' -Passed $(
        $argumentResult.success -and
        [System.IO.File]::ReadAllText($captureArgument) -ceq $prompt
    )
    Write-VorceTestResult -Context $test -Message 'Artefaktpfad enthaelt main/part/attempt' -Passed $(
        $argumentResult.stdout_path -like "*agent-artifacts*main-1*part-1*$($argumentResult.attempt_id)*stdout.log" -and
        $argumentResult.stderr_path -like "*agent-artifacts*main-1*part-1*$($argumentResult.attempt_id)*stderr.log"
    )

    $registry.providers.gemini_cli.command = $fakeCliPath
    $registry.providers.gemini_cli.cli_args = @(
        '-Mode', 'success',
        '-Capture', $captureArgument,
        '-PromptValue', '{PROMPT}'
    )
    Save-TestRegistry
    $scriptCommandResult = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'direct script fixture' `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    Write-VorceTestResult -Context $test -Message 'Direktes .ps1-Command wird sicher ueber pwsh -File gestartet' -Passed $(
        $scriptCommandResult.success -and
        [System.IO.File]::ReadAllText($captureArgument) -eq 'direct script fixture'
    )
    $registry.providers.gemini_cli.command = $pwshCommand
    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'success' -Capture $captureArgument

    $stdinResult = Invoke-VorceProviderProcess `
        -ProviderId 'claude_code' `
        -Prompt $prompt `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    Write-VorceTestResult -Context $test -Message 'stdin-Transport uebergibt Prompt nicht als Argument' -Passed $(
        $stdinResult.success -and
        [System.IO.File]::ReadAllText($captureStdin) -ceq $prompt
    )

    $tempfileResult = Invoke-VorceProviderProcess `
        -ProviderId 'codex_orchestrator' `
        -Prompt $prompt `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    $tempPromptPath = Join-Path (Split-Path -Parent $tempfileResult.stdout_path) 'prompt.txt'
    Write-VorceTestResult -Context $test -Message 'tempfile-Transport uebergibt Prompt exakt und entfernt Promptdatei' -Passed $(
        $tempfileResult.success -and
        [System.IO.File]::ReadAllText($captureTempfile) -ceq $prompt -and
        -not (Test-Path -LiteralPath $tempPromptPath)
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'stderr' -Capture $captureArgument
    $separated = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'separate streams' `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    Write-VorceTestResult -Context $test -Message 'stdout und stderr bleiben getrennt' -Passed $(
        $separated.success -and
        $separated.output -eq 'OK' -and
        (Get-Content -LiteralPath $separated.stderr_path -Raw) -eq 'diagnostic-only'
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'exit1' -Capture $captureArgument
    $exitFailure = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'exit' `
        -RunContext $runContext
    Write-VorceTestResult -Context $test -Message 'ExitCode 1 wird als exit_nonzero klassifiziert' -Passed $(
        -not $exitFailure.success -and
        $exitFailure.process_started -and
        $exitFailure.exit_code -eq 1 -and
        $exitFailure.error_class -eq 'exit_nonzero' -and
        [string]::IsNullOrEmpty((Get-Content -LiteralPath $exitFailure.stdout_path -Raw)) -and
        (Get-Content -LiteralPath $exitFailure.stderr_path -Raw) -eq 'generic failure'
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'empty' -Capture $captureArgument
    $emptyFailure = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'empty' `
        -RunContext $runContext
    Write-VorceTestResult -Context $test -Message 'Leerer stdout wird als empty_output klassifiziert' -Passed $(
        $emptyFailure.error_class -eq 'empty_output'
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'invalidjson' -Capture $captureArgument
    $invalidJson = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'json' `
        -RunContext $runContext `
        -ExpectedOutput 'json'
    Write-VorceTestResult -Context $test -Message 'Invalides JSON wird als invalid_json klassifiziert' -Passed $(
        $invalidJson.error_class -eq 'invalid_json'
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'timeout' -Capture $captureArgument
    $timeoutStart = Get-Date
    $timeoutFailure = Invoke-VorceProviderProcess `
        -ProviderId 'gemini_cli' `
        -Prompt 'timeout' `
        -RunContext $runContext `
        -TimeoutSeconds 1
    $timeoutDuration = ((Get-Date) - $timeoutStart).TotalSeconds
    Write-VorceTestResult -Context $test -Message 'Timeout beendet den Prozessbaum gezielt' -Passed $(
        $timeoutFailure.error_class -eq 'timeout' -and
        $timeoutFailure.process_started -and
        $timeoutDuration -lt 4
    )

    $beforePreflight = Read-VorceQuotaRegistry
    $disabledBefore = [int]$beforePreflight.providers.cline_cli.usage_today.calls
    $authBefore = [int]$beforePreflight.providers.copilot_cli.usage_today.calls
    $quotaBefore = [int]$beforePreflight.providers.cursor_agent.usage_today.calls
    $julesBefore = [int]$beforePreflight.providers.jules.usage_today.calls

    $disabled = Invoke-VorceProviderProcess -ProviderId 'cline_cli' -Prompt 'x' -RunContext $runContext
    $authMissing = Invoke-VorceProviderProcess -ProviderId 'copilot_cli' -Prompt 'x' -RunContext $runContext
    $quotaExhausted = Invoke-VorceProviderProcess -ProviderId 'cursor_agent' -Prompt 'x' -RunContext $runContext
    $jules = Invoke-VorceProviderProcess -ProviderId 'jules' -Prompt 'x' -RunContext $runContext
    $commandMissing = Invoke-VorceProviderProcess -ProviderId 'kiro_cli' -Prompt 'x' -RunContext $runContext
    $unknown = Invoke-VorceProviderProcess -ProviderId 'hermes_cli' -Prompt 'x' -RunContext $runContext

    Write-VorceTestResult -Context $test -Message 'Disabled/Auth/Quota/Jules/Command/Unknown werden vor Prozessstart getrennt klassifiziert' -Passed $(
        $disabled.error_class -eq 'disabled' -and
        $authMissing.error_class -eq 'auth_missing' -and
        $quotaExhausted.error_class -eq 'quota_exhausted' -and
        $jules.error_class -eq 'unsupported_for_cli' -and
        $commandMissing.error_class -eq 'command_missing' -and
        $unknown.error_class -eq 'unknown_provider' -and
        -not $disabled.process_started -and
        -not $authMissing.process_started -and
        -not $quotaExhausted.process_started -and
        -not $jules.process_started -and
        -not $commandMissing.process_started -and
        -not $unknown.process_started
    )

    $afterPreflight = Read-VorceQuotaRegistry
    Write-VorceTestResult -Context $test -Message 'Usage steigt bei nicht gestarteten Versuchen nicht' -Passed $(
        [int]$afterPreflight.providers.cline_cli.usage_today.calls -eq $disabledBefore -and
        [int]$afterPreflight.providers.copilot_cli.usage_today.calls -eq $authBefore -and
        [int]$afterPreflight.providers.cursor_agent.usage_today.calls -eq $quotaBefore -and
        [int]$afterPreflight.providers.jules.usage_today.calls -eq $julesBefore
    )

    Set-TestProviderMode -ProviderId 'gemini_cli' -Mode 'timeout' -Capture $captureArgument
    Set-TestProviderMode -ProviderId 'claude_code' -Mode 'success' -Capture $captureStdin -Transport 'stdin'
    $chainResult = Invoke-VorceAgentWithFallback `
        -TaskType 'fixture_chain' `
        -Prompt 'fallback prompt' `
        -PreferredChain @('kiro_cli', 'gemini_cli', 'claude_code') `
        -RunContext $runContext `
        -ExpectedOutput 'exact' `
        -TimeoutSeconds 1
    Write-VorceTestResult -Context $test -Message 'Fallback-Chain missing -> timeout -> success bleibt geordnet' -Passed $(
        $chainResult.success -and
        $chainResult.provider -eq 'claude_code' -and
        $chainResult.attempts.Count -eq 3 -and
        $chainResult.attempts[0].error_class -eq 'command_missing' -and
        $chainResult.attempts[1].error_class -eq 'timeout' -and
        $chainResult.attempts[2].success
    )
    $serializedChain = $chainResult | ConvertTo-Json -Depth 20
    Write-VorceTestResult -Context $test -Message 'Fallback-Ergebnis ist ohne selbstreferenzierende Attempts serialisierbar' -Passed $(
        $serializedChain -match '"attempts"' -and $serializedChain.Length -lt 200000
    )

    $usageAfterChain = Read-VorceQuotaRegistry
    Write-VorceTestResult -Context $test -Message 'Usage zaehlt gestartete Erfolge und retryable Fehler getrennt' -Passed $(
        [int]$usageAfterChain.providers.gemini_cli.usage_today.attempted_calls -gt 0 -and
        [int]$usageAfterChain.providers.gemini_cli.usage_today.retryable_failures -gt 0 -and
        [int]$usageAfterChain.providers.claude_code.usage_today.successful_calls -gt 0 -and
        [int]$usageAfterChain.providers.kiro_cli.usage_today.attempted_calls -eq 0
    )

    $waiting = Invoke-VorceAgentWithFallback `
        -TaskType 'fixture_waiting' `
        -Prompt 'wait' `
        -PreferredChain @('kiro_cli', 'cline_cli', 'jules') `
        -RunContext $runContext `
        -ExpectedOutput 'text' `
        -TimeoutSeconds 1
    $retryAfter = [datetimeoffset]::Parse($waiting.retry_after)
    Write-VorceTestResult -Context $test -Message 'Chain-Ende liefert waiting_provider mit Resume-Daten ohne Sleep' -Passed $(
        $waiting.status -eq 'waiting_provider' -and
        $waiting.error_class -eq 'chain_exhausted' -and
        $waiting.resume_required -and
        $waiting.waiting_provider -and
        $retryAfter -gt [datetimeoffset]::Now
    )
} catch {
    Write-VorceTestResult -Context $test -Message "Unerwartete Ausnahme: $($_.Exception.Message)" -Passed $false
} finally {
    [Environment]::SetEnvironmentVariable('VORCE_TEST_MISSING_AUTH', $null)
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
