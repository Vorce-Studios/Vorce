# AgentRunner.ps1 (Vorce 3.0)
# Registry-getriebene Provider-Ausfuehrung mit Fallback.

foreach ($dependency in @(
    (Join-Path $PSScriptRoot 'ProviderRegistry.ps1')
    (Join-Path $PSScriptRoot 'AgentResultValidator.ps1')
    (Join-Path $PSScriptRoot '..\engines\QuotaManager.ps1')
)) {
    . $dependency
}

function Get-VorceProviderDefinition {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [string]$ModelTier = 'default'
    )

    $resolved = Resolve-VorceProviderId -ProviderName $ProviderId
    if ($resolved -isnot [string]) {
        return [pscustomobject]@{
            found = $false
            provider_id = $null
            requested_provider = $ProviderId
            error_class = 'unknown_provider'
        }
    }

    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry -or $null -eq $registry.providers -or
        $registry.providers.PSObject.Properties.Name -notcontains $resolved) {
        return [pscustomobject]@{
            found = $false
            provider_id = $resolved
            requested_provider = $ProviderId
            error_class = 'unknown_provider'
        }
    }

    $provider = $registry.providers.$resolved
    $model = $null
    if ($provider.models -and $provider.models.PSObject.Properties.Name -contains $ModelTier) {
        $model = $provider.models.$ModelTier
    } elseif ($provider.models -and $provider.models.PSObject.Properties.Count -gt 0) {
        $model = ($provider.models.PSObject.Properties | Select-Object -First 1).Value
    }

    return [pscustomobject]@{
        found = $true
        provider_id = $resolved
        requested_provider = $ProviderId
        provider = $provider
        model = $model
        command = $provider.command
        cli_args = @($provider.cli_args)
        auth_env_var = $provider.auth_env_var
        enabled = $provider.enabled -eq $true
        prompt_transport = if ($provider.prompt_transport) {
            ([string]$provider.prompt_transport).ToLowerInvariant()
        } else {
            'argument'
        }
    }
}

function Get-VorceProviderChain {
    param(
        [string[]]$PreferredChain,
        [string]$TaskType,
        [string[]]$DefaultChain,
        [hashtable]$RunContext = @{}
    )

    $registry = Read-VorceQuotaRegistry
    $routing = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($PreferredChain)) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) { $routing.Add([string]$entry) }
    }
    if ($registry -and $registry.routing_rules -and $TaskType -and
        $registry.routing_rules.PSObject.Properties.Name -contains $TaskType) {
        foreach ($entry in @($registry.routing_rules.$TaskType)) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) { $routing.Add([string]$entry) }
        }
    }

    $configPath = Join-Path $global:VarDir 'config/autopilot-config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $partName = if ($RunContext.part_run_name) {
                [string]$RunContext.part_run_name
            } elseif ($RunContext.task_name) {
                [string]$RunContext.task_name
            } else {
                $null
            }
            if ($partName -and $config.run_settings -and $config.run_settings.part_runs -and
                $config.run_settings.part_runs.PSObject.Properties.Name -contains $partName) {
                foreach ($entry in @($config.run_settings.part_runs.$partName.llm_chain)) {
                    if (-not [string]::IsNullOrWhiteSpace($entry)) { $routing.Add([string]$entry) }
                }
            }
        } catch {
            # Eine unlesbare optionale Routing-Config darf PreferredChain nicht blockieren.
        }
    }

    foreach ($entry in @($DefaultChain)) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) { $routing.Add([string]$entry) }
    }
    if ($routing.Count -eq 0 -and $registry -and $registry.providers) {
        foreach ($property in $registry.providers.PSObject.Properties) {
            if ($property.Name -ne 'jules' -and $property.Value.enabled -eq $true -and $property.Value.command) {
                $routing.Add($property.Name)
            }
        }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $routing) {
        $candidate = $entry.Trim()
        $modelTier = $null
        if ($candidate -match '^([^:]+):([^:]+)$') {
            $candidate = $Matches[1]
            $modelTier = $Matches[2]
        }
        $resolved = Resolve-VorceProviderId -ProviderName $candidate
        $providerId = if ($resolved -is [string]) { $resolved } else { $candidate.ToLowerInvariant() }
        $token = if ($modelTier) { "$providerId`:$modelTier" } else { $providerId }
        if ($seen.Add($token)) { $normalized.Add($token) }
    }
    return @($normalized)
}

function Get-VorceSafeArtifactSegment {
    param(
        [AllowNull()][string]$Value,
        [Parameter(Mandatory)][string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Fallback }
    $safe = $Value -replace '[^A-Za-z0-9._-]', '_'
    if ([string]::IsNullOrWhiteSpace($safe)) { return $Fallback }
    return $safe
}

function Get-VorceAgentArtifactRoot {
    param(
        [hashtable]$RunContext,
        [Parameter(Mandatory)][string]$AttemptId
    )

    $mainRunId = Get-VorceSafeArtifactSegment -Value ([string]$RunContext.main_run_id) -Fallback 'main'
    $partRunValue = if ($RunContext.part_run_id) {
        [string]$RunContext.part_run_id
    } elseif ($RunContext.part_run_name) {
        [string]$RunContext.part_run_name
    } elseif ($RunContext.task_name) {
        [string]$RunContext.task_name
    } else {
        $null
    }
    $partRunId = Get-VorceSafeArtifactSegment -Value $partRunValue -Fallback 'part'
    return Join-Path $global:VarDir "tmp/agent-artifacts/$mainRunId/$partRunId/$AttemptId"
}

function Get-VorceModelName {
    param(
        [AllowNull()][object]$Definition,
        [string]$ModelTier
    )

    if ($Definition -and $Definition.model -and $Definition.model.name) {
        return [string]$Definition.model.name
    }
    return $ModelTier
}

function New-VorceAgentAttemptResult {
    param(
        [bool]$Success = $false,
        [AllowNull()][string]$Provider,
        [AllowNull()][string]$RequestedProvider,
        [string]$ModelTier = 'default',
        [AllowNull()][string]$Model,
        [Parameter(Mandatory)][string]$AttemptId,
        [int]$ExitCode = -1,
        [int]$DurationMs = 0,
        [AllowNull()][string]$Output = '',
        [AllowNull()][object]$Payload,
        [AllowNull()][string]$Summary = '',
        [AllowNull()][string]$OutputHash,
        [AllowNull()][string]$StdoutPath,
        [AllowNull()][string]$StderrPath,
        [AllowNull()][string]$ErrorClass,
        [AllowNull()][string]$Error,
        [bool]$Retryable = $false,
        [bool]$FallbackRecommended = $true,
        [bool]$ProcessStarted = $false,
        [AllowNull()][string]$NonErrorClass,
        [bool]$WrapperDetected = $false
    )

    return [pscustomobject]@{
        success = $Success
        status = if ($Success) { 'completed' } else { 'failed' }
        provider = $Provider
        requested_provider = $RequestedProvider
        model_tier = $ModelTier
        model = $Model
        attempt_id = $AttemptId
        process_started = $ProcessStarted
        exit_code = $ExitCode
        duration_ms = $DurationMs
        output = $Output
        payload = $Payload
        summary = $Summary
        output_hash = $OutputHash
        stdout_path = $StdoutPath
        stderr_path = $StderrPath
        error = $Error
        error_class = $ErrorClass
        retryable = $Retryable
        fallback_recommended = $FallbackRecommended
        non_error_class = $NonErrorClass
        wrapper_detected = $WrapperDetected
    }
}

function New-VorcePreflightFailure {
    param(
        [Parameter(Mandatory)][string]$ErrorClass,
        [AllowNull()][string]$Provider,
        [Parameter(Mandatory)][string]$RequestedProvider,
        [string]$ModelTier = 'default',
        [AllowNull()][string]$Model,
        [Parameter(Mandatory)][string]$AttemptId,
        [AllowNull()][string]$Error
    )

    $policy = Get-VorceAgentFailurePolicy -ErrorClass $ErrorClass
    return New-VorceAgentAttemptResult `
        -Provider $Provider `
        -RequestedProvider $RequestedProvider `
        -ModelTier $ModelTier `
        -Model $Model `
        -AttemptId $AttemptId `
        -ErrorClass $policy.error_class `
        -Error $Error `
        -Retryable $policy.retryable `
        -FallbackRecommended $policy.fallback_recommended
}

function Get-VorcePromptTransport {
    param(
        [Parameter(Mandatory)][object]$Definition,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$RequestedTransport = 'auto',
        [int]$LongPromptThreshold = 6000
    )

    if ($RequestedTransport -ne 'auto') { return $RequestedTransport.ToLowerInvariant() }
    if ($Prompt.Length -gt $LongPromptThreshold) {
        if ($Definition.prompt_transport -eq 'tempfile') { return 'tempfile' }
        return 'stdin'
    }
    return $Definition.prompt_transport
}

function Build-VorceProviderArguments {
    param(
        [Parameter(Mandatory)][object]$Definition,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Transport,
        [AllowNull()][string]$PromptFile,
        [string]$ModelTier = 'default'
    )

    $modelName = Get-VorceModelName -Definition $Definition -ModelTier $ModelTier
    $hasPromptPlaceholder = $false
    $hasPromptFilePlaceholder = $false
    $argumentList = New-Object System.Collections.Generic.List[string]
    foreach ($template in @($Definition.cli_args)) {
        $value = [string]$template
        if ($Transport -ne 'argument' -and $value -eq '{PROMPT}') {
            $hasPromptPlaceholder = $true
            if ($argumentList.Count -gt 0 -and
                $argumentList[$argumentList.Count - 1] -match '^(?:-p|--prompt|--message|--input)$') {
                $argumentList.RemoveAt($argumentList.Count - 1)
            }
            continue
        }
        if ($value.Contains('{MODEL}')) {
            $value = $value.Replace('{MODEL}', $modelName)
        }

        if ($value.Contains('{PROMPT_FILE}')) {
            $hasPromptFilePlaceholder = $true
            if ($Transport -eq 'tempfile') {
                $value = $value.Replace('{PROMPT_FILE}', $PromptFile)
            } else {
                $value = $value.Replace('{PROMPT_FILE}', '')
            }
        }
        if ($value.Contains('{PROMPT}')) {
            $hasPromptPlaceholder = $true
            if ($Transport -eq 'argument') {
                $value = $value.Replace('{PROMPT}', $Prompt)
            } else {
                $value = $value.Replace('{PROMPT}', '')
            }
        }

        if (-not [string]::IsNullOrEmpty($value)) {
            $argumentList.Add($value)
        }
    }

    if ($Transport -eq 'argument' -and -not $hasPromptPlaceholder) {
        return [pscustomobject]@{
            valid = $false
            error = "Argument-Transport benoetigt den Platzhalter {PROMPT}."
            arguments = @()
        }
    }
    if ($Transport -eq 'tempfile' -and -not $hasPromptFilePlaceholder) {
        return [pscustomobject]@{
            valid = $false
            error = "Tempfile-Transport benoetigt den Platzhalter {PROMPT_FILE}."
            arguments = @()
        }
    }

    return [pscustomobject]@{
        valid = $true
        error = $null
        arguments = @($argumentList)
    }
}

function ConvertTo-VorceProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }

    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * (($backslashes * 2) + 1)))
            $null = $builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            $null = $builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) {
        $null = $builder.Append(('\' * ($backslashes * 2)))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Set-VorceProcessArguments {
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    if ($StartInfo.PSObject.Properties.Name -contains 'ArgumentList') {
        foreach ($argument in $Arguments) {
            $StartInfo.ArgumentList.Add([string]$argument)
        }
        return
    }

    $StartInfo.Arguments = (@($Arguments | ForEach-Object {
        ConvertTo-VorceProcessArgument -Argument ([string]$_)
    }) -join ' ')
}

function Test-VorceWindowsPlatform {
    return $env:OS -eq 'Windows_NT'
}

function Stop-VorceProcessTree {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

    if ((Test-VorceWindowsPlatform) -and -not $Process.HasExited) {
        try {
            $taskkill = Get-Command taskkill.exe -ErrorAction SilentlyContinue
            if ($taskkill) {
                & $taskkill.Source /PID $Process.Id /T /F 2>$null | Out-Null
                $Process.WaitForExit()
                return
            }
        } catch {
            # Einzelprozess-Fallback folgt.
        }
    }
    try {
        if (-not $Process.HasExited) { $Process.Kill() }
        $Process.WaitForExit()
    } catch {
        # Der Versuch bleibt als Timeout klassifiziert.
    }
}

function Invoke-VorceProviderProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelTier = 'default',
        [hashtable]$RunContext = @{},
        [object]$ExpectedOutput = 'text',
        [int]$TimeoutSeconds = 120,
        [ValidateSet('auto', 'argument', 'stdin', 'tempfile')]
        [string]$PromptTransport = 'auto'
    )

    $attemptId = [guid]::NewGuid().ToString('N')
    $definition = Get-VorceProviderDefinition -ProviderId $ProviderId -ModelTier $ModelTier
    if (-not $definition.found) {
        return New-VorcePreflightFailure `
            -ErrorClass 'unknown_provider' `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -AttemptId $attemptId `
            -Error "Provider '$ProviderId' ist nicht registriert."
    }

    $modelName = Get-VorceModelName -Definition $definition -ModelTier $ModelTier
    if ($definition.provider_id -eq 'jules') {
        return New-VorcePreflightFailure `
            -ErrorClass 'unsupported_for_cli' `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -Error 'Jules ist kein CLI-Provider.'
    }
    if (-not $definition.enabled) {
        return New-VorcePreflightFailure `
            -ErrorClass 'disabled' `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -Error 'Provider ist deaktiviert.'
    }

    $quotaStatus = Get-VorceQuotaStatus -AgentName $definition.provider_id -ModelTier $ModelTier
    if (-not $quotaStatus.available) {
        return New-VorcePreflightFailure `
            -ErrorClass $quotaStatus.error_class `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -Error 'Provider-Quota ist nicht verfuegbar.'
    }
    if ($definition.auth_env_var) {
        $authValue = [Environment]::GetEnvironmentVariable([string]$definition.auth_env_var)
        if ([string]::IsNullOrWhiteSpace($authValue)) {
            return New-VorcePreflightFailure `
                -ErrorClass 'auth_missing' `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -Error "Umgebungsvariable '$($definition.auth_env_var)' fehlt."
        }
    }

    $command = if ($definition.command) {
        Get-Command ([string]$definition.command) -ErrorAction SilentlyContinue
    } else {
        $null
    }
    if (-not $command) {
        return New-VorcePreflightFailure `
            -ErrorClass 'command_missing' `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -Error "Command '$($definition.command)' wurde nicht gefunden."
    }

    $artifactRoot = Get-VorceAgentArtifactRoot -RunContext $RunContext -AttemptId $attemptId
    $null = New-Item -ItemType Directory -Path $artifactRoot -Force
    $stdoutPath = Join-Path $artifactRoot 'stdout.log'
    $stderrPath = Join-Path $artifactRoot 'stderr.log'
    $promptPath = $null
    $transport = Get-VorcePromptTransport -Definition $definition -Prompt $Prompt -RequestedTransport $PromptTransport
    if ($transport -eq 'tempfile') {
        $promptPath = Join-Path $artifactRoot 'prompt.txt'
        [System.IO.File]::WriteAllText($promptPath, $Prompt, [System.Text.UTF8Encoding]::new($false))
    }

    $argumentResult = Build-VorceProviderArguments `
        -Definition $definition `
        -Prompt $Prompt `
        -Transport $transport `
        -PromptFile $promptPath `
        -ModelTier $ModelTier
    if (-not $argumentResult.valid) {
        if ($promptPath -and (Test-Path -LiteralPath $promptPath)) {
            Remove-Item -LiteralPath $promptPath -Force -ErrorAction SilentlyContinue
        }
        return New-VorcePreflightFailure `
            -ErrorClass 'invalid_output' `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -Error $argumentResult.error
    }

    $workingDirectory = if ($RunContext.working_directory) {
        [string]$RunContext.working_directory
    } elseif ($global:VorceRoot) {
        [string]$global:VorceRoot
    } else {
        (Get-Location).Path
    }

    $executablePath = $command.Source
    $commandPrefixArguments = @()
    if ($command.CommandType -eq [System.Management.Automation.CommandTypes]::ExternalScript -or
        [System.IO.Path]::GetExtension($command.Source) -eq '.ps1') {
        $powershellHost = Get-Command pwsh -ErrorAction SilentlyContinue
        if (-not $powershellHost) {
            $powershellHost = Get-Command powershell -ErrorAction SilentlyContinue
        }
        if (-not $powershellHost) {
            return New-VorcePreflightFailure `
                -ErrorClass 'command_missing' `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -Error "PowerShell-Host fuer '$($command.Source)' wurde nicht gefunden."
        }
        $executablePath = $powershellHost.Source
        $commandPrefixArguments = @('-NoProfile', '-File', $command.Source)
    }

    $start = Get-Date
    $process = $null
    $processStarted = $false
    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $executablePath
        $startInfo.WorkingDirectory = $workingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.RedirectStandardInput = $transport -eq 'stdin'
        $allArguments = @($commandPrefixArguments) + @($argumentResult.arguments)
        Set-VorceProcessArguments -StartInfo $startInfo -Arguments $allArguments

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'Process.Start() lieferte false.'
        }
        $processStarted = $true
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($transport -eq 'stdin') {
            $process.StandardInput.Write($Prompt)
            $process.StandardInput.Close()
        }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-VorceProcessTree -Process $process
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            [System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.UTF8Encoding]::new($false))
            $duration = [int]((Get-Date) - $start).TotalMilliseconds
            $policy = Get-VorceAgentFailurePolicy -ErrorClass 'timeout'
            Register-VorceQuotaUsage `
                -AgentName $definition.provider_id `
                -ModelTier $ModelTier `
                -Outcome 'retryable_failure' | Out-Null
            return New-VorceAgentAttemptResult `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -DurationMs $duration `
                -StdoutPath $stdoutPath `
                -StderrPath $stderrPath `
                -ErrorClass $policy.error_class `
                -Error 'Provider-Prozess hat das Timeout ueberschritten.' `
                -Retryable $policy.retryable `
                -FallbackRecommended $policy.fallback_recommended `
                -ProcessStarted $true
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.UTF8Encoding]::new($false))
        $duration = [int]((Get-Date) - $start).TotalMilliseconds

        $technicalError = Get-VorceAgentErrorClassification `
            -ExitCode $process.ExitCode `
            -Stdout $stdout `
            -Stderr $stderr
        if ($technicalError) {
            $outcome = if ($technicalError.retryable) { 'retryable_failure' } else { 'failure' }
            Register-VorceQuotaUsage `
                -AgentName $definition.provider_id `
                -ModelTier $ModelTier `
                -Outcome $outcome | Out-Null
            return New-VorceAgentAttemptResult `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -ExitCode $process.ExitCode `
                -DurationMs $duration `
                -StdoutPath $stdoutPath `
                -StderrPath $stderrPath `
                -ErrorClass $technicalError.error_class `
                -Error ($stderr.Trim()) `
                -Retryable $technicalError.retryable `
                -FallbackRecommended $technicalError.fallback_recommended `
                -ProcessStarted $true
        }

        if (-not (Test-Path -LiteralPath $stdoutPath) -or -not (Test-Path -LiteralPath $stderrPath)) {
            $artifactError = Get-VorceAgentFailurePolicy -ErrorClass 'artifact_missing'
            Register-VorceQuotaUsage `
                -AgentName $definition.provider_id `
                -ModelTier $ModelTier `
                -Outcome 'retryable_failure' | Out-Null
            return New-VorceAgentAttemptResult `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -ExitCode $process.ExitCode `
                -DurationMs $duration `
                -StdoutPath $stdoutPath `
                -StderrPath $stderrPath `
                -ErrorClass $artifactError.error_class `
                -Error 'stdout- oder stderr-Artefakt fehlt.' `
                -Retryable $artifactError.retryable `
                -FallbackRecommended $artifactError.fallback_recommended `
                -ProcessStarted $true
        }

        $validation = Test-VorceAgentResult -Stdout $stdout -Stderr $stderr -ExpectedOutput $ExpectedOutput
        if (-not $validation.valid) {
            $outcome = if ($validation.retryable) { 'retryable_failure' } else { 'failure' }
            Register-VorceQuotaUsage `
                -AgentName $definition.provider_id `
                -ModelTier $ModelTier `
                -Outcome $outcome | Out-Null
            return New-VorceAgentAttemptResult `
                -Provider $definition.provider_id `
                -RequestedProvider $ProviderId `
                -ModelTier $ModelTier `
                -Model $modelName `
                -AttemptId $attemptId `
                -ExitCode $process.ExitCode `
                -DurationMs $duration `
                -Output $validation.normalized_output `
                -OutputHash $validation.output_hash `
                -StdoutPath $stdoutPath `
                -StderrPath $stderrPath `
                -ErrorClass $validation.error_class `
                -Error $validation.error `
                -Retryable $validation.retryable `
                -FallbackRecommended $validation.fallback_recommended `
                -ProcessStarted $true `
                -WrapperDetected $validation.wrapper_detected
        }

        Register-VorceQuotaUsage `
            -AgentName $definition.provider_id `
            -ModelTier $ModelTier `
            -Outcome 'success' | Out-Null
        return New-VorceAgentAttemptResult `
            -Success $true `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -ExitCode $process.ExitCode `
            -DurationMs $duration `
            -Output $validation.normalized_output `
            -Payload $validation.payload `
            -Summary $validation.summary `
            -OutputHash $validation.output_hash `
            -StdoutPath $stdoutPath `
            -StderrPath $stderrPath `
            -Retryable $false `
            -FallbackRecommended $false `
            -ProcessStarted $true `
            -NonErrorClass $validation.non_error_class `
            -WrapperDetected $validation.wrapper_detected
    } catch {
        $duration = [int]((Get-Date) - $start).TotalMilliseconds
        $policy = Get-VorceAgentFailurePolicy -ErrorClass 'unknown_provider_error'
        if ($processStarted) {
            Register-VorceQuotaUsage `
                -AgentName $definition.provider_id `
                -ModelTier $ModelTier `
                -Outcome 'retryable_failure' | Out-Null
        }
        return New-VorceAgentAttemptResult `
            -Provider $definition.provider_id `
            -RequestedProvider $ProviderId `
            -ModelTier $ModelTier `
            -Model $modelName `
            -AttemptId $attemptId `
            -DurationMs $duration `
            -StdoutPath $stdoutPath `
            -StderrPath $stderrPath `
            -ErrorClass $policy.error_class `
            -Error $_.Exception.Message `
            -Retryable $policy.retryable `
            -FallbackRecommended $policy.fallback_recommended `
            -ProcessStarted $processStarted
    } finally {
        if ($promptPath -and (Test-Path -LiteralPath $promptPath)) {
            Remove-Item -LiteralPath $promptPath -Force -ErrorAction SilentlyContinue
        }
        if ($process) { $process.Dispose() }
    }
}

function Get-VorceFallbackSettings {
    $settings = [pscustomobject]@{
        retry_after_minutes = 15
        max_chain_cycles = 3
    }
    $configPath = Join-Path $global:VarDir 'config/autopilot-config.json'
    if (-not (Test-Path -LiteralPath $configPath)) { return $settings }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.fallback.retry_after_minutes) {
            $settings.retry_after_minutes = [int]$config.fallback.retry_after_minutes
        }
        if ($config.fallback.max_chain_cycles) {
            $settings.max_chain_cycles = [int]$config.fallback.max_chain_cycles
        }
    } catch {
        # Defaults bleiben aktiv.
    }
    return $settings
}

function Invoke-VorceAgentWithFallback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string[]]$PreferredChain = @(),
        [hashtable]$RunContext = @{},
        [object]$ExpectedOutput = 'text',
        [int]$TimeoutSeconds = 120
    )

    $chain = Get-VorceProviderChain `
        -PreferredChain $PreferredChain `
        -TaskType $TaskType `
        -RunContext $RunContext
    $attempts = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $chain) {
        $providerId = $entry
        $modelTier = 'default'
        if ($entry -match '^([^:]+):([^:]+)$') {
            $providerId = $Matches[1]
            $modelTier = $Matches[2]
        }

        $attempt = Invoke-VorceProviderProcess `
            -ProviderId $providerId `
            -Prompt $Prompt `
            -ModelTier $modelTier `
            -RunContext $RunContext `
            -ExpectedOutput $ExpectedOutput `
            -TimeoutSeconds $TimeoutSeconds
        $attempts.Add($attempt)
        if ($attempt.success) {
            $result = $attempt | Select-Object *
            $result | Add-Member -MemberType NoteProperty -Name attempts -Value @($attempts.ToArray()) -Force
            return $result
        }
    }

    $fallbackSettings = Get-VorceFallbackSettings
    $chainCycle = if ($RunContext.chain_cycle) { [int]$RunContext.chain_cycle } else { 1 }
    $waiting = $chainCycle -lt $fallbackSettings.max_chain_cycles
    $lastAttempt = if ($attempts.Count -gt 0) { $attempts[-1] } else { $null }
    $retryAfter = if ($waiting) {
        (Get-Date).AddMinutes($fallbackSettings.retry_after_minutes).ToString('o')
    } else {
        $null
    }

    return [pscustomobject]@{
        success = $false
        status = if ($waiting) { 'waiting_provider' } else { 'failed' }
        provider = if ($lastAttempt) { $lastAttempt.provider } else { $null }
        model_tier = if ($lastAttempt) { $lastAttempt.model_tier } else { $null }
        model = if ($lastAttempt) { $lastAttempt.model } else { $null }
        attempt_id = if ($lastAttempt) { $lastAttempt.attempt_id } else { [guid]::NewGuid().ToString('N') }
        process_started = if ($lastAttempt) { $lastAttempt.process_started } else { $false }
        exit_code = if ($lastAttempt) { $lastAttempt.exit_code } else { -1 }
        duration_ms = if ($attempts.Count) { ($attempts | Measure-Object duration_ms -Sum).Sum } else { 0 }
        output = ''
        payload = $null
        summary = ''
        output_hash = $null
        stdout_path = if ($lastAttempt) { $lastAttempt.stdout_path } else { $null }
        stderr_path = if ($lastAttempt) { $lastAttempt.stderr_path } else { $null }
        error = 'Provider-Chain ist erschoepft.'
        error_class = 'chain_exhausted'
        retryable = $waiting
        fallback_recommended = $waiting
        attempts = @($attempts.ToArray())
        waiting_provider = $waiting
        retry_after = $retryAfter
        resume_required = $waiting
        chain_cycle = $chainCycle
        max_chain_cycles = $fallbackSettings.max_chain_cycles
    }
}

function Invoke-VorceAgent {
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelTier = 'default',
        [string]$WorkingDirectory = $null,
        [string[]]$PreferredChain = @(),
        [hashtable]$RunContext = @{},
        [object]$ExpectedOutput = 'text',
        [int]$TimeoutSeconds = 120
    )

    $context = @{}
    if ($WorkingDirectory) { $context.working_directory = $WorkingDirectory }
    foreach ($key in $RunContext.Keys) { $context[$key] = $RunContext[$key] }

    if ($PreferredChain -and $PreferredChain.Count -gt 0) {
        return Invoke-VorceAgentWithFallback `
            -TaskType $AgentName `
            -Prompt $Prompt `
            -PreferredChain $PreferredChain `
            -RunContext $context `
            -ExpectedOutput $ExpectedOutput `
            -TimeoutSeconds $TimeoutSeconds
    }

    return Invoke-VorceProviderProcess `
        -ProviderId $AgentName `
        -Prompt $Prompt `
        -ModelTier $ModelTier `
        -RunContext $context `
        -ExpectedOutput $ExpectedOutput `
        -TimeoutSeconds $TimeoutSeconds
}
