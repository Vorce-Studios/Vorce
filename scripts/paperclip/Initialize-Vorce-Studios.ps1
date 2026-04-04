[CmdletBinding()]
param(
    [switch]$StartServer
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\CapacityLedger.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')
. (Join-Path $ScriptDir 'lib\GitHubOrchestrationSync.ps1')

function Ensure-VorceStudiosWorktreeConfig {
    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy
    if ((Test-Path -LiteralPath $paths.PaperclipConfigPath) -and (Test-Path -LiteralPath $paths.PaperclipEnvPath)) {
        return
    }

    $cli = Get-VorceStudiosPaperclipCli
    & $cli.FilePath @(
        $cli.Arguments +
        @(
            'worktree',
            'init',
            '--name', $system.Company.Name,
            '--instance', $system.Company.InstanceId,
            '--home', $paths.PaperclipHome,
            '--server-port', [string]$system.Company.ServerPort,
            '--db-port', [string]$system.Company.DatabasePort,
            '--no-seed',
            '--force'
        )
    )

    if ($LASTEXITCODE -ne 0) {
        throw 'Paperclip worktree init ist fehlgeschlagen.'
    }
}

function Start-VorceStudiosBootstrapServer {
    if (Test-VorceStudiosPaperclipReady) {
        return $false
    }

    $paths = Get-VorceStudiosPaths
    $shell = Get-VorceStudiosShellExecutable
    $runner = Join-Path $ScriptDir 'Run-Vorce-StudiosPaperclip.ps1'
    $stdout = Join-Path $paths.RuntimeLogDir 'paperclip-bootstrap.stdout.log'
    $stderr = Join-Path $paths.RuntimeLogDir 'paperclip-bootstrap.stderr.log'

    $process = Start-Process -FilePath $shell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner) -WorkingDirectory $paths.Root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden

    $processState = Get-VorceStudiosProcessState
    $processState['paperclip'] = @{
        pid = $process.Id
        startedAt = Get-VorceStudiosTimestamp
        source = 'bootstrap'
    }
    Set-VorceStudiosProcessState -State $processState

    if (-not (Wait-VorceStudiosPaperclipReady -TimeoutSeconds 90)) {
        throw 'Paperclip wurde fuer das Bootstrap nicht rechtzeitig bereit.'
    }

    $serverProcess = Get-VorceStudiosServerProcessInfo
    if ($serverProcess) {
        $processState = Get-VorceStudiosProcessState
        $processState['paperclip']['serverPid'] = $serverProcess.pid
        Set-VorceStudiosProcessState -State $processState
    }

    return $true
}

function Get-VorceStudiosAgentDefinitions {
    $paths = Get-VorceStudiosPaths
    $shell = Get-VorceStudiosShellExecutable
    $agentScript = Join-Path $paths.Root 'scripts\paperclip\Invoke-Vorce-StudiosAgent.ps1'
    $routing = Get-VorceStudiosPolicy -Name 'routing'

    $definitions = @(
        @{ key = 'ceo'; name = $routing.Roles.ceo; role = 'ceo'; title = 'Strategic owner, escalation and release authority'; icon = 'crown'; capabilities = 'Architecture, prioritization, escalation, release decisions'; instructionFile = 'ceo.md' },
        @{ key = 'chief_of_staff'; name = $routing.Roles.chief_of_staff; role = 'pm'; title = 'Dynamic routing, queue health and capacity failover'; icon = 'radar'; capabilities = 'Routing, quota management, task assignment'; instructionFile = 'chief-of-staff.md' },
        @{ key = 'discovery'; name = $routing.Roles.discovery; role = 'researcher'; title = 'Proactive discovery and backlog enrichment'; icon = 'search'; capabilities = 'Issue discovery, regression scanning, stale failure triage'; instructionFile = 'discovery-scout.md' },
        @{ key = 'jules'; name = $routing.Roles.jules; role = 'engineer'; title = 'Primary low-cost implementation worker via Jules'; icon = 'wand'; capabilities = 'Issue implementation, Jules session orchestration'; instructionFile = 'jules-builder.md' },
        @{ key = 'gemini_review'; name = $routing.Roles.gemini_review; role = 'qa'; title = 'Preferred reviewer and analysis worker'; icon = 'shield'; capabilities = 'Review, triage, summary generation'; instructionFile = 'gemini-reviewer.md' },
        @{ key = 'qwen_review'; name = $routing.Roles.qwen_review; role = 'qa'; title = 'Fallback reviewer and triage worker'; icon = 'shield'; capabilities = 'Fallback review, diff summaries, bug triage'; instructionFile = 'qwen-reviewer.md' },
        @{ key = 'codex_review'; name = $routing.Roles.codex_review; role = 'cto'; title = 'High-risk reviewer and architecture escalation worker'; icon = 'brain'; capabilities = 'High-risk review, architecture and difficult debugging'; instructionFile = 'codex-reviewer.md' },
        @{ key = 'ops'; name = $routing.Roles.ops; role = 'devops'; title = 'PR checks, governance and merge stewardship'; icon = 'terminal'; capabilities = 'Checks, merge gates, audit notes, status maintenance'; instructionFile = 'ops-steward.md' },
        @{ key = 'atlas'; name = $routing.Roles.atlas; role = 'researcher'; title = 'Optional atlas-backed repo context worker'; icon = 'microscope'; capabilities = 'Atlas summaries, codebase map, context distillation'; instructionFile = 'atlas-context.md' }
    )

    foreach ($definition in $definitions) {
        $definition['payload'] = @{
            name = $definition.name
            role = $definition.role
            title = $definition.title
            icon = $definition.icon
            capabilities = $definition.capabilities
            adapterType = 'process'
            adapterConfig = @{
                command = $shell
                commandArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentScript, '-Role', $definition.key)
                cwd = $paths.Root
                env = @{
                    VORCE_STUDIOS_ROLE = $definition.key
                }
            }
            runtimeConfig = @{
                instructionPath = Join-Path $paths.InstructionsDir $definition.instructionFile
                policyRoot = $paths.PoliciesDir
            }
            budgetMonthlyCents = 0
            permissions = @{
                canCreateAgents = ($definition.key -eq 'ceo')
            }
            metadata = @{
                roleKey = $definition.key
                instructionFile = $definition.instructionFile
            }
        }
    }

    return $definitions
}

Ensure-VorceStudiosRuntimeDirectories
Ensure-VorceStudiosWorktreeConfig
Import-VorceStudiosPaperclipEnvironment
Update-VorceStudiosCapacityLedgerFromProbe | Out-Null
$startedHere = Start-VorceStudiosBootstrapServer

$system = Get-VorceStudiosSystemPolicy
$company = Find-VorceStudiosCompany -Name $system.Company.Name

if ($null -eq $company) {
    try {
        $company = New-VorceStudiosCompany -Name $system.Company.Name -Description $system.Company.Description -BudgetMonthlyCents $system.Company.BudgetMonthlyCents
    } catch {
        $cli = Get-VorceStudiosPaperclipCli
        Write-Warning "Company konnte nicht automatisch erstellt werden: $($_.Exception.Message)"
        Write-Warning 'Falls dies am fehlenden ersten Board-Admin liegt, fuehre den Bootstrap-Link aus.'
        & $cli.FilePath @($cli.Arguments + @('auth', 'bootstrap-ceo', '-c', (Get-VorceStudiosPaths).PaperclipConfigPath, '-d', (Get-VorceStudiosPaths).PaperclipHome, '--base-url', (Get-VorceStudiosApiBase)))
        if ($LASTEXITCODE -ne 0) {
            throw 'Company-Bootstrap fehlgeschlagen und es konnte kein CEO-Bootstrap-Link erstellt werden.'
        }
        return
    }
}

$existingAgents = @{}
foreach ($agent in (Get-VorceStudiosAgents -CompanyId $company.id)) {
    $existingAgents[[string]$agent.name] = $agent
}

$agentState = @{}
foreach ($definition in (Get-VorceStudiosAgentDefinitions)) {
    $agent = $existingAgents[$definition.name]
    if ($null -eq $agent) {
        $agent = New-VorceStudiosAgent -CompanyId $company.id -Payload $definition.payload
    }

    $agentState[$definition.key] = @{
        id = $agent.id
        name = $agent.name
        role = $definition.role
        adapterType = $agent.adapterType
    }
}

$projectState = Ensure-VorceStudiosPrimaryProject -CompanyId $company.id -NormalizeIssues
$project = $projectState.Project

$companyState = @{
    company = @{
        id = $company.id
        name = $company.name
        issuePrefix = $company.issuePrefix
    }
    agents = $agentState
    project = if ($null -eq $project) { $null } else { @{ id = $project.id; name = $project.name } }
    atlas = Get-VorceStudiosAtlasState
    initializedAt = Get-VorceStudiosTimestamp
}

Set-VorceStudiosCompanyState -State $companyState
Ensure-VorceStudiosProjectFields
Ensure-VorceStudiosPlugins -Context @{
    Company = $companyState.company
    Agents = $companyState.agents
    Project = $companyState.project
    Repository = Get-VorceStudiosRepositorySlug
} | Out-Null
Ensure-VorceStudiosGitHubLabels -Repository (Get-VorceStudiosRepositorySlug)
Invoke-VorceStudiosGitHubPluginPeriodicSync -IgnoreFailure | Out-Null

if ($StartServer.IsPresent) {
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Initialized with StartServer switch.'
} elseif ($startedHere) {
    Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Initialized; server started for bootstrap.'
}

$companyState
