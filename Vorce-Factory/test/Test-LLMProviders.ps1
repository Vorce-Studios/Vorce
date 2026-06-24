[CmdletBinding()]
param(
    [switch]$DiscoveryOnly,
    [switch]$DryRun,
    [switch]$FakeCli,
    [switch]$Smoke,
    [switch]$AllowPaidCalls,

    [ValidateRange(1, 600)]
    [int]$SmokeTimeoutSeconds = 60,

    [string]$SmokeResultPath
)

$ErrorActionPreference = 'Stop'

if ($Smoke -and -not $AllowPaidCalls) {
    [Console]::Error.WriteLine(
        'Smoke-Tests erfordern den zusaetzlichen Schalter -AllowPaidCalls.'
    )
    exit 2
}

$explicitFreeMode = $DiscoveryOnly -or $DryRun -or $FakeCli
if (-not $explicitFreeMode -and -not $Smoke) {
    $DiscoveryOnly = $true
    $DryRun = $true
    $FakeCli = $true
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRegistryPath = Join-Path $projectRoot 'var/config/quota-registry.json'
$fakeCliPath = Join-Path $PSScriptRoot 'fixtures/fake-cli/FakeCli.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vorce-provider-tests-" + [guid]::NewGuid().ToString('N'))
$tempConfigDir = Join-Path $tempRoot 'var/config'

if (-not (Test-Path -LiteralPath $sourceRegistryPath)) {
    Write-Error "Provider-Registry fehlt: $sourceRegistryPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $fakeCliPath)) {
    Write-Error "FakeCLI-Fixture fehlt: $fakeCliPath"
    exit 1
}

$hadVorceRoot = Test-Path 'Variable:global:VorceRoot'
$previousVorceRoot = if ($hadVorceRoot) { $global:VorceRoot } else { $null }
$hadVarDir = Test-Path 'Variable:global:VarDir'
$previousVarDir = if ($hadVarDir) { $global:VarDir } else { $null }
$hadLibDir = Test-Path 'Variable:global:LibDir'
$previousLibDir = if ($hadLibDir) { $global:LibDir } else { $null }

$null = New-Item -ItemType Directory -Path $tempConfigDir -Force
Copy-Item -LiteralPath $sourceRegistryPath -Destination (Join-Path $tempConfigDir 'quota-registry.json')

$global:VorceRoot = $projectRoot
$global:VarDir = Join-Path $tempRoot 'var'
$global:LibDir = Join-Path $projectRoot 'src/lib'

. (Join-Path $PSScriptRoot 'TestHelpers.ps1')
. (Join-Path $projectRoot 'src/lib/integrations/AgentRunner.ps1')

$test = New-VorceTestContext -Name 'LLMProviders'
$sourceRegistryHash = (Get-FileHash -LiteralPath $sourceRegistryPath -Algorithm SHA256).Hash
$script:discoveryRows = @()

function Test-ProviderProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    return $null -ne $InputObject -and
        $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-ProviderModelTier {
    param([AllowNull()][object]$Provider)

    if ($null -eq $Provider -or -not $Provider.models) { return 'default' }
    $modelProperties = @($Provider.models.PSObject.Properties)
    if ($modelProperties.Count -eq 0) { return 'default' }
    if ($modelProperties.Name -contains 'default') { return 'default' }
    return [string]$modelProperties[0].Name
}

function Test-ProviderModels {
    param(
        [AllowNull()][object]$Provider,
        [Parameter(Mandatory)][string]$Kind
    )

    if ($Kind -eq 'non_cli') { return $true }
    if ($null -eq $Provider -or -not $Provider.models) { return $false }

    $models = @($Provider.models.PSObject.Properties)
    if ($models.Count -eq 0) { return $false }
    foreach ($model in $models) {
        if ($null -eq $model.Value -or
            -not (Test-ProviderProperty -InputObject $model.Value -Name 'name') -or
            [string]::IsNullOrWhiteSpace([string]$model.Value.name)) {
            return $false
        }
    }
    return $true
}

function Test-ProviderHeadlessFlags {
    param(
        [AllowNull()][object]$Definition,
        [Parameter(Mandatory)][string]$Kind
    )

    if ($Kind -eq 'non_cli') { return $true }
    if ($null -eq $Definition) { return $false }

    $knownFlags = @(
        '-y',
        '--yolo',
        '--print',
        '--trust',
        '--trust-all-tools',
        '--no-interactive',
        '--dangerously-skip-permissions',
        '--dangerously-bypass-approvals-and-sandbox'
    )
    foreach ($argument in @($Definition.cli_args)) {
        if ($knownFlags -contains [string]$argument) { return $true }
    }
    return $false
}

function Test-ProviderArgumentTemplate {
    param(
        [Parameter(Mandatory)][object]$Definition,
        [Parameter(Mandatory)][string]$ModelTier,
        [string]$Prompt = 'Return exactly OK'
    )

    $diagnostics = New-Object System.Collections.Generic.List[string]
    $allowedPlaceholders = @('MODEL', 'PROMPT', 'PROMPT_FILE')
    foreach ($template in @($Definition.cli_args)) {
        foreach ($placeholder in [regex]::Matches([string]$template, '\{([A-Z_]+)\}')) {
            if ($allowedPlaceholders -notcontains $placeholder.Groups[1].Value) {
                $diagnostics.Add("unknown_placeholder:$($placeholder.Groups[1].Value)")
            }
        }
    }

    $transport = if ($Definition.prompt_transport) {
        ([string]$Definition.prompt_transport).ToLowerInvariant()
    } else {
        'argument'
    }
    if ($transport -notin @('argument', 'stdin', 'tempfile')) {
        $diagnostics.Add("invalid_transport:$transport")
    }

    $promptFile = Join-Path $tempRoot 'dry-run-prompt.txt'
    $build = Build-VorceProviderArguments `
        -Definition $Definition `
        -Prompt $Prompt `
        -Transport $transport `
        -PromptFile $promptFile `
        -ModelTier $ModelTier

    if (-not $build.valid) {
        $diagnostics.Add([string]$build.error)
    }
    foreach ($argument in @($build.arguments)) {
        if ([string]$argument -match '\{[A-Z_]+\}') {
            $diagnostics.Add("unresolved_placeholder:$argument")
        }
    }

    return [pscustomobject]@{
        valid = $diagnostics.Count -eq 0
        diagnostics = @($diagnostics.ToArray())
        transport = $transport
        arguments = @($build.arguments)
    }
}

function Get-ProviderDiscoveryRows {
    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry -or $null -eq $registry.providers) {
        return @()
    }

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($property in @($registry.providers.PSObject.Properties)) {
        $providerId = [string]$property.Name
        $provider = $property.Value
        $kind = if ($providerId -eq 'jules') { 'non_cli' } else { 'cli' }
        $enabled = $provider.enabled -eq $true
        # Legacy registries have no optional field. They remain optional until
        # the registry explicitly marks a provider as required with false.
        $optional = if (Test-ProviderProperty -InputObject $provider -Name 'optional') {
            $provider.optional -eq $true
        } else {
            $true
        }
        $modelTier = Get-ProviderModelTier -Provider $provider
        $definition = Get-VorceProviderDefinition -ProviderId $providerId -ModelTier $modelTier
        $command = if ($kind -eq 'cli') { [string]$provider.command } else { $null }
        $commandFound = if ($kind -eq 'non_cli') {
            $true
        } elseif ([string]::IsNullOrWhiteSpace($command)) {
            $false
        } else {
            $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
        }
        $modelsValid = Test-ProviderModels -Provider $provider -Kind $kind
        $argumentCheck = if ($kind -eq 'non_cli') {
            [pscustomobject]@{
                valid = $true
                diagnostics = @()
                transport = 'non_cli'
                arguments = @()
            }
        } elseif ($definition.found) {
            Test-ProviderArgumentTemplate -Definition $definition -ModelTier $modelTier
        } else {
            [pscustomobject]@{
                valid = $false
                diagnostics = @('provider_definition_missing')
                transport = 'argument'
                arguments = @()
            }
        }
        $headlessFlagsPresent = Test-ProviderHeadlessFlags -Definition $definition -Kind $kind

        $status = if ($kind -eq 'non_cli') {
            'non_cli'
        } elseif (-not $enabled) {
            'disabled'
        } elseif (-not $modelsValid) {
            'invalid_models'
        } elseif (-not $argumentCheck.valid) {
            'invalid_args'
        } elseif (-not $headlessFlagsPresent) {
            'headless_flags_missing'
        } elseif (-not $commandFound -and $optional) {
            'command_missing_optional'
        } elseif (-not $commandFound) {
            'command_missing_required'
        } else {
            'ready'
        }

        $rows.Add([pscustomobject][ordered]@{
            provider = $providerId
            kind = $kind
            enabled = $enabled
            optional = $optional
            command = $command
            command_found = $commandFound
            models_valid = $modelsValid
            args_valid = [bool]$argumentCheck.valid
            prompt_transport = [string]$argumentCheck.transport
            headless_flags_present = $headlessFlagsPresent
            discovery_status = $status
            diagnostics = @($argumentCheck.diagnostics)
            model_tier = $modelTier
        })
    }
    return @($rows.ToArray())
}

function New-ProviderDryRun {
    param([Parameter(Mandatory)][object]$DiscoveryRow)

    if ($DiscoveryRow.kind -eq 'non_cli') {
        return [pscustomobject]@{
            provider = $DiscoveryRow.provider
            status = 'non_cli'
            executable = $null
            arguments = @()
            rendered_arguments = ''
        }
    }

    $definition = Get-VorceProviderDefinition `
        -ProviderId $DiscoveryRow.provider `
        -ModelTier $DiscoveryRow.model_tier
    $argumentCheck = Test-ProviderArgumentTemplate `
        -Definition $definition `
        -ModelTier $DiscoveryRow.model_tier
    if (-not $argumentCheck.valid) {
        return [pscustomobject]@{
            provider = $DiscoveryRow.provider
            status = 'invalid_args'
            executable = [string]$definition.command
            arguments = @()
            rendered_arguments = ''
        }
    }

    $command = Get-Command ([string]$definition.command) -ErrorAction SilentlyContinue
    $executable = if ($command) { [string]$command.Source } else { [string]$definition.command }
    $prefixArguments = @()
    if ($command -and
        ($command.CommandType -eq [System.Management.Automation.CommandTypes]::ExternalScript -or
        [System.IO.Path]::GetExtension($command.Source) -eq '.ps1')) {
        $powerShellHost = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $powerShellHost) {
            $powerShellHost = Get-Command powershell -ErrorAction SilentlyContinue
        }
        if ($powerShellHost) {
            $executable = [string]$powerShellHost.Source
            $prefixArguments = @('-NoProfile', '-File', [string]$command.Source)
        }
    }

    $arguments = @($prefixArguments) + @($argumentCheck.arguments)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    Set-VorceProcessArguments -StartInfo $startInfo -Arguments $arguments

    $renderedArguments = if ($startInfo.PSObject.Properties.Name -contains 'ArgumentList') {
        @($startInfo.ArgumentList) -join ' '
    } else {
        [string]$startInfo.Arguments
    }

    return [pscustomobject]@{
        provider = $DiscoveryRow.provider
        status = if ($command) { 'ready' } else { 'command_missing' }
        executable = $executable
        arguments = @($arguments)
        rendered_arguments = $renderedArguments
    }
}

function Set-FakeCliProvider {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [ValidateSet('argument', 'stdin', 'tempfile')]
        [string]$Transport,
        [ValidateSet('success', 'exit', 'timeout')]
        [string]$Mode,
        [Parameter(Mandatory)][string]$CapturePath,
        [string]$StdoutText = 'OK',
        [string]$StderrText = '',
        [int]$ExitCode = 0,
        [int]$SleepMilliseconds = 0
    )

    $registry = Read-VorceQuotaRegistry
    $provider = $registry.providers.$ProviderId
    $arguments = @(
        '-Mode', $Mode,
        '-CapturePath', $CapturePath,
        '-ExitCode', [string]$ExitCode,
        '-SleepMilliseconds', [string]$SleepMilliseconds
    )
    if ([string]::IsNullOrEmpty($StdoutText)) {
        $arguments += '-NoStdout'
    } elseif ($StdoutText -ne 'OK') {
        $arguments += @('-StdoutText', $StdoutText)
    }
    if (-not [string]::IsNullOrEmpty($StderrText)) {
        $arguments += @('-StderrText', $StderrText)
    }
    switch ($Transport) {
        'argument' { $arguments += @('-PromptArgument', '{PROMPT}') }
        'tempfile' { $arguments += @('-PromptFile', '{PROMPT_FILE}') }
    }

    $provider.enabled = $true
    $provider.command = $fakeCliPath
    $provider.cli_args = @($arguments)
    if (Test-ProviderProperty -InputObject $provider -Name 'prompt_transport') {
        $provider.prompt_transport = $Transport
    } else {
        $provider | Add-Member -MemberType NoteProperty -Name prompt_transport -Value $Transport
    }
    if (Test-ProviderProperty -InputObject $provider -Name 'auth_env_var') {
        $provider.auth_env_var = $null
    } else {
        $provider | Add-Member -MemberType NoteProperty -Name auth_env_var -Value $null
    }
    $provider.models = [pscustomobject]@{
        default = [pscustomobject]@{
            name = 'fake-model'
            estimated_cost_per_call_usd = 0
        }
    }
    $provider.daily_limit = 100000
    $provider.daily_budget_usd = $null
    $provider.usage_today = [pscustomobject]@{
        calls = 0
        attempted_calls = 0
        successful_calls = 0
        retryable_failures = 0
        failed_calls = 0
        estimated_cost_usd = 0
    }
    Save-VorceQuotaRegistry -Registry $registry | Out-Null
}

function Read-FakeCliCapture {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-FreeDiscovery {
    $registry = Read-VorceQuotaRegistry
    $providerNames = @($registry.providers.PSObject.Properties.Name)
    $script:discoveryRows = @(Get-ProviderDiscoveryRows)

    Write-Host 'Provider discovery:'
    foreach ($row in $script:discoveryRows) {
        $publicRow = $row | Select-Object `
            provider, kind, enabled, optional, command, command_found, models_valid, `
            args_valid, prompt_transport, headless_flags_present, discovery_status
        Write-Host ($publicRow | ConvertTo-Json -Compress)
    }

    $uniqueNames = @($script:discoveryRows.provider | Sort-Object -Unique)
    Write-VorceTestResult -Context $test -Message 'Alle Registry-Provider erscheinen dynamisch genau einmal' -Passed $(
        $script:discoveryRows.Count -eq $providerNames.Count -and
        $uniqueNames.Count -eq $providerNames.Count -and
        @($providerNames | Where-Object { $uniqueNames -notcontains $_ }).Count -eq 0
    )

    $julesRows = @($script:discoveryRows | Where-Object { $_.provider -eq 'jules' })
    Write-VorceTestResult -Context $test -Message 'Jules ist genau einmal als non_cli klassifiziert' -Passed $(
        $julesRows.Count -eq 1 -and
        $julesRows[0].kind -eq 'non_cli' -and
        $julesRows[0].discovery_status -eq 'non_cli'
    )

    $invalidModels = @($script:discoveryRows | Where-Object {
        $_.kind -eq 'cli' -and $_.enabled -and -not $_.models_valid
    })
    Write-VorceTestResult -Context $test -Message "Provider-Modelle sind valide: $($invalidModels.provider -join ', ')" -Passed $(
        $invalidModels.Count -eq 0
    )

    $invalidArguments = @($script:discoveryRows | Where-Object {
        $_.kind -eq 'cli' -and $_.enabled -and -not $_.args_valid
    })
    Write-VorceTestResult -Context $test -Message "Provider-Argumenttemplates sind valide: $($invalidArguments.provider -join ', ')" -Passed $(
        $invalidArguments.Count -eq 0
    )

    $missingHeadless = @($script:discoveryRows | Where-Object {
        $_.kind -eq 'cli' -and $_.enabled -and -not $_.headless_flags_present
    })
    Write-VorceTestResult -Context $test -Message "Aktive CLI-Provider besitzen Headless-Flags: $($missingHeadless.provider -join ', ')" -Passed $(
        $missingHeadless.Count -eq 0
    )

    $missingRequired = @($script:discoveryRows | Where-Object {
        $_.kind -eq 'cli' -and $_.enabled -and -not $_.optional -and -not $_.command_found
    })
    Write-VorceTestResult -Context $test -Message "Keine erforderlichen Provider-Commands fehlen: $($missingRequired.provider -join ', ')" -Passed $(
        $missingRequired.Count -eq 0
    )
}

function Invoke-FreeDryRun {
    if ($script:discoveryRows.Count -eq 0) {
        $script:discoveryRows = @(Get-ProviderDiscoveryRows)
    }

    $tempRegistryPath = Join-Path $global:VarDir 'config/quota-registry.json'
    $beforeHash = (Get-FileHash -LiteralPath $tempRegistryPath -Algorithm SHA256).Hash
    $dryRuns = @($script:discoveryRows | ForEach-Object { New-ProviderDryRun -DiscoveryRow $_ })

    foreach ($dryRun in $dryRuns) {
        Write-Host ("[DRYRUN] {0}: {1}" -f $dryRun.provider, $dryRun.status)
    }

    $cliRows = @($script:discoveryRows | Where-Object { $_.kind -eq 'cli' })
    $cliDryRuns = @($dryRuns | Where-Object { $_.status -ne 'non_cli' })
    Write-VorceTestResult -Context $test -Message 'DryRun baut jeden CLI-Provider ohne Prozessstart' -Passed $(
        $cliDryRuns.Count -eq $cliRows.Count -and
        @($cliDryRuns | Where-Object { $_.arguments.Count -eq 0 }).Count -eq 0
    )

    $afterHash = (Get-FileHash -LiteralPath $tempRegistryPath -Algorithm SHA256).Hash
    Write-VorceTestResult -Context $test -Message 'DryRun veraendert Registry und Usage nicht' -Passed $(
        $beforeHash -eq $afterHash
    )

    $invalidDefinition = [pscustomobject]@{
        cli_args = @('--prompt', '{BROKEN}')
        prompt_transport = 'argument'
        model = [pscustomobject]@{ name = 'fake-model' }
    }
    $invalidCheck = Test-ProviderArgumentTemplate `
        -Definition $invalidDefinition `
        -ModelTier 'default'
    Write-VorceTestResult -Context $test -Message 'Unbekannte Platzhalter werden klar diagnostiziert' -Passed $(
        -not $invalidCheck.valid -and
        (@($invalidCheck.diagnostics) -join ';') -match 'unknown_placeholder:BROKEN'
    )

    $missingPromptDefinition = [pscustomobject]@{
        cli_args = @('--headless')
        prompt_transport = 'argument'
        model = [pscustomobject]@{ name = 'fake-model' }
    }
    $missingPromptCheck = Test-ProviderArgumentTemplate `
        -Definition $missingPromptDefinition `
        -ModelTier 'default'
    Write-VorceTestResult -Context $test -Message 'Fehlender Prompt-Platzhalter wird durch den Runner-Builder diagnostiziert' -Passed $(
        -not $missingPromptCheck.valid -and
        (@($missingPromptCheck.diagnostics) -join ';') -match '\{PROMPT\}'
    )
}

function Invoke-FakeCliTests {
    if ($script:discoveryRows.Count -eq 0) {
        $script:discoveryRows = @(Get-ProviderDiscoveryRows)
    }
    $fakeProvider = @($script:discoveryRows | Where-Object { $_.kind -eq 'cli' } | Select-Object -First 1)
    if ($fakeProvider.Count -ne 1) {
        Write-VorceTestResult -Context $test -Message 'FakeCLI benoetigt mindestens einen registrierten CLI-Provider' -Passed $false
        return
    }

    $providerId = [string]$fakeProvider[0].provider
    $captureRoot = Join-Path $tempRoot 'captures'
    $runContext = @{
        main_run_id = 'na-13'
        part_run_id = 'fake-cli'
        working_directory = $projectRoot
    }
    $prompt = @'
alpha beta
quote "x"; ampersand & dollar $() backtick ` end
'@

    $argumentCapture = Join-Path $captureRoot 'argument.json'
    Set-FakeCliProvider `
        -ProviderId $providerId `
        -Transport 'argument' `
        -Mode 'success' `
        -CapturePath $argumentCapture `
        -StdoutText 'OK' `
        -StderrText 'fixture-stderr'
    $argumentResult = Invoke-VorceProviderProcess `
        -ProviderId $providerId `
        -Prompt $prompt `
        -ModelTier 'default' `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    $argumentData = Read-FakeCliCapture -Path $argumentCapture
    Write-VorceTestResult -Context $test -Message 'FakeCLI trennt stdout und stderr' -Passed $(
        $argumentResult.success -and
        $argumentResult.output -eq 'OK' -and
        (Get-Content -LiteralPath $argumentResult.stderr_path -Raw -Encoding UTF8) -eq 'fixture-stderr'
    )
    Write-VorceTestResult -Context $test -Message 'FakeCLI bewahrt den Prompt als einzelnes Argument' -Passed $(
        $argumentData.prompt_source -eq 'argument' -and
        $argumentData.prompt -ceq $prompt
    )

    $stdinCapture = Join-Path $captureRoot 'stdin.json'
    Set-FakeCliProvider `
        -ProviderId $providerId `
        -Transport 'stdin' `
        -Mode 'success' `
        -CapturePath $stdinCapture
    $stdinResult = Invoke-VorceProviderProcess `
        -ProviderId $providerId `
        -Prompt $prompt `
        -ModelTier 'default' `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    $stdinData = Read-FakeCliCapture -Path $stdinCapture
    Write-VorceTestResult -Context $test -Message 'FakeCLI bewahrt den Prompt ueber stdin' -Passed $(
        $stdinResult.success -and
        $stdinData.prompt_source -eq 'stdin' -and
        $stdinData.prompt -ceq $prompt
    )

    $tempfileCapture = Join-Path $captureRoot 'tempfile.json'
    Set-FakeCliProvider `
        -ProviderId $providerId `
        -Transport 'tempfile' `
        -Mode 'success' `
        -CapturePath $tempfileCapture
    $tempfileResult = Invoke-VorceProviderProcess `
        -ProviderId $providerId `
        -Prompt $prompt `
        -ModelTier 'default' `
        -RunContext $runContext `
        -ExpectedOutput 'exact'
    $tempfileData = Read-FakeCliCapture -Path $tempfileCapture
    Write-VorceTestResult -Context $test -Message 'FakeCLI liest den Prompt unveraendert aus der Tempdatei' -Passed $(
        $tempfileResult.success -and
        $tempfileData.prompt_source -eq 'tempfile' -and
        $tempfileData.prompt_file_existed -and
        $tempfileData.prompt -ceq $prompt
    )
    Write-VorceTestResult -Context $test -Message 'Runner entfernt die Prompt-Tempdatei nach dem Aufruf' -Passed $(
        -not [string]::IsNullOrWhiteSpace([string]$tempfileData.prompt_file) -and
        -not (Test-Path -LiteralPath ([string]$tempfileData.prompt_file))
    )

    $exitCapture = Join-Path $captureRoot 'exit.json'
    Set-FakeCliProvider `
        -ProviderId $providerId `
        -Transport 'argument' `
        -Mode 'exit' `
        -CapturePath $exitCapture `
        -StdoutText '' `
        -StderrText 'fixture-exit' `
        -ExitCode 23
    $exitResult = Invoke-VorceProviderProcess `
        -ProviderId $providerId `
        -Prompt 'exit prompt' `
        -ModelTier 'default' `
        -RunContext $runContext
    Write-VorceTestResult -Context $test -Message 'FakeCLI propagiert stderr und ExitCode' -Passed $(
        -not $exitResult.success -and
        $exitResult.process_started -and
        $exitResult.exit_code -eq 23 -and
        $exitResult.error_class -eq 'exit_nonzero' -and
        (Get-Content -LiteralPath $exitResult.stderr_path -Raw -Encoding UTF8) -eq 'fixture-exit'
    )

    $timeoutCapture = Join-Path $captureRoot 'timeout.json'
    Set-FakeCliProvider `
        -ProviderId $providerId `
        -Transport 'argument' `
        -Mode 'timeout' `
        -CapturePath $timeoutCapture `
        -StdoutText 'TOO LATE' `
        -SleepMilliseconds 5000
    $timeoutStart = Get-Date
    $timeoutResult = Invoke-VorceProviderProcess `
        -ProviderId $providerId `
        -Prompt 'timeout prompt' `
        -ModelTier 'default' `
        -RunContext $runContext `
        -TimeoutSeconds 1
    $timeoutDuration = ((Get-Date) - $timeoutStart).TotalSeconds
    Write-VorceTestResult -Context $test -Message 'FakeCLI-Timeout beendet den Prozess vor Fixture-Ende' -Passed $(
        $timeoutResult.error_class -eq 'timeout' -and
        $timeoutResult.process_started -and
        (Test-Path -LiteralPath $timeoutCapture) -and
        $timeoutDuration -lt 5
    )
}

function Invoke-SmokeTests {
    if ($script:discoveryRows.Count -eq 0) {
        $script:discoveryRows = @(Get-ProviderDiscoveryRows)
    }

    $candidates = @($script:discoveryRows | Where-Object {
        $_.kind -eq 'cli' -and
        $_.enabled -and
        $_.command_found -and
        $_.models_valid -and
        $_.args_valid
    })
    $summaries = @()
    foreach ($candidate in $candidates) {
        $result = Invoke-VorceProviderProcess `
            -ProviderId $candidate.provider `
            -Prompt 'Return exactly OK' `
            -ModelTier $candidate.model_tier `
            -RunContext @{
                main_run_id = 'na-13'
                part_run_id = 'smoke'
                working_directory = $projectRoot
            } `
            -ExpectedOutput 'exact' `
            -TimeoutSeconds $SmokeTimeoutSeconds

        $summary = [pscustomobject][ordered]@{
            provider = $candidate.provider
            success = [bool]$result.success
            exit_code = [int]$result.exit_code
            duration_ms = [int]$result.duration_ms
            error_class = $result.error_class
            output_hash = $result.output_hash
            summary = $result.summary
        }
        $summaries += $summary
        Write-Host ($summary | ConvertTo-Json -Compress)
        Write-VorceTestResult -Context $test -Message "Smoke: $($candidate.provider)" -Passed ([bool]$result.success)
    }

    $resultPath = $SmokeResultPath
    if ([string]::IsNullOrWhiteSpace($resultPath)) {
        $fileName = "vorce-provider-smoke-{0}-{1}.json" -f `
            (Get-Date -Format 'yyyyMMdd-HHmmss'), `
            ([guid]::NewGuid().ToString('N'))
        $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
    }
    $resultDirectory = Split-Path -Parent $resultPath
    if ($resultDirectory -and -not (Test-Path -LiteralPath $resultDirectory)) {
        $null = New-Item -ItemType Directory -Path $resultDirectory -Force
    }
    ConvertTo-Json -InputObject @($summaries) -Depth 10 |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host "Smoke-Zusammenfassung ohne Rohoutput: $resultPath"
}

try {
    if ($DiscoveryOnly) { Invoke-FreeDiscovery }
    if ($DryRun) { Invoke-FreeDryRun }
    if ($FakeCli) { Invoke-FakeCliTests }
    if ($Smoke) {
        if ($script:discoveryRows.Count -eq 0) { Invoke-FreeDiscovery }
        Invoke-SmokeTests
    }

    $finalSourceHash = (Get-FileHash -LiteralPath $sourceRegistryPath -Algorithm SHA256).Hash
    Write-VorceTestResult -Context $test -Message 'Die Produktions-Registry bleibt unveraendert' -Passed $(
        $sourceRegistryHash -eq $finalSourceHash
    )
} catch {
    Write-VorceTestResult `
        -Context $test `
        -Message "Unerwartete Ausnahme: $($_.Exception.Message)" `
        -Passed $false
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($hadVorceRoot) {
        $global:VorceRoot = $previousVorceRoot
    } else {
        Remove-Variable -Name VorceRoot -Scope Global -ErrorAction SilentlyContinue
    }
    if ($hadVarDir) {
        $global:VarDir = $previousVarDir
    } else {
        Remove-Variable -Name VarDir -Scope Global -ErrorAction SilentlyContinue
    }
    if ($hadLibDir) {
        $global:LibDir = $previousLibDir
    } else {
        Remove-Variable -Name LibDir -Scope Global -ErrorAction SilentlyContinue
    }
}

Complete-VorceTest -Context $test
