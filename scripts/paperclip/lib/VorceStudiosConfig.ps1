Set-StrictMode -Version Latest

function Get-VorceStudiosRoot {
    $root = Join-Path $PSScriptRoot '..\..\..'
    return (Resolve-Path $root).Path
}

function Get-VorceStudiosSystemPolicy {
    return Import-PowerShellDataFile -Path (Join-Path (Get-VorceStudiosRoot) 'ops\paperclip\policies\system.psd1')
}

function Get-VorceStudiosPolicy {
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $path = Join-Path (Get-VorceStudiosRoot) ("ops\paperclip\policies\{0}.psd1" -f $Name)
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Policy '$Name' wurde nicht gefunden: $path"
    }

    return Import-PowerShellDataFile -Path $path
}

function Get-VorceStudiosPaths {
    $root = Get-VorceStudiosRoot
    $system = Get-VorceStudiosSystemPolicy

    $paperclipHome = Join-Path $root '.paperclip-home'
    $runtimeRoot = Join-Path $paperclipHome 'runtime\vorce-studios'

    return [ordered]@{
        Root                 = $root
        PaperclipConfigDir   = Join-Path $root '.paperclip'
        PaperclipConfigPath  = Join-Path $root '.paperclip\config.json'
        PaperclipEnvPath     = Join-Path $root '.paperclip\.env'
        PaperclipHome        = $paperclipHome
        PluginSourcesDir     = Join-Path $paperclipHome 'vendor-plugins'
        RuntimeRoot          = $runtimeRoot
        RuntimeLogDir        = Join-Path $runtimeRoot 'logs'
        RuntimeStatePath     = Join-Path $runtimeRoot 'runtime-state.json'
        CompanyStatePath     = Join-Path $runtimeRoot 'company-state.json'
        CapacityLedgerPath   = Join-Path $runtimeRoot 'capacity-ledger.json'
        ProcessStatePath     = Join-Path $runtimeRoot 'process-state.json'
        AfkModeStatePath     = Join-Path $runtimeRoot 'afk-mode.json'
        PlanningSnapshotPath = Join-Path $runtimeRoot 'planning-snapshot.json'
        PluginPatchStatePath = Join-Path $runtimeRoot 'plugin-patch-state.json'
        SupervisorLockPath   = Join-Path $runtimeRoot 'supervisor.lock'
        PoliciesDir          = Join-Path $root 'ops\paperclip\policies'
        TemplatesDir         = Join-Path $root 'ops\paperclip\templates'
        InstructionsDir      = Join-Path $root 'ops\paperclip\instructions'
        AtlasDir             = Join-Path $root '.agent\atlas'
        AtlasSummaryPath     = Join-Path $root $system.Atlas.SummaryPath
        AtlasReadmePath      = Join-Path $root $system.Atlas.ReadmePath
        AtlasCodePath        = Join-Path $root $system.Atlas.CodeAtlasPath
        RegressionPlaybook   = Join-Path $root 'docs\A3_PROJECT\B3_OPERATIONS\DOC-C4_REGRESSION_PLAYBOOK.md'
    }
}

function Get-VorceStudiosTimestamp {
    return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Ensure-VorceStudiosDirectory {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-VorceStudiosRuntimeDirectories {
    $paths = Get-VorceStudiosPaths
    foreach ($path in @(
        $paths.PaperclipConfigDir,
        $paths.PaperclipHome,
        $paths.PluginSourcesDir,
        $paths.RuntimeRoot,
        $paths.RuntimeLogDir
    )) {
        Ensure-VorceStudiosDirectory -Path $path
    }
}

function ConvertTo-VorceStudiosHashtable {
    param(
        [AllowNull()][object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-VorceStudiosHashtable -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = foreach ($item in $InputObject) {
            ConvertTo-VorceStudiosHashtable -InputObject $item
        }
        return @($items)
    }

    if (
        ($InputObject -is [string]) -or
        ($InputObject -is [ValueType]) -or
        ($InputObject -is [datetime]) -or
        ($InputObject -is [datetimeoffset]) -or
        ($InputObject -is [decimal])
    ) {
        return $InputObject
    }

    $properties = @($InputObject.PSObject.Properties)
    if ($InputObject -is [pscustomobject] -or $properties.Count -gt 0) {
        $result = @{}
        foreach ($property in $properties) {
            $result[$property.Name] = ConvertTo-VorceStudiosHashtable -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

function Read-VorceStudiosJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Default = $null
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Default
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    try {
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        return ConvertTo-VorceStudiosHashtable -InputObject $parsed
    } catch {
        return $Default
    }
}

function Write-VorceStudiosJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        Ensure-VorceStudiosDirectory -Path $parent
    }

    $json = $Value | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-VorceStudiosRuntimeState {
    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy

    return Read-VorceStudiosJsonFile -Path $paths.RuntimeStatePath -Default @{
        mode = $system.Runtime.DefaultMode
        updatedAt = Get-VorceStudiosTimestamp
        note = 'initial'
        lastRoleRuns = @{}
    }
}

function Set-VorceStudiosRuntimeState {
    param(
        [Parameter(Mandatory)][hashtable]$State
    )

    $State['updatedAt'] = Get-VorceStudiosTimestamp
    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).RuntimeStatePath -Value $State
}

function Set-VorceStudiosRuntimeMode {
    param(
        [Parameter(Mandatory)][ValidateSet('stopped', 'running', 'draining')][string]$Mode,
        [string]$Note = ''
    )

    $state = Get-VorceStudiosRuntimeState
    $state['mode'] = $Mode
    $state['note'] = $Note
    Set-VorceStudiosRuntimeState -State $state
}

function Get-VorceStudiosCompanyState {
    return Read-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CompanyStatePath -Default @{
        company = $null
        agents = @{}
        project = $null
        atlas = @{
            available = $false
        }
        initializedAt = $null
    }
}

function Set-VorceStudiosCompanyState {
    param(
        [Parameter(Mandatory)][hashtable]$State
    )

    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CompanyStatePath -Value $State
}

function Get-VorceStudiosProcessState {
    return Read-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).ProcessStatePath -Default @{
        paperclip = $null
        supervisor = $null
    }
}

function Set-VorceStudiosProcessState {
    param(
        [Parameter(Mandatory)][hashtable]$State
    )

    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).ProcessStatePath -Value $State
}

function Import-VorceStudiosPaperclipEnvironment {
    $envPath = (Get-VorceStudiosPaths).PaperclipEnvPath
    if (-not (Test-Path -LiteralPath $envPath)) {
        $envLines = @()
    } else {
        $envLines = @(Get-Content -LiteralPath $envPath)
    }

    foreach ($line in $envLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^(?<key>[A-Za-z0-9_]+)=(?<value>.*)$') { continue }

        $key = $Matches['key']
        $value = $Matches['value'].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        [System.Environment]::SetEnvironmentVariable($key, $value)
        Set-Item -Path ("Env:{0}" -f $key) -Value $value
    }

    $env:PAPERCLIP_DISABLE_SKILL_LINKING = 'true'
    [System.Environment]::SetEnvironmentVariable('PAPERCLIP_DISABLE_SKILL_LINKING', 'true', 'Process')

    try {
        $sync = Get-VorceStudiosPolicy -Name 'sync'
        $defaults = @{
            VORCE_PROJECT_OWNER = [string]$sync.GitHub.ProjectOwner
            VORCE_PROJECT_NUMBER = [string]$sync.GitHub.ProjectNumber
            VORCE_PROJECT_STATUS_FIELD = [string]$sync.GitHub.ProjectFields.Names.Status
            VORCE_PROJECT_QUEUE_STATE_FIELD = [string]$sync.GitHub.ProjectFields.Names.QueueState
            VORCE_PROJECT_JULES_SESSION_STATUS_FIELD = [string]$sync.GitHub.ProjectFields.Names.JulesSessionStatus
            VORCE_PROJECT_PR_CHECKS_STATUS_FIELD = [string]$sync.GitHub.ProjectFields.Names.PrChecksStatus
            VORCE_PROJECT_WORK_BRANCH_FIELD = [string]$sync.GitHub.ProjectFields.Names.WorkBranch
            VORCE_PROJECT_LAST_UPDATE_FIELD = [string]$sync.GitHub.ProjectFields.Names.LastUpdate
            VORCE_PROJECT_LINKED_PR_FIELD = [string]$sync.GitHub.ProjectFields.Names.LinkedPr
        }

        foreach ($entry in $defaults.GetEnumerator()) {
            $currentValue = ''
            try {
                $envItem = Get-Item -Path ("Env:{0}" -f $entry.Key) -ErrorAction Stop
                $currentValue = [string]$envItem
            } catch {
                $currentValue = ''
            }

            if ([string]::IsNullOrWhiteSpace($currentValue)) {
                [System.Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value)
                Set-Item -Path ("Env:{0}" -f $entry.Key) -Value ([string]$entry.Value)
            }
        }
    } catch {
    }
}

function Get-VorceStudiosPaperclipCli {
    $system = Get-VorceStudiosSystemPolicy
    $pnpm = Get-Command 'pnpm.cmd' -ErrorAction SilentlyContinue
    if ($null -eq $pnpm) {
        $pnpm = Get-Command 'pnpm' -ErrorAction Stop
    }
    return @{
        FilePath = $pnpm.Source
        Arguments = @('dlx', ("paperclipai@{0}" -f $system.Company.PaperclipVersion))
    }
}

function Get-VorceStudiosShellExecutable {
    foreach ($candidate in @('pwsh.exe', 'pwsh', 'powershell.exe', 'powershell')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw 'Keine PowerShell-Executable gefunden.'
}

function Get-VorceStudiosRepositoryRemote {
    try {
        $remote = git config --get remote.origin.url 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($remote)) {
            return $remote.Trim()
        }
    } catch {
    }

    return 'https://github.com/Vorce-Studios/Vorce.git'
}

function Get-VorceStudiosRepositorySlug {
    $remote = Get-VorceStudiosRepositoryRemote
    if ($remote -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+?)(?:\.git)?$') {
        return ('{0}/{1}' -f $Matches['owner'], $Matches['repo'])
    }

    return 'Vorce-Studios/Vorce'
}

function Get-VorceStudiosAtlasState {
    $paths = Get-VorceStudiosPaths
    return @{
        available = (Test-Path -LiteralPath $paths.AtlasCodePath)
        summaryPath = $paths.AtlasSummaryPath
        readmePath = $paths.AtlasReadmePath
        codeAtlasPath = $paths.AtlasCodePath
    }
}

function Get-VorceStudiosServerPort {
    return [int](Get-VorceStudiosSystemPolicy).Company.ServerPort
}

function Get-VorceStudiosServerProcessInfo {
    try {
        $connection = Get-NetTCPConnection -LocalPort (Get-VorceStudiosServerPort) -State Listen -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $connection) {
            return $null
        }

        $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return $null
        }

        return @{
            pid = $process.Id
            name = $process.ProcessName
            startTime = $process.StartTime
        }
    } catch {
        return $null
    }
}
