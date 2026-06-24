# ProcessSupervisor.ps1
# PID-based process registry, identity verification, health and crash helpers.

function Get-VorceProcessRegistryPath {
    [CmdletBinding()]
    param(
        [string]$RegistryPath
    )

    if ($RegistryPath) {
        return [System.IO.Path]::GetFullPath($RegistryPath)
    }

    $varDir = Get-Variable -Name VarDir -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($varDir) {
        return [System.IO.Path]::GetFullPath((Join-Path $varDir 'tmp/vorce-processes.json'))
    }

    return [System.IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '../../../var/tmp/vorce-processes.json')
    )
}

function New-VorceProcessRegistry {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        schema_version = 1
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
        processes = @()
    }
}

function ConvertTo-VorceNormalizedPath {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
    } catch {
        return $Path.Trim().TrimEnd('\', '/')
    }
}

function Test-VorcePathEqual {
    [CmdletBinding()]
    param(
        [string]$Left,
        [string]$Right
    )

    $normalizedLeft = ConvertTo-VorceNormalizedPath -Path $Left
    $normalizedRight = ConvertTo-VorceNormalizedPath -Path $Right
    if ($null -eq $normalizedLeft -or $null -eq $normalizedRight) {
        return $false
    }

    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    return [string]::Equals($normalizedLeft, $normalizedRight, $comparison)
}

function Get-VorceRegistryMutexName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(
            (Get-VorceProcessRegistryPath -RegistryPath $RegistryPath).ToLowerInvariant()
        )
        $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
    } finally {
        $sha.Dispose()
    }

    $prefix = if ($env:OS -eq 'Windows_NT') { 'Local\' } else { '' }
    return "${prefix}VorceFactoryProcessRegistry_$($hash.Substring(0, 24))"
}

function Invoke-VorceProcessRegistryLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [ValidateRange(1, 120)]
        [int]$TimeoutSeconds = 10
    )

    $mutexName = Get-VorceRegistryMutexName -RegistryPath $RegistryPath
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $lockTaken = $false

    try {
        try {
            $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
        } catch [System.Threading.AbandonedMutexException] {
            $lockTaken = $true
        }

        if (-not $lockTaken) {
            throw "Timeout beim Sperren der Prozessregistry '$RegistryPath'."
        }

        return & $ScriptBlock
    } finally {
        if ($lockTaken) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Read-VorceProcessRegistry {
    [CmdletBinding()]
    param(
        [string]$RegistryPath
    )

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return New-VorceProcessRegistry
    }

    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Prozessregistry '$path' ist leer."
    }

    try {
        $registry = $raw | ConvertFrom-Json
    } catch {
        throw "Prozessregistry '$path' enthaelt ungueltiges JSON: $($_.Exception.Message)"
    }

    if ($null -eq $registry -or $registry.PSObject.Properties.Name -notcontains 'processes') {
        throw "Prozessregistry '$path' besitzt kein 'processes'-Feld."
    }

    $registry.processes = @($registry.processes | Where-Object { $null -ne $_ })
    if ($registry.PSObject.Properties.Name -notcontains 'schema_version') {
        $registry | Add-Member -MemberType NoteProperty -Name schema_version -Value 1
    }
    if ($registry.PSObject.Properties.Name -notcontains 'updated_at') {
        $registry | Add-Member -MemberType NoteProperty -Name updated_at -Value $null
    }

    return $registry
}

function Write-VorceProcessRegistryInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry,

        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    if ($Registry.PSObject.Properties.Name -notcontains 'schema_version') {
        $Registry | Add-Member -MemberType NoteProperty -Name schema_version -Value 1
    }
    if ($Registry.PSObject.Properties.Name -notcontains 'processes') {
        $Registry | Add-Member -MemberType NoteProperty -Name processes -Value @()
    }
    if ($Registry.PSObject.Properties.Name -contains 'updated_at') {
        $Registry.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    } else {
        $Registry | Add-Member -MemberType NoteProperty -Name updated_at `
            -Value (Get-Date).ToUniversalTime().ToString('o')
    }

    $Registry.processes = @($Registry.processes | Where-Object { $null -ne $_ })
    $json = $Registry | ConvertTo-Json -Depth 12
    $tempPath = Join-Path $parent (
        '.{0}.{1}.tmp' -f ([System.IO.Path]::GetFileName($path)), [guid]::NewGuid().ToString('N')
    )
    $backupPath = Join-Path $parent (
        '.{0}.{1}.bak' -f ([System.IO.Path]::GetFileName($path)), [guid]::NewGuid().ToString('N')
    )

    try {
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8WithoutBom)

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                [System.IO.File]::Replace($tempPath, $path, $backupPath, $true)
            } catch [System.PlatformNotSupportedException] {
                Move-Item -LiteralPath $tempPath -Destination $path -Force
            }
        } else {
            [System.IO.File]::Move($tempPath, $path)
        }
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $Registry
}

function Write-VorceProcessRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Registry,

        [string]$RegistryPath
    )

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    return Invoke-VorceProcessRegistryLock -RegistryPath $path -ScriptBlock {
        Write-VorceProcessRegistryInternal -Registry $Registry -RegistryPath $path
    }
}

function New-VorceProcessRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [Alias('Pid')]
        [int]$ProcessId,

        [Nullable[int]]$ParentPid,

        [string]$StartedAt = (Get-Date).ToUniversalTime().ToString('o'),

        [Parameter(Mandatory)]
        [string]$CommandPath,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Nullable[int]]$Port,

        [string]$HealthUrl,
        [string]$StdoutPath,
        [string]$StderrPath,
        [string]$SessionId,

        [ValidateSet('healthy', 'starting', 'degraded', 'stopped')]
        [string]$Status = 'starting',

        [ValidateSet('unknown', 'healthy', 'starting', 'degraded', 'stopped', 'stale')]
        [string]$Health = 'unknown'
    )

    return [pscustomobject][ordered]@{
        component = $Component
        pid = $ProcessId
        parent_pid = if ($null -ne $ParentPid) { [int]$ParentPid } else { $null }
        started_at = $StartedAt
        command_path = ConvertTo-VorceNormalizedPath -Path $CommandPath
        working_directory = ConvertTo-VorceNormalizedPath -Path $WorkingDirectory
        port = if ($null -ne $Port) { [int]$Port } else { $null }
        health_url = $HealthUrl
        stdout_path = $StdoutPath
        stderr_path = $StderrPath
        session_id = $SessionId
        status = $Status
        health = $Health
        last_health_at = $null
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Assert-VorceProcessRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record
    )

    $required = @(
        'component', 'pid', 'parent_pid', 'started_at', 'command_path',
        'working_directory', 'port', 'health_url', 'stdout_path',
        'stderr_path', 'session_id'
    )

    foreach ($name in $required) {
        if ($Record.PSObject.Properties.Name -notcontains $name) {
            throw "Prozessrecord besitzt kein Pflichtfeld '$name'."
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Record.component)) {
        throw 'Prozessrecord besitzt keine Komponente.'
    }
    if ([int]$Record.pid -le 0) {
        throw 'Prozessrecord besitzt keine gueltige PID.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.command_path) -or
        -not [System.IO.Path]::IsPathRooted([string]$Record.command_path)) {
        throw 'Prozessrecord benoetigt einen absoluten CommandPath.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Record.working_directory) -or
        -not [System.IO.Path]::IsPathRooted([string]$Record.working_directory)) {
        throw 'Prozessrecord benoetigt ein absolutes WorkingDirectory.'
    }
}

function Register-VorceProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,

        [string]$RegistryPath,

        [switch]$Replace
    )

    Assert-VorceProcessRecord -Record $Record
    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath

    return Invoke-VorceProcessRegistryLock -RegistryPath $path -ScriptBlock {
        $registry = Read-VorceProcessRegistry -RegistryPath $path
        $duplicates = @($registry.processes | Where-Object {
            $_.component -eq $Record.component -or [int]$_.pid -eq [int]$Record.pid
        })

        if ($duplicates.Count -gt 0 -and -not $Replace) {
            throw "Registry enthaelt bereits Komponente '$($Record.component)' oder PID '$($Record.pid)'."
        }

        if ($Replace) {
            $registry.processes = @($registry.processes | Where-Object {
                $_.component -ne $Record.component -and [int]$_.pid -ne [int]$Record.pid
            })
        }

        if ($Record.PSObject.Properties.Name -contains 'updated_at') {
            $Record.updated_at = (Get-Date).ToUniversalTime().ToString('o')
        } else {
            $Record | Add-Member -MemberType NoteProperty -Name updated_at `
                -Value (Get-Date).ToUniversalTime().ToString('o')
        }

        $registry.processes = @($registry.processes) + @($Record)
        Write-VorceProcessRegistryInternal -Registry $registry -RegistryPath $path | Out-Null
        return $Record
    }
}

function Update-VorceProcess {
    [CmdletBinding(DefaultParameterSetName = 'Component')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Component')]
        [string]$Component,

        [Parameter(Mandatory, ParameterSetName = 'Pid')]
        [ValidateRange(1, [int]::MaxValue)]
        [Alias('Pid')]
        [int]$ProcessId,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Changes,

        [string]$RegistryPath
    )

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    $findByComponent = $PSCmdlet.ParameterSetName -eq 'Component'
    return Invoke-VorceProcessRegistryLock -RegistryPath $path -ScriptBlock {
        $registry = Read-VorceProcessRegistry -RegistryPath $path
        $record = if ($findByComponent) {
            $registry.processes | Where-Object { $_.component -eq $Component } | Select-Object -First 1
        } else {
            $registry.processes | Where-Object { [int]$_.pid -eq $ProcessId } | Select-Object -First 1
        }

        if ($null -eq $record) {
            $identity = if ($findByComponent) { $Component } else { $ProcessId }
            throw "Kein Prozessrecord fuer '$identity' gefunden."
        }

        foreach ($name in $Changes.Keys) {
            if ($name -in @('component', 'pid')) {
                throw "Registry-Identitaetsfeld '$name' darf nicht aktualisiert werden."
            }

            if ($record.PSObject.Properties.Name -contains $name) {
                $record.$name = $Changes[$name]
            } else {
                $record | Add-Member -MemberType NoteProperty -Name $name -Value $Changes[$name]
            }
        }

        if ($Changes.Keys -contains 'health' -and $Changes.Keys -notcontains 'last_health_at') {
            if ($record.PSObject.Properties.Name -contains 'last_health_at') {
                $record.last_health_at = (Get-Date).ToUniversalTime().ToString('o')
            } else {
                $record | Add-Member -MemberType NoteProperty -Name last_health_at `
                    -Value (Get-Date).ToUniversalTime().ToString('o')
            }
        }
        if ($record.PSObject.Properties.Name -contains 'updated_at') {
            $record.updated_at = (Get-Date).ToUniversalTime().ToString('o')
        } else {
            $record | Add-Member -MemberType NoteProperty -Name updated_at `
                -Value (Get-Date).ToUniversalTime().ToString('o')
        }

        Assert-VorceProcessRecord -Record $record
        Write-VorceProcessRegistryInternal -Registry $registry -RegistryPath $path | Out-Null
        return $record
    }
}

function Remove-VorceProcess {
    [CmdletBinding()]
    param(
        [string]$Component,

        [ValidateRange(1, [int]::MaxValue)]
        [Alias('Pid')]
        [int]$ProcessId,

        [string]$RegistryPath
    )

    $hasProcessId = $PSBoundParameters.ContainsKey('ProcessId')
    if (-not $Component -and -not $hasProcessId) {
        throw 'Remove-VorceProcess benoetigt Component oder Pid.'
    }

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    return Invoke-VorceProcessRegistryLock -RegistryPath $path -ScriptBlock {
        $registry = Read-VorceProcessRegistry -RegistryPath $path
        $removed = @($registry.processes | Where-Object {
            $componentMatch = -not $Component -or $_.component -eq $Component
            $pidMatch = -not $hasProcessId -or [int]$_.pid -eq $ProcessId
            $componentMatch -and $pidMatch
        })

        if ($removed.Count -eq 0) {
            return $null
        }

        $registry.processes = @($registry.processes | Where-Object {
            $componentMatch = -not $Component -or $_.component -eq $Component
            $pidMatch = -not $hasProcessId -or [int]$_.pid -eq $ProcessId
            -not ($componentMatch -and $pidMatch)
        })
        Write-VorceProcessRegistryInternal -Registry $registry -RegistryPath $path | Out-Null
        return $removed[0]
    }
}

function Get-VorceProcessSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [Alias('Pid')]
        [int]$ProcessId
    )

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
    } catch {
        return [pscustomobject][ordered]@{
            pid = $ProcessId
            exists = $false
            executable_path = $null
            command_line = $null
            working_directory = $null
            parent_pid = $null
            started_at = $null
        }
    }

    $executablePath = $null
    $commandLine = $null
    $parentPid = $null
    try { $executablePath = $process.Path } catch {}

    if ($env:OS -eq 'Windows_NT' -and (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        try {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
            if ($cim) {
                if ($cim.ExecutablePath) { $executablePath = $cim.ExecutablePath }
                $commandLine = $cim.CommandLine
                $parentPid = $cim.ParentProcessId
            }
        } catch {
        }
    }

    $startedAt = $null
    try { $startedAt = $process.StartTime.ToUniversalTime().ToString('o') } catch {}
    $workingDirectory = if ($ProcessId -eq $PID) {
        ConvertTo-VorceNormalizedPath -Path (Get-Location).ProviderPath
    } else {
        $null
    }

    return [pscustomobject][ordered]@{
        pid = $ProcessId
        exists = $true
        executable_path = ConvertTo-VorceNormalizedPath -Path $executablePath
        command_line = $commandLine
        working_directory = $workingDirectory
        parent_pid = $parentPid
        started_at = $startedAt
    }
}

function Test-VorceCommandPathMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExpectedCommandPath,

        [object]$ProcessSnapshot
    )

    if ($null -eq $ProcessSnapshot -or -not $ProcessSnapshot.exists) {
        return $false
    }

    if (Test-VorcePathEqual -Left $ExpectedCommandPath -Right $ProcessSnapshot.executable_path) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace([string]$ProcessSnapshot.command_line)) {
        return $false
    }

    $expected = ConvertTo-VorceNormalizedPath -Path $ExpectedCommandPath
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }

    return $ProcessSnapshot.command_line.IndexOf($expected, $comparison) -ge 0
}

function Test-VorceProcessIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,

        [Parameter(Mandatory)]
        [string]$ExpectedCommandPath,

        [Parameter(Mandatory)]
        [string]$ExpectedWorkingDirectory,

        [object]$ProcessSnapshot
    )

    if ($null -eq $ProcessSnapshot) {
        $ProcessSnapshot = Get-VorceProcessSnapshot -Pid ([int]$Record.pid)
    }

    $safePid = [int]$Record.pid -gt 4
    $processExists = [bool]$ProcessSnapshot.exists
    $registryCommandMatch = Test-VorcePathEqual `
        -Left $Record.command_path `
        -Right $ExpectedCommandPath
    $registryWorkingDirectoryMatch = Test-VorcePathEqual `
        -Left $Record.working_directory `
        -Right $ExpectedWorkingDirectory
    $processCommandMatch = Test-VorceCommandPathMatch `
        -ExpectedCommandPath $ExpectedCommandPath `
        -ProcessSnapshot $ProcessSnapshot

    $observedWorkingDirectory = $ProcessSnapshot.working_directory
    $observedWorkingDirectoryMatch = if ($observedWorkingDirectory) {
        Test-VorcePathEqual -Left $ExpectedWorkingDirectory -Right $observedWorkingDirectory
    } else {
        $null
    }

    $verified = (
        $safePid -and
        $processExists -and
        $registryCommandMatch -and
        $registryWorkingDirectoryMatch -and
        $processCommandMatch -and
        ($null -eq $observedWorkingDirectoryMatch -or $observedWorkingDirectoryMatch)
    )

    $reason = if (-not $safePid) {
        'protected_pid'
    } elseif (-not $processExists) {
        'process_not_found'
    } elseif (-not $registryCommandMatch) {
        'registry_command_path_mismatch'
    } elseif (-not $registryWorkingDirectoryMatch) {
        'registry_working_directory_mismatch'
    } elseif (-not $processCommandMatch) {
        'running_command_path_mismatch'
    } elseif ($false -eq $observedWorkingDirectoryMatch) {
        'running_working_directory_mismatch'
    } else {
        'verified'
    }

    return [pscustomobject][ordered]@{
        component = $Record.component
        pid = [int]$Record.pid
        status = if (-not $processExists) { 'stopped' } elseif ($verified) { 'healthy' } else { 'degraded' }
        verified = $verified
        reason = $reason
        process_exists = $processExists
        safe_pid = $safePid
        registry_command_path_match = $registryCommandMatch
        registry_working_directory_match = $registryWorkingDirectoryMatch
        running_command_path_match = $processCommandMatch
        running_working_directory_match = $observedWorkingDirectoryMatch
        expected_command_path = ConvertTo-VorceNormalizedPath -Path $ExpectedCommandPath
        observed_command_path = $ProcessSnapshot.executable_path
        expected_working_directory = ConvertTo-VorceNormalizedPath -Path $ExpectedWorkingDirectory
        observed_working_directory = $observedWorkingDirectory
        checked_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Stop-VorceRegisteredProcess {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$ExpectedCommandPath,

        [Parameter(Mandatory)]
        [string]$ExpectedWorkingDirectory,

        [string]$RegistryPath,

        [ValidateRange(1, 60)]
        [int]$WaitTimeoutSeconds = 5,

        [switch]$Force
    )

    $path = Get-VorceProcessRegistryPath -RegistryPath $RegistryPath
    $registry = Read-VorceProcessRegistry -RegistryPath $path
    $record = $registry.processes |
        Where-Object { $_.component -eq $Component } |
        Select-Object -First 1

    if ($null -eq $record) {
        return [pscustomobject][ordered]@{
            component = $Component
            pid = $null
            status = 'stopped'
            stopped = $false
            registry_removed = $false
            verified = $false
            reason = 'not_registered'
            checked_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    $identity = Test-VorceProcessIdentity `
        -Record $record `
        -ExpectedCommandPath $ExpectedCommandPath `
        -ExpectedWorkingDirectory $ExpectedWorkingDirectory

    if ($identity.reason -eq 'process_not_found') {
        $removed = Remove-VorceProcess -Component $Component -Pid ([int]$record.pid) -RegistryPath $path
        return [pscustomobject][ordered]@{
            component = $Component
            pid = [int]$record.pid
            status = 'stopped'
            stopped = $false
            registry_removed = $null -ne $removed
            verified = $false
            reason = 'already_stopped'
            checked_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    if (-not $identity.verified) {
        return [pscustomobject][ordered]@{
            component = $Component
            pid = [int]$record.pid
            status = 'degraded'
            stopped = $false
            registry_removed = $false
            verified = $false
            reason = $identity.reason
            identity = $identity
            checked_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    $target = "{0} PID {1}" -f $Component, $record.pid
    if (-not $PSCmdlet.ShouldProcess($target, 'Stop verified registered process')) {
        return [pscustomobject][ordered]@{
            component = $Component
            pid = [int]$record.pid
            status = $identity.status
            stopped = $false
            registry_removed = $false
            verified = $true
            reason = 'not_executed'
            checked_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    Stop-Process -Id ([int]$record.pid) -Force:$Force -ErrorAction Stop
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 100
        $stillRunning = $null -ne (Get-Process -Id ([int]$record.pid) -ErrorAction SilentlyContinue)
    } while ($stillRunning -and (Get-Date) -lt $deadline)

    if ($stillRunning) {
        return [pscustomobject][ordered]@{
            component = $Component
            pid = [int]$record.pid
            status = 'degraded'
            stopped = $false
            registry_removed = $false
            verified = $true
            reason = 'stop_timeout'
            checked_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    $removed = Remove-VorceProcess -Component $Component -Pid ([int]$record.pid) -RegistryPath $path
    return [pscustomobject][ordered]@{
        component = $Component
        pid = [int]$record.pid
        status = 'stopped'
        stopped = $true
        registry_removed = $null -ne $removed
        verified = $true
        reason = 'stopped'
        checked_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-VorceHeartbeatStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HeartbeatPath,

        [ValidateRange(1, 86400)]
        [int]$StaleAfterSeconds = 60,

        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $path = [System.IO.Path]::GetFullPath($HeartbeatPath)
    $checkedAt = $Now.ToUniversalTime()
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            path = $path
            status = 'missing'
            healthy = $false
            last_heartbeat_at = $null
            age_seconds = $null
            stale_after_seconds = $StaleAfterSeconds
            reason = 'heartbeat_file_missing'
            checked_at = $checkedAt.ToString('o')
        }
    }

    $file = Get-Item -LiteralPath $path
    $lastHeartbeat = $null
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $heartbeat = $raw | ConvertFrom-Json
            foreach ($field in @('timestamp', 'updated_at', 'heartbeat_at', 'last_seen_at')) {
                if ($heartbeat.PSObject.Properties.Name -contains $field -and $heartbeat.$field) {
                    $lastHeartbeat = [datetime]::Parse(
                        [string]$heartbeat.$field,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::RoundtripKind
                    ).ToUniversalTime()
                    break
                }
            }
        } catch {
            $lastHeartbeat = $null
        }
    }

    if ($null -eq $lastHeartbeat) {
        $lastHeartbeat = $file.LastWriteTimeUtc
    }

    $ageSeconds = [math]::Max(0, ($checkedAt - $lastHeartbeat).TotalSeconds)
    $healthy = $ageSeconds -le $StaleAfterSeconds
    return [pscustomobject][ordered]@{
        path = $path
        status = if ($healthy) { 'healthy' } else { 'stale' }
        healthy = $healthy
        last_heartbeat_at = $lastHeartbeat.ToString('o')
        age_seconds = [math]::Round($ageSeconds, 3)
        stale_after_seconds = $StaleAfterSeconds
        reason = if ($healthy) { 'heartbeat_current' } else { 'heartbeat_stale' }
        checked_at = $checkedAt.ToString('o')
    }
}

function Get-VorceProcessStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,

        [string]$ExpectedCommandPath = $Record.command_path,
        [string]$ExpectedWorkingDirectory = $Record.working_directory,
        [string]$HeartbeatPath,

        [ValidateRange(1, 86400)]
        [int]$HeartbeatStaleAfterSeconds = 60,

        [object]$ProcessSnapshot
    )

    $identity = Test-VorceProcessIdentity `
        -Record $Record `
        -ExpectedCommandPath $ExpectedCommandPath `
        -ExpectedWorkingDirectory $ExpectedWorkingDirectory `
        -ProcessSnapshot $ProcessSnapshot

    $heartbeat = if ($HeartbeatPath) {
        Get-VorceHeartbeatStatus `
            -HeartbeatPath $HeartbeatPath `
            -StaleAfterSeconds $HeartbeatStaleAfterSeconds
    } else {
        $null
    }

    $status = if (-not $identity.process_exists) {
        'stopped'
    } elseif (-not $identity.verified) {
        'degraded'
    } elseif ($heartbeat -and -not $heartbeat.healthy) {
        'degraded'
    } elseif ($heartbeat -and $heartbeat.healthy) {
        'healthy'
    } elseif ($Record.status -in @('healthy', 'starting', 'degraded', 'stopped')) {
        $Record.status
    } else {
        'starting'
    }

    return [pscustomobject][ordered]@{
        component = $Record.component
        pid = [int]$Record.pid
        status = $status
        healthy = $status -eq 'healthy'
        identity = $identity
        heartbeat = $heartbeat
        stdout_path = $Record.stdout_path
        stderr_path = $Record.stderr_path
        checked_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-VorceNonEmptyLogTail {
    [CmdletBinding()]
    param(
        [string]$Path,

        [ValidateRange(1, 1000)]
        [int]$LineCount = 30
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or
        -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($line in [System.IO.File]::ReadLines([System.IO.Path]::GetFullPath($Path))) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($queue.Count -ge $LineCount) {
            $null = $queue.Dequeue()
        }
        $queue.Enqueue($line)
    }

    return @($queue.ToArray())
}

function Get-VorceCrashExcerpt {
    [CmdletBinding()]
    param(
        [Nullable[int]]$ExitCode,
        [string]$StdoutPath,
        [string]$StderrPath,

        [ValidateRange(1, 30)]
        [int]$LinesPerStream = 30
    )

    $stdoutLines = @(Get-VorceNonEmptyLogTail -Path $StdoutPath -LineCount $LinesPerStream)
    $stderrLines = @(Get-VorceNonEmptyLogTail -Path $StderrPath -LineCount $LinesPerStream)
    $terminalLines = @(
        $stdoutLines | ForEach-Object { "[stdout] $_" }
        $stderrLines | ForEach-Object { "[stderr] $_" }
    )

    return [pscustomobject][ordered]@{
        status = 'crashed'
        exit_code = if ($null -ne $ExitCode) { [int]$ExitCode } else { $null }
        stdout_path = if ($StdoutPath) { [System.IO.Path]::GetFullPath($StdoutPath) } else { $null }
        stderr_path = if ($StderrPath) { [System.IO.Path]::GetFullPath($StderrPath) } else { $null }
        stdout_lines = $stdoutLines
        stderr_lines = $stderrLines
        terminal_lines = $terminalLines
        terminal_line_count = $terminalLines.Count
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}
