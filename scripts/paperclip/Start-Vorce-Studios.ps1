[CmdletBinding()]
param(
    [switch]$OpenUi
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

if (-not (Test-Path -LiteralPath (Get-VorceStudiosPaths).PaperclipConfigPath)) {
    & (Join-Path $ScriptDir 'Initialize-Vorce-Studios.ps1') -StartServer
}

$processState = Get-VorceStudiosProcessState
$paths = Get-VorceStudiosPaths
$shell = Get-VorceStudiosShellExecutable

if (-not (Test-VorceStudiosPaperclipReady)) {
    $runner = Join-Path $ScriptDir 'Run-Vorce-StudiosPaperclip.ps1'
    $stdout = Join-Path $paths.RuntimeLogDir 'paperclip.stdout.log'
    $stderr = Join-Path $paths.RuntimeLogDir 'paperclip.stderr.log'
    $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner) -WorkingDirectory $paths.Root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden

    $processState['paperclip'] = @{
        pid = $process.Id
        startedAt = Get-VorceStudiosTimestamp
        source = 'start-script'
    }
    Set-VorceStudiosProcessState -State $processState
}

if (-not (Wait-VorceStudiosPaperclipReady -TimeoutSeconds 90)) {
    throw 'Paperclip wurde nicht rechtzeitig bereit.'
}

$serverProcess = Get-VorceStudiosServerProcessInfo
$processState = Get-VorceStudiosProcessState
if ($serverProcess) {
    if ($null -eq $processState['paperclip']) {
        $processState['paperclip'] = @{}
    }
    $processState['paperclip']['serverPid'] = $serverProcess.pid
    if (-not $processState['paperclip'].ContainsKey('pid')) {
        $processState['paperclip']['pid'] = $serverProcess.pid
    }
    if (-not $processState['paperclip'].ContainsKey('startedAt')) {
        $processState['paperclip']['startedAt'] = Get-VorceStudiosTimestamp
    }
    if (-not $processState['paperclip'].ContainsKey('source')) {
        $processState['paperclip']['source'] = 'port-detected'
    }
    Set-VorceStudiosProcessState -State $processState
}

$companyState = Get-VorceStudiosCompanyState
if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    & (Join-Path $ScriptDir 'Initialize-Vorce-Studios.ps1') -StartServer
    $companyState = Get-VorceStudiosCompanyState
}

if ($null -ne $companyState.company -and -not [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    $projectState = Ensure-VorceStudiosPrimaryProject -CompanyId ([string]$companyState.company.id) -NormalizeIssues
    if ($null -ne $projectState.Project) {
        $companyState['project'] = @{
            id = [string]$projectState.Project.id
            name = [string]$projectState.Project.name
        }
        Set-VorceStudiosCompanyState -State $companyState
    }

    $context = @{
        Company = $companyState.company
        Agents = $companyState.agents
        Project = $companyState.project
        Repository = Get-VorceStudiosRepositorySlug
    }

    Ensure-VorceStudiosProjectFields
    Ensure-VorceStudiosPlugins -Context $context | Out-Null
    Ensure-VorceStudiosGitHubLabels -Repository $context.Repository
    Invoke-VorceStudiosPlanningSweep -Repository $context.Repository | Out-Null
    Invoke-VorceStudiosGitHubPluginPeriodicSync -IgnoreFailure | Out-Null
}

$processState = Get-VorceStudiosProcessState
$supervisorProcess = $null
if ($processState.supervisor -and $processState.supervisor.pid) {
    $supervisorProcess = Get-Process -Id ([int]$processState.supervisor.pid) -ErrorAction SilentlyContinue
}

if ($null -eq $supervisorProcess) {
    $stdout = Join-Path $paths.RuntimeLogDir 'supervisor.stdout.log'
    $stderr = Join-Path $paths.RuntimeLogDir 'supervisor.stderr.log'
    $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ScriptDir 'Invoke-Vorce-StudiosSupervisor.ps1')) -WorkingDirectory $paths.Root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
    $processState['supervisor'] = @{
        pid = $process.Id
        startedAt = Get-VorceStudiosTimestamp
    }
    Set-VorceStudiosProcessState -State $processState
}

Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Started via Start-Vorce-Studios.ps1'

if ($OpenUi.IsPresent) {
    Start-Process (Get-VorceStudiosApiBase) | Out-Null
}

[pscustomobject]@{
    apiBase = Get-VorceStudiosApiBase
    companyId = $companyState.company.id
    mode = 'running'
}
