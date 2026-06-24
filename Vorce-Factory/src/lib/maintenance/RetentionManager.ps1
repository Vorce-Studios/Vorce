# RetentionManager.ps1
# Central, fail-closed retention for bounded runtime data below VarDir.

function Get-VorceRetentionValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default
    )

    if ($null -eq $InputObject) {
        return $Default
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ieq $Name) {
                return $InputObject[$key]
            }
        }
        return $Default
    }

    $property = $InputObject.PSObject.Properties |
        Where-Object { $_.Name -ieq $Name } |
        Select-Object -First 1
    if ($property) {
        return $property.Value
    }
    return $Default
}

function Set-VorceRetentionValue {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Name] = $Value
        return
    }
    $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Merge-VorceRetentionPolicy {
    param(
        [Parameter(Mandatory)][object]$Target,
        [Parameter(Mandatory)][object]$Source
    )

    $sourceEntries = if ($Source -is [System.Collections.IDictionary]) {
        @($Source.Keys | ForEach-Object {
            [pscustomobject]@{ Name = [string]$_; Value = $Source[$_] }
        })
    } else {
        @($Source.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Value = $_.Value }
        })
    }

    foreach ($entry in $sourceEntries) {
        $current = Get-VorceRetentionValue -InputObject $Target -Name $entry.Name -Default $null
        $sourceValue = $entry.Value
        $sourceIsObject = $null -ne $sourceValue -and
            ($sourceValue -is [System.Collections.IDictionary] -or
             ($sourceValue -isnot [string] -and
              $sourceValue.PSObject.Properties.Count -gt 0 -and
              $sourceValue -isnot [System.Collections.IEnumerable]))
        $currentIsObject = $null -ne $current -and
            ($current -is [System.Collections.IDictionary] -or
             ($current -isnot [string] -and
              $current.PSObject.Properties.Count -gt 0 -and
              $current -isnot [System.Collections.IEnumerable]))

        if ($sourceIsObject -and $currentIsObject) {
            Merge-VorceRetentionPolicy -Target $current -Source $sourceValue
        } else {
            Set-VorceRetentionValue -InputObject $Target -Name $entry.Name -Value $sourceValue
        }
    }
}

function New-VorceRetentionPolicy {
    [CmdletBinding()]
    param()

    return [ordered]@{
        schema_version = 1
        events = [ordered]@{
            enabled = $true
            root = 'log/events'
            max_age_days = 30
            compress_after_days = 2
        }
        sessions = [ordered]@{
            enabled = $true
            root = 'log/sessions'
            max_age_days = 30
            max_files = 30
        }
        error_log = [ordered]@{
            enabled = $true
            path = 'log/vorce-errors.log'
            max_size_bytes = 10485760
            generations = 5
        }
        process_logs = [ordered]@{
            enabled = $true
            root = 'log'
            max_age_days = 14
            patterns = @('stdout.log', 'stderr.log', '*.stdout.log', '*.stderr.log')
        }
        agent_artifacts = [ordered]@{
            enabled = $true
            root = 'tmp/agent-artifacts'
            successful_max_age_hours = 24
            failed_max_age_days = 7
        }
        config_backups = [ordered]@{
            enabled = $true
            root = 'config'
            max_files = 20
            patterns = @('*.bak', '*.bak.*', '*.backup', '*.backup.*')
        }
        archives = [ordered]@{
            enabled = $true
            roots = @('run-states-archive')
            max_age_days = 90
        }
        reports = [ordered]@{
            enabled = $true
            roots = @('log/crash-reports', 'analysis', 'performance', 'memory-maintenance')
            max_age_days = 30
        }
        history = [ordered]@{
            enabled = $false
            roots = @('run-history')
            max_age_days = 0
        }
        general_logs = [ordered]@{
            enabled = $true
            roots = @('log')
            max_age_days = 30
        }
        tmp = [ordered]@{
            enabled = $true
            roots = @('tmp')
            max_age_hours = 24
            excluded_roots = @('tmp/agent-artifacts')
        }
    }
}

function Import-VorceRetentionPolicy {
    [CmdletBinding()]
    param(
        [string]$PolicyPath,
        [object]$Policy
    )

    $result = New-VorceRetentionPolicy
    if ($Policy) {
        Merge-VorceRetentionPolicy -Target $result -Source $Policy
        return $result
    }
    if ([string]::IsNullOrWhiteSpace($PolicyPath) -or
        -not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
        return $result
    }

    $loaded = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Merge-VorceRetentionPolicy -Target $result -Source $loaded
    return $result
}

function ConvertTo-VorceRetentionFullPath {
    param([Parameter(Mandatory)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-VorceRetentionPathComparison {
    if ($env:OS -eq 'Windows_NT' -or $PSVersionTable.PSEdition -eq 'Desktop') {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Test-VorceRetentionPathInside {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [switch]$AllowRoot
    )

    try {
        $fullPath = ConvertTo-VorceRetentionFullPath -Path $Path
        $fullRoot = ConvertTo-VorceRetentionFullPath -Path $Root
    } catch {
        return $false
    }

    $comparison = Get-VorceRetentionPathComparison
    if ([string]::Equals($fullPath, $fullRoot, $comparison)) {
        return [bool]$AllowRoot
    }
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, $comparison)
}

function Test-VorceRetentionDangerousRoot {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = ConvertTo-VorceRetentionFullPath -Path $Path
    $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($pathRoot)) {
        return $true
    }
    return [string]::Equals(
        $fullPath,
        $pathRoot.TrimEnd('\', '/'),
        (Get-VorceRetentionPathComparison)
    )
}

function Test-VorceRetentionReparsePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    if (-not (Test-VorceRetentionPathInside -Path $Path -Root $Root -AllowRoot)) {
        return $true
    }

    $current = ConvertTo-VorceRetentionFullPath -Path $Path
    $stop = ConvertTo-VorceRetentionFullPath -Path $Root
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $true
            }
        }
        if ([string]::Equals($current, $stop, (Get-VorceRetentionPathComparison))) {
            break
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            return $true
        }
        $current = ConvertTo-VorceRetentionFullPath -Path $parent
    }
    return $false
}

function New-VorceRetentionCategoryReport {
    param([Parameter(Mandatory)][string]$Name)

    return [pscustomobject][ordered]@{
        category = $Name
        status = 'completed'
        scanned = 0
        candidates = 0
        planned = 0
        deleted = 0
        compressed = 0
        rotated = 0
        protected = 0
        skipped = 0
        rejected = 0
        errors = 0
        bytes_reclaimed = 0L
        messages = @()
    }
}

function Add-VorceRetentionMessage {
    param(
        [Parameter(Mandatory)][object]$Category,
        [Parameter(Mandatory)][string]$Message
    )

    if (@($Category.messages).Count -lt 20) {
        $Category.messages = @($Category.messages) + $Message
    }
}

function Test-VorceRetentionPattern {
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$Patterns
    )

    foreach ($pattern in @($Patterns)) {
        if ($Name -like [string]$pattern) {
            return $true
        }
    }
    return $false
}

function Test-VorceRetentionExcludedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ExcludedRoots
    )

    foreach ($excludedRoot in @($ExcludedRoots)) {
        if (Test-VorceRetentionPathInside -Path $Path -Root $excludedRoot -AllowRoot) {
            return $true
        }
    }
    return $false
}

function Get-VorceRetentionFiles {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$ExcludedRoots = @(),
        [Parameter(Mandatory)][object]$Category
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return @()
    }
    if (Test-VorceRetentionReparsePath -Path $Root -Root $Root) {
        $Category.protected++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message "Reparse-Root uebersprungen: $Root"
        return @()
    }

    $files = New-Object System.Collections.ArrayList
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue((ConvertTo-VorceRetentionFullPath -Path $Root))
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        try {
            $items = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
        } catch {
            $Category.errors++
            $Category.status = 'completed_with_warnings'
            Add-VorceRetentionMessage -Category $Category -Message $_.Exception.Message
            continue
        }

        foreach ($item in $items) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $Category.protected++
                Add-VorceRetentionMessage -Category $Category -Message "Reparse-Point uebersprungen: $($item.FullName)"
                continue
            }
            if (Test-VorceRetentionExcludedPath -Path $item.FullName -ExcludedRoots $ExcludedRoots) {
                $Category.skipped++
                continue
            }
            if ($item.PSIsContainer) {
                $queue.Enqueue($item.FullName)
            } else {
                $null = $files.Add($item)
            }
        }
    }
    return @($files)
}

function Test-VorceRetentionFileUnlocked {
    param([Parameter(Mandatory)][string]$Path)

    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
        return $true
    } catch {
        return $false
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Test-VorceRetentionProtectedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ProtectedPaths
    )

    foreach ($protectedPath in @($ProtectedPaths)) {
        if ([string]::IsNullOrWhiteSpace($protectedPath)) {
            continue
        }
        if ([string]::Equals(
            (ConvertTo-VorceRetentionFullPath -Path $Path),
            (ConvertTo-VorceRetentionFullPath -Path $protectedPath),
            (Get-VorceRetentionPathComparison)
        )) {
            return $true
        }
    }
    return $false
}

function Test-VorceRetentionProtectedTree {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ProtectedPaths
    )

    foreach ($protectedPath in @($ProtectedPaths)) {
        if ([string]::IsNullOrWhiteSpace($protectedPath)) {
            continue
        }
        if ((Test-VorceRetentionPathInside -Path $protectedPath -Root $Path -AllowRoot) -or
            (Test-VorceRetentionPathInside -Path $Path -Root $protectedPath -AllowRoot)) {
            return $true
        }
    }
    return $false
}

function Remove-VorceRetentionFile {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [Parameter(Mandatory)][string]$VarRoot,
        [string[]]$ProtectedPaths,
        [Parameter(Mandatory)][bool]$DryRun,
        [Parameter(Mandatory)][object]$Category,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $Category.candidates++
    if (-not (Test-VorceRetentionPathInside -Path $File.FullName -Root $AllowedRoot) -or
        -not (Test-VorceRetentionPathInside -Path $File.FullName -Root $VarRoot)) {
        $Category.rejected++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message "Pfad ausserhalb des erlaubten Roots: $($File.FullName)"
        return $false
    }
    if (Test-VorceRetentionReparsePath -Path $File.FullName -Root $AllowedRoot) {
        $Category.protected++
        return $false
    }
    if (Test-VorceRetentionProtectedPath -Path $File.FullName -ProtectedPaths $ProtectedPaths) {
        $Category.protected++
        return $false
    }
    if (-not (Test-VorceRetentionFileUnlocked -Path $File.FullName)) {
        $Category.protected++
        return $false
    }

    if ($DryRun) {
        $Category.planned++
        return $true
    }
    try {
        if ($Cmdlet.ShouldProcess($File.FullName, 'Delete retention candidate')) {
            $length = $File.Length
            Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
            $Category.deleted++
            $Category.bytes_reclaimed += $length
            return $true
        }
        $Category.planned++
    } catch {
        $Category.errors++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message $_.Exception.Message
    }
    return $false
}

function Compress-VorceRetentionFile {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [Parameter(Mandatory)][string]$VarRoot,
        [string[]]$ProtectedPaths,
        [Parameter(Mandatory)][bool]$DryRun,
        [Parameter(Mandatory)][object]$Category,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $Category.candidates++
    $destination = "$($File.FullName).gz"
    if (-not (Test-VorceRetentionPathInside -Path $File.FullName -Root $AllowedRoot) -or
        -not (Test-VorceRetentionPathInside -Path $destination -Root $AllowedRoot) -or
        -not (Test-VorceRetentionPathInside -Path $File.FullName -Root $VarRoot)) {
        $Category.rejected++
        $Category.status = 'completed_with_warnings'
        return $false
    }
    if ((Test-VorceRetentionReparsePath -Path $File.FullName -Root $AllowedRoot) -or
        (Test-VorceRetentionProtectedPath -Path $File.FullName -ProtectedPaths $ProtectedPaths) -or
        -not (Test-VorceRetentionFileUnlocked -Path $File.FullName)) {
        $Category.protected++
        return $false
    }
    if (Test-Path -LiteralPath $destination) {
        $Category.skipped++
        Add-VorceRetentionMessage -Category $Category -Message "Gzip-Ziel existiert bereits: $destination"
        return $false
    }
    if ($DryRun) {
        $Category.planned++
        return $true
    }

    $input = $null
    $output = $null
    $gzip = $null
    $tempPath = "$destination.tmp"
    try {
        if (-not $Cmdlet.ShouldProcess($File.FullName, 'Compress retention candidate with gzip')) {
            $Category.planned++
            return $false
        }
        $input = New-Object System.IO.FileStream(
            $File.FullName,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None
        )
        $output = New-Object System.IO.FileStream(
            $tempPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $gzip = New-Object System.IO.Compression.GZipStream(
            $output,
            [System.IO.Compression.CompressionMode]::Compress
        )
        $input.CopyTo($gzip)
        $gzip.Dispose()
        $gzip = $null
        $output.Dispose()
        $output = $null
        $input.Dispose()
        $input = $null
        Move-Item -LiteralPath $tempPath -Destination $destination -ErrorAction Stop
        (Get-Item -LiteralPath $destination).LastWriteTimeUtc = $File.LastWriteTimeUtc
        $originalLength = $File.Length
        Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
        $compressedLength = (Get-Item -LiteralPath $destination).Length
        $Category.compressed++
        $Category.bytes_reclaimed += [math]::Max(0, $originalLength - $compressedLength)
        return $true
    } catch {
        $Category.errors++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message $_.Exception.Message
    } finally {
        if ($gzip) { $gzip.Dispose() }
        if ($output) { $output.Dispose() }
        if ($input) { $input.Dispose() }
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $false
}

function Get-VorceRetentionActiveState {
    param(
        [Parameter(Mandatory)][string]$VarRoot,
        [string]$RegistryPath,
        [string[]]$ActiveSessionIds
    )

    $paths = New-Object System.Collections.ArrayList
    $sessions = New-Object System.Collections.ArrayList
    foreach ($sessionId in @($ActiveSessionIds)) {
        if (-not [string]::IsNullOrWhiteSpace($sessionId) -and -not $sessions.Contains($sessionId)) {
            $null = $sessions.Add($sessionId)
        }
    }

    if ($global:VorceLogContext) {
        $globalSessionId = [string](Get-VorceRetentionValue -InputObject $global:VorceLogContext -Name 'session_id' -Default $null)
        if (-not [string]::IsNullOrWhiteSpace($globalSessionId) -and -not $sessions.Contains($globalSessionId)) {
            $null = $sessions.Add($globalSessionId)
        }
    }

    if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
        $RegistryPath = Join-Path $VarRoot 'tmp/vorce-processes.json'
    }
    $registryExists = Test-Path -LiteralPath $RegistryPath -PathType Leaf
    if ($registryExists) {
        $null = $paths.Add((ConvertTo-VorceRetentionFullPath -Path $RegistryPath))
    }

    $registryError = $null
    if ($registryExists) {
        try {
            $registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $registry -or $registry.PSObject.Properties.Name -notcontains 'processes') {
                throw 'Prozessregistry besitzt kein processes-Feld.'
            }
            foreach ($record in @($registry.processes)) {
                foreach ($field in @('stdout_path', 'stderr_path')) {
                    $path = [string](Get-VorceRetentionValue -InputObject $record -Name $field -Default $null)
                    if (-not [string]::IsNullOrWhiteSpace($path)) {
                        if (-not [System.IO.Path]::IsPathRooted($path)) {
                            $path = Join-Path $VarRoot $path
                        }
                        $null = $paths.Add((ConvertTo-VorceRetentionFullPath -Path $path))
                    }
                }
                $sessionId = [string](Get-VorceRetentionValue -InputObject $record -Name 'session_id' -Default $null)
                if (-not [string]::IsNullOrWhiteSpace($sessionId) -and -not $sessions.Contains($sessionId)) {
                    $null = $sessions.Add($sessionId)
                }
            }
        } catch {
            $registryError = $_.Exception.Message
        }
    }

    foreach ($sessionId in @($sessions)) {
        $null = $paths.Add((Join-Path $VarRoot "log/sessions/$sessionId.log"))
    }

    return [pscustomobject][ordered]@{
        paths = @($paths | Select-Object -Unique)
        session_ids = @($sessions | Select-Object -Unique)
        registry_path = ConvertTo-VorceRetentionFullPath -Path $RegistryPath
        registry_error = $registryError
    }
}

function Add-VorceRetentionAttemptStatus {
    param(
        [AllowNull()][object]$Node,
        [Parameter(Mandatory)][hashtable]$Statuses
    )

    if ($null -eq $Node -or $Node -is [string] -or
        $Node -is [ValueType]) {
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and
        $Node -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Node) {
            Add-VorceRetentionAttemptStatus -Node $item -Statuses $Statuses
        }
        return
    }

    $attemptId = [string](Get-VorceRetentionValue -InputObject $Node -Name 'attempt_id' -Default $null)
    if (-not [string]::IsNullOrWhiteSpace($attemptId)) {
        $success = Get-VorceRetentionValue -InputObject $Node -Name 'success' -Default $null
        $status = [string](Get-VorceRetentionValue -InputObject $Node -Name 'status' -Default '')
        if ($success -eq $true -or $status -in @('completed', 'succeeded', 'success', 'attempt_succeeded')) {
            $Statuses[$attemptId] = 'successful'
        } elseif ($success -eq $false -or $status -in @('failed', 'error', 'attempt_failed')) {
            $Statuses[$attemptId] = 'failed'
        }
    }

    $values = if ($Node -is [System.Collections.IDictionary]) {
        @($Node.Values)
    } else {
        @($Node.PSObject.Properties | ForEach-Object { $_.Value })
    }
    foreach ($value in $values) {
        Add-VorceRetentionAttemptStatus -Node $value -Statuses $Statuses
    }
}

function Get-VorceRetentionAttemptStatuses {
    param([Parameter(Mandatory)][string]$VarRoot)

    $statuses = @{}
    $historyRoot = Join-Path $VarRoot 'run-history'
    if (-not (Test-Path -LiteralPath $historyRoot -PathType Container)) {
        return $statuses
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $historyRoot -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            Add-VorceRetentionAttemptStatus -Node $state -Statuses $statuses
        } catch {
            # History is read-only for retention; malformed entries are ignored conservatively.
        }
    }
    return $statuses
}

function Remove-VorceRetentionTree {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [Parameter(Mandatory)][string]$VarRoot,
        [string[]]$ProtectedPaths,
        [Parameter(Mandatory)][bool]$DryRun,
        [Parameter(Mandatory)][object]$Category,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $Category.candidates++
    if (-not (Test-VorceRetentionPathInside -Path $Path -Root $AllowedRoot) -or
        -not (Test-VorceRetentionPathInside -Path $Path -Root $VarRoot)) {
        $Category.rejected++
        $Category.status = 'completed_with_warnings'
        return $false
    }
    if ((Test-VorceRetentionReparsePath -Path $Path -Root $AllowedRoot) -or
        (Test-VorceRetentionProtectedTree -Path $Path -ProtectedPaths $ProtectedPaths)) {
        $Category.protected++
        return $false
    }

    $preflight = New-VorceRetentionCategoryReport -Name 'tree_preflight'
    $files = @(Get-VorceRetentionFiles -Root $Path -Category $preflight)
    if ($preflight.protected -gt 0 -or $preflight.errors -gt 0) {
        $Category.protected += $preflight.protected
        $Category.errors += $preflight.errors
        $Category.status = 'completed_with_warnings'
        return $false
    }
    foreach ($file in $files) {
        if ((Test-VorceRetentionProtectedPath -Path $file.FullName -ProtectedPaths $ProtectedPaths) -or
            -not (Test-VorceRetentionFileUnlocked -Path $file.FullName)) {
            $Category.protected++
            return $false
        }
    }

    if ($DryRun) {
        $Category.planned++
        return $true
    }
    try {
        if (-not $Cmdlet.ShouldProcess($Path, 'Delete retention directory tree')) {
            $Category.planned++
            return $false
        }
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        foreach ($file in $files) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        }
        $directories = @(Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction Stop |
            Sort-Object { $_.FullName.Length } -Descending)
        foreach ($directory in $directories) {
            Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        $Category.deleted++
        $Category.bytes_reclaimed += [long]$bytes
        return $true
    } catch {
        $Category.errors++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message $_.Exception.Message
    }
    return $false
}

function Resolve-VorceRetentionRoot {
    param(
        [Parameter(Mandatory)][string]$VarRoot,
        [Parameter(Mandatory)][string]$RelativeRoot,
        [Parameter(Mandatory)][string]$CategoryName,
        [Parameter(Mandatory)][object]$Category
    )

    try {
        $candidate = if ([System.IO.Path]::IsPathRooted($RelativeRoot)) {
            ConvertTo-VorceRetentionFullPath -Path $RelativeRoot
        } else {
            ConvertTo-VorceRetentionFullPath -Path (Join-Path $VarRoot $RelativeRoot)
        }
        if (-not (Test-VorceRetentionPathInside -Path $candidate -Root $VarRoot)) {
            throw "Policy-Root liegt ausserhalb VarDir: $RelativeRoot"
        }
        if (Test-VorceRetentionDangerousRoot -Path $candidate) {
            throw "Gefaehrlicher Policy-Root: $candidate"
        }

        $relative = $candidate.Substring($VarRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $hardProtected = @('db', 'run-states')
        if ($relative -in $hardProtected -or
            @($hardProtected | Where-Object { $relative.StartsWith("$_/") }).Count -gt 0) {
            throw "Policy-Root ist hart geschuetzt: $relative"
        }
        if (($relative -eq 'config' -or $relative.StartsWith('config/')) -and
            $CategoryName -ne 'config_backups') {
            throw "Config-Root ist nur fuer config_backups erlaubt: $relative"
        }
        if ((Test-Path -LiteralPath $candidate) -and
            (Test-VorceRetentionReparsePath -Path $candidate -Root $candidate)) {
            throw "Policy-Root darf kein Reparse-Point sein: $candidate"
        }
        return $candidate
    } catch {
        $Category.rejected++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message $_.Exception.Message
        return $null
    }
}

function Invoke-VorceRetentionAgePolicy {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$VarRoot,
        [Parameter(Mandatory)][datetime]$Now,
        [string[]]$ProtectedPaths,
        [Parameter(Mandatory)][bool]$DryRun,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Cmdlet,
        [string[]]$AdditionalExcludedRoots = @(),
        [object[]]$Patterns = @()
    )

    $category = New-VorceRetentionCategoryReport -Name $Name
    if (-not [bool](Get-VorceRetentionValue -InputObject $Settings -Name 'enabled' -Default $false)) {
        $category.status = 'policy_disabled'
        return $category
    }

    $maxAgeHours = Get-VorceRetentionValue -InputObject $Settings -Name 'max_age_hours' -Default $null
    if ($null -eq $maxAgeHours) {
        $maxAgeDays = [double](Get-VorceRetentionValue -InputObject $Settings -Name 'max_age_days' -Default 0)
        $maxAgeHours = $maxAgeDays * 24
    }
    $cutoff = $Now.ToUniversalTime().AddHours(-[double]$maxAgeHours)
    $roots = @(Get-VorceRetentionValue -InputObject $Settings -Name 'roots' -Default @())
    if ($roots.Count -eq 0) {
        $singleRoot = [string](Get-VorceRetentionValue -InputObject $Settings -Name 'root' -Default '')
        if ($singleRoot) { $roots = @($singleRoot) }
    }

    foreach ($relativeRoot in $roots) {
        $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot -RelativeRoot ([string]$relativeRoot) -CategoryName $Name -Category $category
        if (-not $root) { continue }
        $excludedRoots = @($AdditionalExcludedRoots)
        foreach ($relativeExcluded in @(Get-VorceRetentionValue -InputObject $Settings -Name 'excluded_roots' -Default @())) {
            $excluded = Resolve-VorceRetentionRoot -VarRoot $VarRoot -RelativeRoot ([string]$relativeExcluded) -CategoryName $Name -Category $category
            if ($excluded) { $excludedRoots += $excluded }
        }

        $files = @(Get-VorceRetentionFiles -Root $root -ExcludedRoots $excludedRoots -Category $category)
        foreach ($file in $files) {
            $category.scanned++
            if ($Patterns.Count -gt 0 -and -not (Test-VorceRetentionPattern -Name $file.Name -Patterns $Patterns)) {
                continue
            }
            if ($file.LastWriteTimeUtc -lt $cutoff) {
                $null = Remove-VorceRetentionFile -File $file -AllowedRoot $root -VarRoot $VarRoot `
                    -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
            }
        }
    }
    return $category
}

function Invoke-VorceRetentionEvents {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [datetime]$Now,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $category = New-VorceRetentionCategoryReport -Name 'events'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot `
        -RelativeRoot ([string](Get-VorceRetentionValue $Settings 'root' 'log/events')) `
        -CategoryName 'events' -Category $category
    if (-not $root) { return $category }

    $deleteCutoff = $Now.ToUniversalTime().AddDays(-[double](Get-VorceRetentionValue $Settings 'max_age_days' 30))
    $compressCutoff = $Now.ToUniversalTime().AddDays(-[double](Get-VorceRetentionValue $Settings 'compress_after_days' 2))
    foreach ($file in @(Get-VorceRetentionFiles -Root $root -Category $category)) {
        $category.scanned++
        if ($file.Name -notlike 'vorce-events-*.jsonl' -and
            $file.Name -notlike 'vorce-events-*.jsonl.gz') {
            continue
        }
        if ($file.LastWriteTimeUtc -lt $deleteCutoff) {
            $null = Remove-VorceRetentionFile -File $file -AllowedRoot $root -VarRoot $VarRoot `
                -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
        } elseif ($file.Extension -eq '.jsonl' -and $file.LastWriteTimeUtc -lt $compressCutoff) {
            $null = Compress-VorceRetentionFile -File $file -AllowedRoot $root -VarRoot $VarRoot `
                -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
        }
    }
    return $category
}

function Invoke-VorceRetentionSessions {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [datetime]$Now,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $category = New-VorceRetentionCategoryReport -Name 'sessions'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot `
        -RelativeRoot ([string](Get-VorceRetentionValue $Settings 'root' 'log/sessions')) `
        -CategoryName 'sessions' -Category $category
    if (-not $root) { return $category }

    $cutoff = $Now.ToUniversalTime().AddDays(-[double](Get-VorceRetentionValue $Settings 'max_age_days' 30))
    $maxFiles = [math]::Max(0, [int](Get-VorceRetentionValue $Settings 'max_files' 30))
    $files = @(Get-VorceRetentionFiles -Root $root -Category $category |
        Where-Object { $_.Name -like '*.log' } |
        Sort-Object LastWriteTimeUtc -Descending)
    $category.scanned += $files.Count
    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        if ($file.LastWriteTimeUtc -lt $cutoff -or $index -ge $maxFiles) {
            $null = Remove-VorceRetentionFile -File $file -AllowedRoot $root -VarRoot $VarRoot `
                -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
        }
    }
    return $category
}

function Invoke-VorceRetentionErrorLog {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $category = New-VorceRetentionCategoryReport -Name 'error_log'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $relativePath = [string](Get-VorceRetentionValue $Settings 'path' 'log/vorce-errors.log')
    $parentRelative = Split-Path -Parent $relativePath
    $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot -RelativeRoot $parentRelative `
        -CategoryName 'error_log' -Category $category
    if (-not $root) { return $category }
    $path = ConvertTo-VorceRetentionFullPath -Path (Join-Path $VarRoot $relativePath)
    $generations = [math]::Max(1, [int](Get-VorceRetentionValue $Settings 'generations' 5))

    foreach ($generationFile in @(Get-ChildItem -LiteralPath $root -Filter 'vorce-errors.log.*' -File -ErrorAction SilentlyContinue)) {
        $category.scanned++
        if ($generationFile.Name -match '^vorce-errors\.log\.(\d+)$' -and [int]$Matches[1] -gt $generations) {
            $null = Remove-VorceRetentionFile -File $generationFile -AllowedRoot $root -VarRoot $VarRoot `
                -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
        }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $category
    }

    $current = Get-Item -LiteralPath $path
    $category.scanned++
    if ($current.Length -le [long](Get-VorceRetentionValue $Settings 'max_size_bytes' 10485760)) {
        return $category
    }
    $category.candidates++
    if ((Test-VorceRetentionProtectedPath -Path $path -ProtectedPaths $ProtectedPaths) -or
        (Test-VorceRetentionReparsePath -Path $path -Root $root) -or
        -not (Test-VorceRetentionFileUnlocked -Path $path)) {
        $category.protected++
        return $category
    }
    foreach ($index in 1..$generations) {
        $generationPath = "$path.$index"
        if (Test-Path -LiteralPath $generationPath -PathType Leaf) {
            if ((Test-VorceRetentionReparsePath -Path $generationPath -Root $root) -or
                -not (Test-VorceRetentionFileUnlocked -Path $generationPath)) {
                $category.protected++
                return $category
            }
        }
    }
    if ($DryRun) {
        $category.planned++
        return $category
    }

    try {
        if (-not $Cmdlet.ShouldProcess($path, "Rotate error log with $generations generations")) {
            $category.planned++
            return $category
        }
        $oldest = "$path.$generations"
        if (Test-Path -LiteralPath $oldest -PathType Leaf) {
            Remove-Item -LiteralPath $oldest -Force -ErrorAction Stop
        }
        for ($index = $generations - 1; $index -ge 1; $index--) {
            $source = "$path.$index"
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                Move-Item -LiteralPath $source -Destination "$path.$($index + 1)" -Force -ErrorAction Stop
            }
        }
        Move-Item -LiteralPath $path -Destination "$path.1" -Force -ErrorAction Stop
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($path, '', $encoding)
        foreach ($extraGeneration in @(Get-ChildItem -LiteralPath $root -Filter 'vorce-errors.log.*' -File -ErrorAction SilentlyContinue)) {
            if ($extraGeneration.Name -match '^vorce-errors\.log\.(\d+)$' -and
                [int]$Matches[1] -gt $generations) {
                Remove-Item -LiteralPath $extraGeneration.FullName -Force -ErrorAction Stop
            }
        }
        $category.rotated++
    } catch {
        $category.errors++
        $category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $category -Message $_.Exception.Message
    }
    return $category
}

function Invoke-VorceRetentionArtifacts {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [datetime]$Now,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $category = New-VorceRetentionCategoryReport -Name 'agent_artifacts'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot `
        -RelativeRoot ([string](Get-VorceRetentionValue $Settings 'root' 'tmp/agent-artifacts')) `
        -CategoryName 'agent_artifacts' -Category $category
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        return $category
    }

    $statuses = Get-VorceRetentionAttemptStatuses -VarRoot $VarRoot
    $successCutoff = $Now.ToUniversalTime().AddHours(
        -[double](Get-VorceRetentionValue $Settings 'successful_max_age_hours' 24)
    )
    $failedCutoff = $Now.ToUniversalTime().AddDays(
        -[double](Get-VorceRetentionValue $Settings 'failed_max_age_days' 7)
    )

    foreach ($mainDirectory in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
        if (($mainDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $category.protected++
            continue
        }
        foreach ($partDirectory in @(Get-ChildItem -LiteralPath $mainDirectory.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
            if (($partDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $category.protected++
                continue
            }
            foreach ($attemptDirectory in @(Get-ChildItem -LiteralPath $partDirectory.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                $category.scanned++
                if (($attemptDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $category.protected++
                    continue
                }
                $fixture = New-VorceRetentionCategoryReport -Name 'artifact_age'
                $artifactFiles = @(Get-VorceRetentionFiles -Root $attemptDirectory.FullName -Category $fixture)
                $lastWrite = if ($artifactFiles.Count -gt 0) {
                    @($artifactFiles | Sort-Object LastWriteTimeUtc -Descending)[0].LastWriteTimeUtc
                } else {
                    $attemptDirectory.LastWriteTimeUtc
                }
                $status = if ($statuses.ContainsKey($attemptDirectory.Name)) {
                    $statuses[$attemptDirectory.Name]
                } else {
                    'failed'
                }
                $cutoff = if ($status -eq 'successful') { $successCutoff } else { $failedCutoff }
                if ($lastWrite -lt $cutoff) {
                    $null = Remove-VorceRetentionTree -Path $attemptDirectory.FullName -AllowedRoot $root `
                        -VarRoot $VarRoot -ProtectedPaths $ProtectedPaths -DryRun $DryRun `
                        -Category $category -Cmdlet $Cmdlet
                }
            }
        }
    }
    return $category
}

function Invoke-VorceRetentionBackups {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $category = New-VorceRetentionCategoryReport -Name 'config_backups'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot `
        -RelativeRoot ([string](Get-VorceRetentionValue $Settings 'root' 'config')) `
        -CategoryName 'config_backups' -Category $category
    if (-not $root) { return $category }

    $patterns = @(Get-VorceRetentionValue $Settings 'patterns' @('*.bak', '*.backup'))
    $maxFiles = [math]::Max(0, [int](Get-VorceRetentionValue $Settings 'max_files' 20))
    $files = @(Get-VorceRetentionFiles -Root $root -Category $category |
        Where-Object { Test-VorceRetentionPattern -Name $_.Name -Patterns $patterns } |
        Sort-Object LastWriteTimeUtc -Descending)
    $category.scanned += $files.Count
    for ($index = $maxFiles; $index -lt $files.Count; $index++) {
        $null = Remove-VorceRetentionFile -File $files[$index] -AllowedRoot $root -VarRoot $VarRoot `
            -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
    }
    return $category
}

function Invoke-VorceRetentionGeneralLogs {
    param(
        [object]$Settings,
        [string]$VarRoot,
        [datetime]$Now,
        [string[]]$ProtectedPaths,
        [bool]$DryRun,
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $excluded = @(
        (Join-Path $VarRoot 'log/events'),
        (Join-Path $VarRoot 'log/sessions'),
        (Join-Path $VarRoot 'log/crash-reports')
    )
    $category = New-VorceRetentionCategoryReport -Name 'general_logs'
    if (-not [bool](Get-VorceRetentionValue $Settings 'enabled' $false)) {
        $category.status = 'policy_disabled'
        return $category
    }
    $cutoff = $Now.ToUniversalTime().AddDays(-[double](Get-VorceRetentionValue $Settings 'max_age_days' 30))
    foreach ($relativeRoot in @(Get-VorceRetentionValue $Settings 'roots' @('log'))) {
        $root = Resolve-VorceRetentionRoot -VarRoot $VarRoot -RelativeRoot ([string]$relativeRoot) `
            -CategoryName 'general_logs' -Category $category
        if (-not $root) { continue }
        foreach ($file in @(Get-VorceRetentionFiles -Root $root -ExcludedRoots $excluded -Category $category)) {
            $category.scanned++
            if ($file.Name -like 'vorce-errors.log*' -or
                (Test-VorceRetentionPattern -Name $file.Name -Patterns @('stdout.log', 'stderr.log', '*.stdout.log', '*.stderr.log'))) {
                continue
            }
            if ($file.LastWriteTimeUtc -lt $cutoff) {
                $null = Remove-VorceRetentionFile -File $file -AllowedRoot $root -VarRoot $VarRoot `
                    -ProtectedPaths $ProtectedPaths -DryRun $DryRun -Category $category -Cmdlet $Cmdlet
            }
        }
    }
    return $category
}

function Write-VorceRetentionCleanupEvent {
    param(
        [Parameter(Mandatory)][object]$Category,
        [Parameter(Mandatory)][bool]$DryRun
    )

    if ($DryRun -or -not (Get-Command Write-VorceLogEntry -ErrorAction SilentlyContinue)) {
        return
    }
    try {
        $level = if ($Category.errors -gt 0 -or $Category.rejected -gt 0) { 'WARN' } else { 'INFO' }
        $null = Write-VorceLogEntry -Level $level -Message "Retention cleanup: $($Category.category)" `
            -Component 'retention' -EventType 'cleanup' -Status $Category.status -SkipTerminal `
            -Data ([ordered]@{
                path_category = $Category.category
                scanned = $Category.scanned
                candidates = $Category.candidates
                deleted = $Category.deleted
                compressed = $Category.compressed
                rotated = $Category.rotated
                protected = $Category.protected
                rejected = $Category.rejected
                errors = $Category.errors
                bytes_reclaimed = $Category.bytes_reclaimed
            })
    } catch {
        $Category.errors++
        $Category.status = 'completed_with_warnings'
        Add-VorceRetentionMessage -Category $Category -Message "Cleanup-Event konnte nicht geschrieben werden: $($_.Exception.Message)"
    }
}

function Invoke-VorceRetention {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$VarRoot,
        [string]$PolicyPath,
        [object]$Policy,
        [string]$RegistryPath,
        [string[]]$ActiveSessionIds = @(),
        [datetime]$Now = (Get-Date).ToUniversalTime(),
        [bool]$DryRun = $true
    )

    $startedAt = (Get-Date).ToUniversalTime()
    $effectiveDryRun = $DryRun -or [bool]$WhatIfPreference
    $report = [pscustomobject][ordered]@{
        schema_version = 1
        status = 'completed'
        dry_run = $effectiveDryRun
        started_at = $startedAt.ToString('o')
        completed_at = $null
        var_root = $null
        policy_path = $PolicyPath
        registry_path = $null
        protected_session_ids = @()
        protected_path_count = 0
        categories = @()
        totals = $null
        errors = @()
    }

    try {
        $fullVarRoot = ConvertTo-VorceRetentionFullPath -Path $VarRoot
        $report.var_root = $fullVarRoot
        if (Test-VorceRetentionDangerousRoot -Path $fullVarRoot) {
            throw "VarRoot darf kein Dateisystem-Root sein: $fullVarRoot"
        }
        if (-not (Test-Path -LiteralPath $fullVarRoot -PathType Container)) {
            throw "VarRoot existiert nicht: $fullVarRoot"
        }
        if (Test-VorceRetentionReparsePath -Path $fullVarRoot -Root $fullVarRoot) {
            throw "VarRoot darf kein Reparse-Point sein: $fullVarRoot"
        }

        $effectivePolicy = Import-VorceRetentionPolicy -PolicyPath $PolicyPath -Policy $Policy
        $active = Get-VorceRetentionActiveState -VarRoot $fullVarRoot `
            -RegistryPath $RegistryPath -ActiveSessionIds $ActiveSessionIds
        $report.registry_path = $active.registry_path
        $report.protected_session_ids = @($active.session_ids)
        $report.protected_path_count = @($active.paths).Count
        if ($active.registry_error) {
            $report.status = 'safety_blocked'
            $report.errors = @("Prozessregistry unlesbar; Cleanup fail-closed: $($active.registry_error)")
            return $report
        }

        $categories = New-Object System.Collections.ArrayList
        $null = $categories.Add((Invoke-VorceRetentionEvents `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'events' $null) `
            -VarRoot $fullVarRoot -Now $Now -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))
        $null = $categories.Add((Invoke-VorceRetentionSessions `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'sessions' $null) `
            -VarRoot $fullVarRoot -Now $Now -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))
        $null = $categories.Add((Invoke-VorceRetentionErrorLog `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'error_log' $null) `
            -VarRoot $fullVarRoot -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))

        $processSettings = Get-VorceRetentionValue $effectivePolicy 'process_logs' $null
        $null = $categories.Add((Invoke-VorceRetentionAgePolicy -Name 'process_logs' `
            -Settings $processSettings -VarRoot $fullVarRoot -Now $Now `
            -ProtectedPaths $active.paths -DryRun $effectiveDryRun -Cmdlet $PSCmdlet `
            -Patterns @(Get-VorceRetentionValue $processSettings 'patterns' @())))
        $null = $categories.Add((Invoke-VorceRetentionArtifacts `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'agent_artifacts' $null) `
            -VarRoot $fullVarRoot -Now $Now -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))
        $null = $categories.Add((Invoke-VorceRetentionBackups `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'config_backups' $null) `
            -VarRoot $fullVarRoot -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))

        foreach ($name in @('archives', 'reports', 'history', 'tmp')) {
            $settings = Get-VorceRetentionValue $effectivePolicy $name $null
            $null = $categories.Add((Invoke-VorceRetentionAgePolicy -Name $name `
                -Settings $settings -VarRoot $fullVarRoot -Now $Now `
                -ProtectedPaths $active.paths -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))
        }
        $null = $categories.Add((Invoke-VorceRetentionGeneralLogs `
            -Settings (Get-VorceRetentionValue $effectivePolicy 'general_logs' $null) `
            -VarRoot $fullVarRoot -Now $Now -ProtectedPaths $active.paths `
            -DryRun $effectiveDryRun -Cmdlet $PSCmdlet))

        $report.categories = @($categories)
        foreach ($category in $report.categories) {
            Write-VorceRetentionCleanupEvent -Category $category -DryRun $effectiveDryRun
        }
        if (@($report.categories | Where-Object {
            $_.errors -gt 0 -or $_.rejected -gt 0
        }).Count -gt 0) {
            $report.status = 'completed_with_warnings'
        }
    } catch {
        $report.status = 'safety_blocked'
        $report.errors = @($_.Exception.Message)
    } finally {
        $report.completed_at = (Get-Date).ToUniversalTime().ToString('o')
        $report.totals = [pscustomobject][ordered]@{
            scanned = ($report.categories | Measure-Object scanned -Sum).Sum
            candidates = ($report.categories | Measure-Object candidates -Sum).Sum
            planned = ($report.categories | Measure-Object planned -Sum).Sum
            deleted = ($report.categories | Measure-Object deleted -Sum).Sum
            compressed = ($report.categories | Measure-Object compressed -Sum).Sum
            rotated = ($report.categories | Measure-Object rotated -Sum).Sum
            protected = ($report.categories | Measure-Object protected -Sum).Sum
            skipped = ($report.categories | Measure-Object skipped -Sum).Sum
            rejected = ($report.categories | Measure-Object rejected -Sum).Sum
            errors = ($report.categories | Measure-Object errors -Sum).Sum
            bytes_reclaimed = ($report.categories | Measure-Object bytes_reclaimed -Sum).Sum
        }
    }

    return $report
}
