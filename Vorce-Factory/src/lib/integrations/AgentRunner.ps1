# AgentRunner.ps1 (Vorce 3.0)
# Registry-getriebene Provider-Ausfuehrung mit Fallback.

function Get-VorceProviderDefinition {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [string]$ModelTier = 'default'
    )

    $registry = Read-VorceQuotaRegistry
    if ($null -eq $registry -or $null -eq $registry.providers) {
        return $null
    }

    $canonicalId = Resolve-VorceProviderId -ProviderName $ProviderId
    if (-not $canonicalId) { $canonicalId = $ProviderId }

    if ($registry.providers.PSObject.Properties.Name -notcontains $canonicalId) {
        return $null
    }

    $provider = $registry.providers.$canonicalId
    $model = $null
    if ($provider.models -and $provider.models.PSObject.Properties.Name -contains $ModelTier) {
        $model = $provider.models.$ModelTier
    } elseif ($provider.models -and $provider.models.PSObject.Properties.Name.Count -gt 0) {
        $firstModel = $provider.models.PSObject.Properties | Select-Object -First 1
        $model = $firstModel.Value
    }

    return [pscustomobject]@{
        provider_id = $canonicalId
        provider = $provider
        model = $model
        command = $provider.command
        cli_args = @($provider.cli_args)
        auth_env_var = $provider.auth_env_var
        enabled = $provider.enabled -eq $true
        prompt_transport = if ($provider.prompt_transport) { [string]$provider.prompt_transport } else { 'argument' }
    }
}

function Resolve-VorceProviderId {
    param([Parameter(Mandatory)][string]$ProviderName)

    $name = $ProviderName.Trim().ToLowerInvariant()
    switch ($name) {
        'gemini' { return 'gemini_cli' }
        'gemini_cli' { return 'gemini_cli' }
        'claude' { return 'claude_code' }
        'claude_code' { return 'claude_code' }
        'codex' { return 'codex_orchestrator' }
        'codex_cli' { return 'codex_orchestrator' }
        'codex_orchestrator' { return 'codex_orchestrator' }
        'kiro' { return 'kiro_cli' }
        'kiro_cli' { return 'kiro_cli' }
        'cline' { return 'cline_cli' }
        'cline_cli' { return 'cline_cli' }
        'copilot' { return 'copilot_cli' }
        'copilot_cli' { return 'copilot_cli' }
        'cursor' { return 'cursor_agent' }
        'cursor-agent' { return 'cursor_agent' }
        'cursor_agent' { return 'cursor_agent' }
        'jules' { return 'jules' }
        'jules_cli' { return 'jules' }
        'jules_extern' { return 'jules' }
        default { return $ProviderName }
    }
}

function Get-VorceProviderChain {
    param(
        [string[]]$PreferredChain,
        [string]$TaskType,
        [string[]]$DefaultChain
    )

    $registry = Read-VorceQuotaRegistry
    $routing = @()

    if ($PreferredChain) { $routing += $PreferredChain }
    if ($registry -and $registry.routing_rules -and $TaskType -and $registry.routing_rules.PSObject.Properties.Name -contains $TaskType) {
        $routing += @($registry.routing_rules.$TaskType)
    }
    if ($DefaultChain) { $routing += $DefaultChain }

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $routing) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $candidate = $entry
        $modelTier = $null
        if ($entry -match '^([^:]+):([^:]+)$') {
            $candidate = $Matches[1]
            $modelTier = $Matches[2]
        }
        $providerId = Resolve-VorceProviderId -ProviderName $candidate
        $token = if ($modelTier) { '{0}:{1}' -f $providerId, $modelTier } else { $providerId }
        if (-not $normalized.Contains($token)) {
            $normalized.Add($token)
        }
    }

    return @($normalized)
}

function Invoke-VorceProviderProcess {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelTier = 'default',
        [hashtable]$RunContext = @{},
        [string]$ExpectedOutput = 'text',
        [int]$TimeoutSeconds = 120,
        [string]$PromptTransport = 'auto'
    )

    $definition = Get-VorceProviderDefinition -ProviderId $ProviderId -ModelTier $ModelTier
    if (-not $definition) {
        return [pscustomobject]@{
            success = $false
            provider = $ProviderId
            model_tier = $ModelTier
            model = $null
            attempt_id = [guid]::NewGuid().ToString('N')
            exit_code = -1
            duration_ms = 0
            output = ''
            stdout_path = $null
            stderr_path = $null
            error_class = 'unknown_provider'
            retryable = $false
            fallback_recommended = $true
        }
    }

    if ($definition.provider_id -eq 'jules') {
        return [pscustomobject]@{
            success = $false
            provider = $definition.provider_id
            model_tier = $ModelTier
            model = $definition.model.name
            attempt_id = [guid]::NewGuid().ToString('N')
            exit_code = -1
            duration_ms = 0
            output = ''
            stdout_path = $null
            stderr_path = $null
            error_class = 'unsupported_for_cli'
            retryable = $false
            fallback_recommended = $true
        }
    }

    $commandName = $definition.command
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            success = $false
            provider = $definition.provider_id
            model_tier = $ModelTier
            model = $definition.model.name
            attempt_id = [guid]::NewGuid().ToString('N')
            exit_code = -1
            duration_ms = 0
            output = ''
            stdout_path = $null
            stderr_path = $null
            error_class = 'command_missing'
            retryable = $false
            fallback_recommended = $true
        }
    }

    $mainRunFolder = if ($RunContext.ContainsKey('main_run_id') -and $RunContext.main_run_id) { [string]$RunContext.main_run_id } else { 'run' }
    $artifactRoot = Join-Path $global:VarDir ('tmp/agent-artifacts/{0}' -f $mainRunFolder)
    if (-not (Test-Path $artifactRoot)) { $null = New-Item -ItemType Directory -Path $artifactRoot -Force }
    $attemptId = [guid]::NewGuid().ToString('N')
    $attemptRoot = Join-Path $artifactRoot $attemptId
    $null = New-Item -ItemType Directory -Path $attemptRoot -Force

    $stdoutPath = Join-Path $attemptRoot 'stdout.log'
    $stderrPath = Join-Path $attemptRoot 'stderr.log'
    $promptPath = $null
    $args = @()
    foreach ($arg in @($definition.cli_args)) {
        if ($arg -eq '{PROMPT}') {
            continue
        }
        if ($arg -eq '{MODEL}') {
            if ($definition.model -and $definition.model.name) {
                $args += [string]$definition.model.name
            } else {
                $args += $ModelTier
            }
        } else {
            $args += $arg
        }
    }

    $transport = $PromptTransport
    if ($transport -eq 'auto') {
        $transport = if ($Prompt.Length -gt 6000) { 'stdin' } else { $definition.prompt_transport }
    }

    if ($transport -eq 'tempfile') {
        $promptPath = Join-Path $attemptRoot 'prompt.txt'
        Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding UTF8
    } elseif ($transport -eq 'stdin') {
        $promptPath = Join-Path $attemptRoot 'prompt.txt'
        Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding UTF8
    }

    if ($definition.cli_args -contains '{PROMPT}') {
        $args = @($args | ForEach-Object { $_.Replace('{PROMPT}', $Prompt) })
    }

    if ($definition.auth_env_var) {
        $envValue = [Environment]::GetEnvironmentVariable($definition.auth_env_var)
        if ([string]::IsNullOrWhiteSpace($envValue)) {
            return [pscustomobject]@{
                success = $false
                provider = $definition.provider_id
                model_tier = $ModelTier
                model = $definition.model.name
                attempt_id = $attemptId
                exit_code = -1
                duration_ms = 0
                output = ''
                stdout_path = $stdoutPath
                stderr_path = $stderrPath
                error_class = 'auth_missing'
                retryable = $false
                fallback_recommended = $true
            }
        }
    }

    $start = Get-Date
    try {
        $commandArgs = @($args)
        if ($transport -eq 'stdin' -and $promptPath) {
            $commandArgs = @($commandArgs)
        } elseif ($definition.cli_args -notcontains '{PROMPT}') {
            $commandArgs = @($commandArgs)
        }

        $workingDirectory = if ($RunContext.ContainsKey('working_directory') -and $RunContext.working_directory) { $RunContext.working_directory } else { $global:VorceRoot }
        $startParams = @{
            FilePath = $command.Source
            ArgumentList = $commandArgs
            WorkingDirectory = $workingDirectory
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError = $stderrPath
            NoNewWindow = $true
            PassThru = $true
        }
        if ($transport -eq 'stdin' -and $promptPath) {
            $startParams.RedirectStandardInput = $promptPath
        }

        $process = Start-Process @startParams
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch {}
            return [pscustomobject]@{
                success = $false
                provider = $definition.provider_id
                model_tier = $ModelTier
                model = $definition.model.name
                attempt_id = $attemptId
                exit_code = -1
                duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
                output = ''
                stdout_path = $stdoutPath
                stderr_path = $stderrPath
                error_class = 'timeout'
                retryable = $true
                fallback_recommended = $true
            }
        }

        $stdout = if (Test-Path $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
        $stderr = if (Test-Path $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
        $output = @($stdout, $stderr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
        $success = $process.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)

        return [pscustomobject]@{
            success = $success
            provider = $definition.provider_id
            model_tier = $ModelTier
            model = $definition.model.name
            attempt_id = $attemptId
            exit_code = $process.ExitCode
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = $output
            stdout_path = $stdoutPath
            stderr_path = $stderrPath
            error_class = if ($success) { $null } elseif ($process.ExitCode -ne 0) { 'exit_nonzero' } else { 'empty_output' }
            retryable = $process.ExitCode -ne 0
            fallback_recommended = $true
        }
    } catch {
        return [pscustomobject]@{
            success = $false
            provider = $definition.provider_id
            model_tier = $ModelTier
            model = $definition.model.name
            attempt_id = $attemptId
            exit_code = -1
            duration_ms = [int]((Get-Date) - $start).TotalMilliseconds
            output = ''
            stdout_path = $stdoutPath
            stderr_path = $stderrPath
            error_class = 'unknown_provider_error'
            retryable = $true
            fallback_recommended = $true
        }
    } finally {
        if ($promptPath -and (Test-Path $promptPath)) { Remove-Item -LiteralPath $promptPath -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-VorceAgentWithFallback {
    param(
        [Parameter(Mandatory)][string]$TaskType,
        [Parameter(Mandatory)][string]$Prompt,
        [string[]]$PreferredChain = @(),
        [hashtable]$RunContext = @{},
        [string]$ExpectedOutput = 'text',
        [int]$TimeoutSeconds = 120
    )

    $defaultChain = @('gemini_cli:balanced', 'claude_code:balanced', 'codex_orchestrator:planning')
    $chain = Get-VorceProviderChain -PreferredChain $PreferredChain -TaskType $TaskType -DefaultChain $defaultChain
    $attempts = @()

    foreach ($entry in $chain) {
        $providerId = $entry
        $modelTier = 'default'
        if ($entry -match '^([^:]+):([^:]+)$') {
            $providerId = $Matches[1]
            $modelTier = $Matches[2]
        }

        $attempt = Invoke-VorceProviderProcess -ProviderId $providerId -Prompt $Prompt -ModelTier $modelTier -RunContext $RunContext -ExpectedOutput $ExpectedOutput -TimeoutSeconds $TimeoutSeconds
        $attempts += $attempt
        if ($attempt.success) {
            return [pscustomobject]@{
                success = $true
                provider = $attempt.provider
                model_tier = $attempt.model_tier
                model = $attempt.model
                attempt_id = $attempt.attempt_id
                duration_ms = $attempt.duration_ms
                output = $attempt.output
                stdout_path = $attempt.stdout_path
                stderr_path = $attempt.stderr_path
                error_class = $null
                retryable = $false
                fallback_recommended = $false
                attempts = $attempts
            }
        }
    }

    return [pscustomobject]@{
        success = $false
        provider = if ($attempts.Count) { $attempts[-1].provider } else { $null }
        model_tier = if ($attempts.Count) { $attempts[-1].model_tier } else { $null }
        model = if ($attempts.Count) { $attempts[-1].model } else { $null }
        attempt_id = if ($attempts.Count) { $attempts[-1].attempt_id } else { [guid]::NewGuid().ToString('N') }
        duration_ms = if ($attempts.Count) { ($attempts | Measure-Object duration_ms -Sum).Sum } else { 0 }
        output = ''
        stdout_path = if ($attempts.Count) { $attempts[-1].stdout_path } else { $null }
        stderr_path = if ($attempts.Count) { $attempts[-1].stderr_path } else { $null }
        error_class = 'chain_exhausted'
        retryable = $true
        fallback_recommended = $true
        attempts = $attempts
        waiting_provider = $true
    }
}

function Invoke-VorceAgent {
    param(
        [Parameter(Mandatory)][string]$AgentName,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$ModelTier = 'default',
        [string]$WorkingDirectory = $null,
        [string[]]$PreferredChain = @(),
        [hashtable]$RunContext = @{}
    )

    $context = @{}
    if ($WorkingDirectory) { $context.working_directory = $WorkingDirectory }
    foreach ($key in $RunContext.Keys) { $context[$key] = $RunContext[$key] }

    if ($PreferredChain -and $PreferredChain.Count -gt 0) {
        return Invoke-VorceAgentWithFallback -TaskType $AgentName -Prompt $Prompt -PreferredChain $PreferredChain -RunContext $context
    }

    return Invoke-VorceProviderProcess -ProviderId $AgentName -Prompt $Prompt -ModelTier $ModelTier -RunContext $context
}
