# Write-Log.ps1 (Vorce 3.0)
# Dot-source safe logging core for terminal, session, error and JSONL sinks.

function Get-VorceLogRoot {
    if ($global:VarDir) {
        return Join-Path $global:VarDir 'log'
    }

    return Join-Path (Join-Path $PSScriptRoot '..\..\..\var') 'log'
}

function Initialize-VorceLogDirectory {
    $logRoot = Get-VorceLogRoot
    $null = New-Item -ItemType Directory -Path $logRoot -Force
    foreach ($relative in @('events', 'sessions', 'crash-reports')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $logRoot $relative) -Force
    }

    return $logRoot
}

function Get-VorceLogPath {
    param(
        [string]$SessionId,
        [ValidateSet('event', 'error', 'session', 'default')]
        [string]$Category = 'session',
        [string]$DateStamp
    )

    $logRoot = Initialize-VorceLogDirectory
    switch ($Category) {
        'event' {
            if (-not $DateStamp) {
                $DateStamp = Get-Date -Format 'yyyyMMdd'
            }
            return Join-Path $logRoot ("events/vorce-events-$DateStamp.jsonl")
        }
        'error' {
            return Join-Path $logRoot 'vorce-errors.log'
        }
        'session' {
            if (-not $SessionId) {
                $SessionId = 'default'
            }
            return Join-Path $logRoot ("sessions/$SessionId.log")
        }
        default {
            return Join-Path $logRoot 'vorce.log'
        }
    }
}

function Get-VorceContextValue {
    param(
        [object]$Context,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Context) {
        return $null
    }

    if ($Context -is [System.Collections.IDictionary]) {
        foreach ($key in $Context.Keys) {
            if ([string]$key -ieq $Name) {
                return $Context[$key]
            }
        }
        return $null
    }

    $property = $Context.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1
    if ($property) {
        return $property.Value
    }

    return $null
}

function New-VorceSessionContext {
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$Component = 'bootstrap'
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = 'session_{0}_{1}' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 12))
    }

    return [ordered]@{
        session_id = $SessionId
        correlation_id = $null
        run_id = $null
        parent_run_id = $null
        main_run_id = $null
        sub_run_id = $null
        part_run_id = $null
        run_name = $null
        run_type = $null
        component = $Component
    }
}

function Initialize-VorceLogContext {
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$Component = 'bootstrap',
        [switch]$Force
    )

    $existingSessionId = Get-VorceContextValue -Context $global:VorceLogContext -Name 'session_id'
    if (-not $Force -and -not [string]::IsNullOrWhiteSpace([string]$existingSessionId)) {
        return $global:VorceLogContext
    }

    $global:VorceLogContext = New-VorceSessionContext -SessionId $SessionId -Component $Component
    return $global:VorceLogContext
}

function Set-VorceLogContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context
    )

    $global:VorceLogContext = $Context
    return $global:VorceLogContext
}

function Get-VorceLogContext {
    [CmdletBinding()]
    param(
        [switch]$Ensure
    )

    if ($Ensure -and [string]::IsNullOrWhiteSpace([string](Get-VorceContextValue -Context $global:VorceLogContext -Name 'session_id'))) {
        return Initialize-VorceLogContext
    }

    return $global:VorceLogContext
}

function New-VorceRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('MAIN', 'SUB', 'PART')][string]$RunType,
        [Parameter(Mandatory)][string]$RunName,
        [object]$ParentContext,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$RunId,
        [string]$ParentRunId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$Component = 'run-engine'
    )

    if ($null -eq $ParentContext) {
        $ParentContext = Get-VorceLogContext
    }

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = [string](Get-VorceContextValue -Context $ParentContext -Name 'session_id')
    }
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = [string](Get-VorceContextValue -Context (Initialize-VorceLogContext) -Name 'session_id')
    }

    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = 'run_{0}_{1}' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 12))
    }
    if ([string]::IsNullOrWhiteSpace($ParentRunId)) {
        $ParentRunId = [string](Get-VorceContextValue -Context $ParentContext -Name 'run_id')
    }
    if ([string]::IsNullOrWhiteSpace($MainRunId)) {
        $MainRunId = [string](Get-VorceContextValue -Context $ParentContext -Name 'main_run_id')
    }
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [string](Get-VorceContextValue -Context $ParentContext -Name 'correlation_id')
    }

    switch ($RunType) {
        'MAIN' {
            if ([string]::IsNullOrWhiteSpace($MainRunId)) {
                $MainRunId = $RunId
            } else {
                $RunId = $MainRunId
            }
            if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
                $CorrelationId = $MainRunId
            }
            $ParentRunId = $null
        }
        'SUB' {
            if ([string]::IsNullOrWhiteSpace($SubRunId)) {
                $SubRunId = $RunId
            } else {
                $RunId = $SubRunId
            }
        }
        'PART' {
            if ([string]::IsNullOrWhiteSpace($PartRunId)) {
                $PartRunId = $RunId
            } else {
                $RunId = $PartRunId
            }
            if ([string]::IsNullOrWhiteSpace($SubRunId)) {
                $SubRunId = [string](Get-VorceContextValue -Context $ParentContext -Name 'sub_run_id')
            }
        }
    }

    return [ordered]@{
        session_id = $SessionId
        correlation_id = $CorrelationId
        run_id = $RunId
        parent_run_id = $ParentRunId
        main_run_id = $MainRunId
        sub_run_id = $SubRunId
        part_run_id = $PartRunId
        run_name = $RunName
        run_type = $RunType
        component = $Component
    }
}

function Get-VorceProviderAuthEnvironmentNames {
    [CmdletBinding()]
    param(
        [object]$ProviderRegistry
    )

    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($commonName in @(
        'ANTHROPIC_API_KEY',
        'AZURE_OPENAI_API_KEY',
        'GEMINI_API_KEY',
        'GH_TOKEN',
        'GITHUB_TOKEN',
        'GOOGLE_API_KEY',
        'OPENAI_API_KEY'
    )) {
        $null = $names.Add($commonName)
    }

    if ($null -eq $ProviderRegistry) {
        if ($global:VorceProviderRegistry) {
            $ProviderRegistry = $global:VorceProviderRegistry
        } elseif ($global:QuotaRegistry) {
            $ProviderRegistry = $global:QuotaRegistry
        } else {
            $registryPath = if ($global:VarDir) {
                Join-Path $global:VarDir 'config/quota-registry.json'
            } else {
                Join-Path (Join-Path $PSScriptRoot '..\..\..\var') 'config/quota-registry.json'
            }

            if (Test-Path -LiteralPath $registryPath) {
                try {
                    $ProviderRegistry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
                } catch {
                    $ProviderRegistry = $null
                }
            }
        }
    }

    $providers = Get-VorceContextValue -Context $ProviderRegistry -Name 'providers'
    if ($providers) {
        $providerValues = if ($providers -is [System.Collections.IDictionary]) {
            @($providers.Values)
        } else {
            @($providers.PSObject.Properties | ForEach-Object { $_.Value })
        }

        foreach ($provider in $providerValues) {
            $authEnvironmentName = [string](Get-VorceContextValue -Context $provider -Name 'auth_env_var')
            if (-not [string]::IsNullOrWhiteSpace($authEnvironmentName)) {
                $null = $names.Add($authEnvironmentName)
            }
        }
    }

    return @($names)
}

function Get-VorceSecretValues {
    [CmdletBinding()]
    param(
        [object]$ProviderRegistry
    )

    $values = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($environmentName in @(Get-VorceProviderAuthEnvironmentNames -ProviderRegistry $ProviderRegistry)) {
        $environmentValue = [Environment]::GetEnvironmentVariable($environmentName)
        if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
            $null = $values.Add($environmentValue)
        }
    }

    return @($values)
}

function Protect-VorceSecretText {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [object]$ProviderRegistry,
        [int]$MaxLength = 500
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $redacted = $Text
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)(Authorization\s*:\s*Bearer\s+)[^\s,''";]+',
        '$1[REDACTED]'
    )
    $redacted = [regex]::Replace($redacted, '(?i)\bghp_[A-Za-z0-9_]{4,}\b', '[REDACTED]')
    $redacted = [regex]::Replace($redacted, '(?i)\bgithub_pat_[A-Za-z0-9_]{4,}\b', '[REDACTED]')
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)(\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|secret|password)\b\s*[:=]\s*["'']?)[^,\s;}"'']+',
        '$1[REDACTED]'
    )

    foreach ($environmentName in @(Get-VorceProviderAuthEnvironmentNames -ProviderRegistry $ProviderRegistry)) {
        $escapedName = [regex]::Escape($environmentName)
        $redacted = [regex]::Replace(
            $redacted,
            "(?i)(\b$escapedName\b\s*[:=]\s*[`"']?)[^,\s;}`"']+",
            '$1[REDACTED]'
        )
    }

    foreach ($secretValue in @(Get-VorceSecretValues -ProviderRegistry $ProviderRegistry | Sort-Object Length -Descending)) {
        if (-not [string]::IsNullOrWhiteSpace($secretValue)) {
            $redacted = [regex]::Replace($redacted, [regex]::Escape($secretValue), '[REDACTED]')
        }
    }

    if ($MaxLength -gt 0 -and $redacted.Length -gt $MaxLength) {
        $redacted = $redacted.Substring(0, $MaxLength)
    }

    return $redacted
}

function Test-VorceOmittedLogField {
    param([string]$Name)

    return $Name -match '^(?i:prompt|raw_prompt|system_prompt|user_prompt|llm_output|model_output|full_output|completion|raw_response|response_body|stdout_content|stderr_content)$'
}

function Test-VorceSensitiveLogField {
    param(
        [string]$Name,
        [string[]]$ProviderAuthEnvironmentNames
    )

    if ($Name -match '(?i)(^|[_-])(authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|token|secret|password|credential|private[_-]?key)($|[_-])') {
        return $true
    }

    return @($ProviderAuthEnvironmentNames) -icontains $Name
}

function Protect-VorceLogValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [object]$ProviderRegistry,
        [int]$Depth = 0
    )

    if ($null -eq $Value) {
        return $null
    }
    if ($Depth -ge 20) {
        return '[OMITTED:MAX_DEPTH]'
    }
    if ($Value -is [string]) {
        return Protect-VorceSecretText -Text $Value -ProviderRegistry $ProviderRegistry -MaxLength 0
    }
    if ($Value -is [char] -or $Value -is [bool] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal] -or
        $Value -is [datetime] -or $Value -is [guid]) {
        return $Value
    }

    $authEnvironmentNames = @(Get-VorceProviderAuthEnvironmentNames -ProviderRegistry $ProviderRegistry)
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $propertyName = [string]$key
            if (Test-VorceOmittedLogField -Name $propertyName) {
                $result[$propertyName] = '[OMITTED]'
            } elseif (Test-VorceSensitiveLogField -Name $propertyName -ProviderAuthEnvironmentNames $authEnvironmentNames) {
                $result[$propertyName] = '[REDACTED]'
            } else {
                $result[$propertyName] = Protect-VorceLogValue -Value $Value[$key] -ProviderRegistry $ProviderRegistry -Depth ($Depth + 1)
            }
        }
        return $result
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            $null = $items.Add((Protect-VorceLogValue -Value $item -ProviderRegistry $ProviderRegistry -Depth ($Depth + 1)))
        }
        Write-Output -NoEnumerate $items.ToArray()
        return
    }

    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty') })
    if ($properties.Count -gt 0) {
        $result = [ordered]@{}
        foreach ($property in $properties) {
            if (Test-VorceOmittedLogField -Name $property.Name) {
                $result[$property.Name] = '[OMITTED]'
            } elseif (Test-VorceSensitiveLogField -Name $property.Name -ProviderAuthEnvironmentNames $authEnvironmentNames) {
                $result[$property.Name] = '[REDACTED]'
            } else {
                $result[$property.Name] = Protect-VorceLogValue -Value $property.Value -ProviderRegistry $ProviderRegistry -Depth ($Depth + 1)
            }
        }
        return $result
    }

    return Protect-VorceSecretText -Text ([string]$Value) -ProviderRegistry $ProviderRegistry -MaxLength 0
}

function ConvertTo-VorceJsonSafe {
    param([object]$Value)

    try {
        return $Value | ConvertTo-Json -Depth 20 -Compress
    } catch {
        return '{"serialization_error":true}'
    }
}

function Get-VorceLogMutexName {
    param([Parameter(Mandatory)][string]$Path)

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedPath))
        $hex = ([System.BitConverter]::ToString($hash)).Replace('-', '')
        return 'VorceLog_{0}' -f $hex.Substring(0, 32)
    } finally {
        $sha.Dispose()
    }
}

function Add-VorceLogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][Parameter(Mandatory)][string]$Line,
        [int]$TimeoutMilliseconds = 30000
    )

    $parentDirectory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        $null = New-Item -ItemType Directory -Path $parentDirectory -Force
    }

    $mutex = New-Object System.Threading.Mutex($false, (Get-VorceLogMutexName -Path $Path))
    $lockTaken = $false
    try {
        try {
            $lockTaken = $mutex.WaitOne($TimeoutMilliseconds)
        } catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            throw "Timeout while waiting for logging lock: $Path"
        }

        $encoding = New-Object System.Text.UTF8Encoding($false)
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        try {
            $null = $stream.Seek(0, [System.IO.SeekOrigin]::End)
            $writer = New-Object System.IO.StreamWriter($stream, $encoding)
            try {
                $writer.WriteLine($Line)
                $writer.Flush()
                $stream.Flush()
            } finally {
                $writer.Dispose()
            }
        } finally {
            if ($stream) {
                $stream.Dispose()
            }
        }
    } finally {
        if ($lockTaken) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Write-VorceLogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')][string]$Level,
        [AllowEmptyString()][Parameter(Mandatory)][string]$Message,
        [string]$Component = 'unknown',
        [string]$EventType = 'diagnostic',
        [object]$Context,
        [string]$SessionId,
        [string]$CorrelationId,
        [string]$RunId,
        [string]$ParentRunId,
        [string]$MainRunId,
        [string]$SubRunId,
        [string]$PartRunId,
        [string]$RunName,
        [string]$Provider,
        [int]$Attempt,
        [string]$Status,
        [int]$DurationMs,
        [object]$Data = @{},
        [int]$ProcessId = 0,
        [object]$ProviderRegistry,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [int]$ExitCode,
        [string]$ArtifactPath,
        [switch]$SkipTerminal
    )

    if ($null -eq $Context) {
        $Context = Get-VorceLogContext
    }

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $SessionId = [string](Get-VorceContextValue -Context $Context -Name 'session_id')
    }
    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $Context = Initialize-VorceLogContext
        $SessionId = [string](Get-VorceContextValue -Context $Context -Name 'session_id')
    }
    if ([string]::IsNullOrWhiteSpace($CorrelationId)) {
        $CorrelationId = [string](Get-VorceContextValue -Context $Context -Name 'correlation_id')
    }
    if ([string]::IsNullOrWhiteSpace($RunId)) {
        $RunId = [string](Get-VorceContextValue -Context $Context -Name 'run_id')
    }
    if ([string]::IsNullOrWhiteSpace($ParentRunId)) {
        $ParentRunId = [string](Get-VorceContextValue -Context $Context -Name 'parent_run_id')
    }
    if ([string]::IsNullOrWhiteSpace($MainRunId)) {
        $MainRunId = [string](Get-VorceContextValue -Context $Context -Name 'main_run_id')
    }
    if ([string]::IsNullOrWhiteSpace($SubRunId)) {
        $SubRunId = [string](Get-VorceContextValue -Context $Context -Name 'sub_run_id')
    }
    if ([string]::IsNullOrWhiteSpace($PartRunId)) {
        $PartRunId = [string](Get-VorceContextValue -Context $Context -Name 'part_run_id')
    }
    if ([string]::IsNullOrWhiteSpace($RunName)) {
        $RunName = [string](Get-VorceContextValue -Context $Context -Name 'run_name')
    }
    if ($Component -eq 'unknown') {
        $contextComponent = [string](Get-VorceContextValue -Context $Context -Name 'component')
        if (-not [string]::IsNullOrWhiteSpace($contextComponent)) {
            $Component = $contextComponent
        }
    }
    if ($ProcessId -le 0) {
        $ProcessId = $PID
    }

    $messageText = Protect-VorceSecretText -Text $Message -ProviderRegistry $ProviderRegistry -MaxLength 500
    $safeData = Protect-VorceLogValue -Value $Data -ProviderRegistry $ProviderRegistry
    if ($null -eq $safeData) {
        $safeData = [ordered]@{}
    }

    if ($Level -in @('ERROR', 'FATAL')) {
        if ($safeData -isnot [System.Collections.IDictionary]) {
            $safeData = [ordered]@{ detail = $safeData }
        }
        if ($ErrorClass) {
            $safeData['error_class'] = Protect-VorceSecretText -Text $ErrorClass -ProviderRegistry $ProviderRegistry -MaxLength 200
        }
        if ($ErrorRecord) {
            $safeData['exception_type'] = $ErrorRecord.Exception.GetType().FullName
            $safeData['error_message'] = Protect-VorceSecretText -Text $ErrorRecord.Exception.Message -ProviderRegistry $ProviderRegistry -MaxLength 500
        }
        if ($PSBoundParameters.ContainsKey('ExitCode')) {
            $safeData['exit_code'] = $ExitCode
        }
        if ($ArtifactPath) {
            $safeData['artifact_path'] = Protect-VorceSecretText -Text $ArtifactPath -ProviderRegistry $ProviderRegistry -MaxLength 1000
        }
    }

    $timestamp = Get-Date
    $entry = [ordered]@{
        timestamp = $timestamp.ToString('o')
        level = $Level
        event_type = $EventType
        component = $Component
        session_id = $SessionId
        correlation_id = $CorrelationId
        run_id = $RunId
        parent_run_id = $ParentRunId
        main_run_id = $MainRunId
        sub_run_id = $SubRunId
        part_run_id = $PartRunId
        run_name = $RunName
        provider = $Provider
        attempt = if ($Attempt -gt 0) { $Attempt } else { $null }
        status = $Status
        duration_ms = if ($DurationMs -gt 0) { $DurationMs } else { $null }
        message = $messageText
        data = $safeData
        pid = $ProcessId
    }

    $terminal = '[{0}] [{1}] [{2}] {3}' -f $entry.timestamp, $Level, $Component, $messageText
    if (-not $SkipTerminal) {
        switch ($Level) {
            'DEBUG' { Write-Host $terminal -ForegroundColor DarkCyan }
            'INFO' { Write-Host $terminal -ForegroundColor Gray }
            'WARN' { Write-Host $terminal -ForegroundColor Yellow }
            'ERROR' { Write-Host $terminal -ForegroundColor Red }
            'FATAL' { Write-Host $terminal -ForegroundColor Red -BackgroundColor DarkRed }
        }
    }

    $effectiveSessionId = if ($SessionId) { $SessionId } else { 'default' }
    $sessionPath = Get-VorceLogPath -SessionId $effectiveSessionId -Category 'session'
    Add-VorceLogLine -Path $sessionPath -Line $terminal

    $jsonlPath = Get-VorceLogPath -Category 'event' -DateStamp ($timestamp.ToString('yyyyMMdd'))
    Add-VorceLogLine -Path $jsonlPath -Line (ConvertTo-VorceJsonSafe -Value $entry)

    if ($Level -in @('ERROR', 'FATAL')) {
        $errorPath = Get-VorceLogPath -Category 'error'
        Add-VorceLogLine -Path $errorPath -Line $terminal
    }

    return [pscustomobject]$entry
}

function Write-VorceRequiredEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Run', 'Router', 'Provider', 'State', 'Process')][string]$Category,
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'unknown',
        [object]$Context,
        [object]$Data = @{},
        [string]$Provider,
        [int]$Attempt,
        [int]$DurationMs,
        [int]$ProcessId = 0,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [int]$ExitCode,
        [string]$ArtifactPath,
        [switch]$SkipTerminal
    )

    $contract = @{
        Run = @{
            initialized = @{ type = 'run_initialized'; level = 'DEBUG'; status = 'initialized' }
            started = @{ type = 'run_started'; level = 'INFO'; status = 'running' }
            completed = @{ type = 'run_completed'; level = 'INFO'; status = 'completed' }
            failed = @{ type = 'run_failed'; level = 'ERROR'; status = 'failed' }
            skipped = @{ type = 'run_skipped'; level = 'INFO'; status = 'skipped' }
            reused = @{ type = 'run_reused'; level = 'INFO'; status = 'reused' }
            waiting_provider = @{ type = 'run_waiting_provider'; level = 'INFO'; status = 'waiting_provider' }
        }
        Router = @{
            decision = @{ type = 'router_decision'; level = 'INFO'; status = 'decision' }
        }
        Provider = @{
            attempt_started = @{ type = 'provider_attempt_started'; level = 'INFO'; status = 'attempt_started' }
            attempt_failed = @{ type = 'provider_attempt_failed'; level = 'ERROR'; status = 'attempt_failed' }
            fallback_selected = @{ type = 'provider_fallback_selected'; level = 'WARN'; status = 'fallback_selected' }
            attempt_succeeded = @{ type = 'provider_attempt_succeeded'; level = 'INFO'; status = 'attempt_succeeded' }
            chain_exhausted = @{ type = 'provider_chain_exhausted'; level = 'ERROR'; status = 'chain_exhausted' }
        }
        State = @{
            saved = @{ type = 'state_saved'; level = 'DEBUG'; status = 'saved' }
            save_failed = @{ type = 'state_save_failed'; level = 'ERROR'; status = 'save_failed' }
        }
        Process = @{
            started = @{ type = 'process_started'; level = 'INFO'; status = 'started' }
            healthy = @{ type = 'process_healthy'; level = 'INFO'; status = 'healthy' }
            degraded = @{ type = 'process_degraded'; level = 'WARN'; status = 'degraded' }
            stopped = @{ type = 'process_stopped'; level = 'INFO'; status = 'stopped' }
            crashed = @{ type = 'process_crashed'; level = 'ERROR'; status = 'crashed' }
        }
    }

    if (-not $contract[$Category].ContainsKey($Event)) {
        throw "Unsupported required event '$Category/$Event'."
    }

    $definition = $contract[$Category][$Event]
    $parameters = @{
        Level = $definition.level
        Message = $Message
        Component = $Component
        EventType = $definition.type
        Context = $Context
        Data = $Data
        Provider = $Provider
        Attempt = $Attempt
        Status = $definition.status
        DurationMs = $DurationMs
        ProcessId = $ProcessId
        ErrorRecord = $ErrorRecord
        ErrorClass = $ErrorClass
        ArtifactPath = $ArtifactPath
        SkipTerminal = $SkipTerminal
    }
    if ($PSBoundParameters.ContainsKey('ExitCode')) {
        $parameters.ExitCode = $ExitCode
    }

    return Write-VorceLogEntry @parameters
}

function Write-VorceRunEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('initialized', 'started', 'completed', 'failed', 'skipped', 'reused', 'waiting_provider')][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][object]$Context,
        [string]$Component = 'run-engine',
        [object]$Data = @{},
        [int]$DurationMs,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [switch]$SkipTerminal
    )

    return Write-VorceRequiredEvent -Category Run -Event $State -Message $Message -Component $Component -Context $Context -Data $Data -DurationMs $DurationMs -ErrorRecord $ErrorRecord -ErrorClass $ErrorClass -SkipTerminal:$SkipTerminal
}

function Write-VorceRouterDecisionEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Condition,
        [Parameter(Mandatory)][string]$Reason,
        [object]$Evidence = @{},
        [string]$Component = 'router'
    )

    $data = [ordered]@{
        condition = $Condition
        reason = $Reason
        evidence = $Evidence
    }
    return Write-VorceRequiredEvent -Category Router -Event decision -Message $Message -Component $Component -Context $Context -Data $data
}

function Write-VorceProviderEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('attempt_started', 'attempt_failed', 'fallback_selected', 'attempt_succeeded', 'chain_exhausted')][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Provider,
        [int]$Attempt,
        [object]$Data = @{},
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [int]$ExitCode,
        [string]$ArtifactPath
    )

    $parameters = @{
        Category = 'Provider'
        Event = $State
        Message = $Message
        Component = 'agent-runner'
        Context = $Context
        Provider = $Provider
        Attempt = $Attempt
        Data = $Data
        ErrorRecord = $ErrorRecord
        ErrorClass = $ErrorClass
        ArtifactPath = $ArtifactPath
    }
    if ($PSBoundParameters.ContainsKey('ExitCode')) {
        $parameters.ExitCode = $ExitCode
    }

    return Write-VorceRequiredEvent @parameters
}

function Write-VorceStateEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('saved', 'save_failed')][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][object]$Context,
        [object]$Data = @{},
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass
    )

    return Write-VorceRequiredEvent -Category State -Event $State -Message $Message -Component 'run-engine' -Context $Context -Data $Data -ErrorRecord $ErrorRecord -ErrorClass $ErrorClass
}

function Write-VorceProcessEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('started', 'healthy', 'degraded', 'stopped', 'crashed')][string]$State,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][string]$Component,
        [int]$ProcessId,
        [object]$Data = @{},
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$ErrorClass,
        [int]$ExitCode
    )

    $parameters = @{
        Category = 'Process'
        Event = $State
        Message = $Message
        Component = $Component
        Context = $Context
        ProcessId = $ProcessId
        Data = $Data
        ErrorRecord = $ErrorRecord
        ErrorClass = $ErrorClass
    }
    if ($PSBoundParameters.ContainsKey('ExitCode')) {
        $parameters.ExitCode = $ExitCode
    }

    return Write-VorceRequiredEvent @parameters
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'unknown',
        [object]$Data = @{},
        [object]$Context
    )

    return Write-VorceLogEntry -Level $Level -Message $Message -Component $Component -Data $Data -Context $Context
}

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        os_version = $PSVersionTable.OS
        hostname = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
        powershell = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-ProcessInfo {
    [CmdletBinding()]
    param()

    try {
        return @(
            Get-Process | Where-Object {
                $_.ProcessName -match 'Vorce|vite|dashboard|sync-service|autopilot'
            } | Select-Object Id, ProcessName, Path
        )
    } catch {
        return @()
    }
}

function Write-VorceFatalReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Component = 'unknown',
        [object]$Data = @{},
        [object]$ProviderRegistry
    )

    $logRoot = Initialize-VorceLogDirectory
    $reportPath = Join-Path $logRoot ("crash-reports/crash-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $PID)
    $report = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        component = $Component
        message = Protect-VorceSecretText -Text $Message -ProviderRegistry $ProviderRegistry -MaxLength 500
        data = Protect-VorceLogValue -Value $Data -ProviderRegistry $ProviderRegistry
        system_info = Get-SystemInfo
        process_info = Get-ProcessInfo
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    return $reportPath
}
