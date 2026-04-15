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
        Sync-VorceStudiosWorktreeConfigFile | Out-Null
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

    Sync-VorceStudiosWorktreeConfigFile | Out-Null
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

function Get-VorceStudiosManagedInstructionFilePath {
    param(
        [Parameter(Mandatory)][string]$RoleKey
    )

    $paths = Get-VorceStudiosPaths
    return (Join-Path $paths.RuntimeRoot ("instruction-bundles\{0}\AGENTS.md" -f $RoleKey))
}

function Get-VorceStudiosRoleHeartbeatInterval {
    param(
        [Parameter(Mandatory)][string]$RoleKey
    )

    $routing = Get-VorceStudiosPolicy -Name 'routing'
    if (
        $routing.ContainsKey('Heartbeats') -and
        $routing.Heartbeats.ContainsKey('IntervalsSec') -and
        $routing.Heartbeats.IntervalsSec.ContainsKey($RoleKey)
    ) {
        return [int]$routing.Heartbeats.IntervalsSec[$RoleKey]
    }

    return 0
}

function Get-VorceStudiosAgentDefinitions {
    $paths = Get-VorceStudiosPaths
    $shell = Get-VorceStudiosShellExecutable
    $agentScript = Join-Path $paths.Root 'ops\paperclip\Invoke-Vorce-StudiosAgent.ps1'
    $routing = Get-VorceStudiosPolicy -Name 'routing'

    $definitions = @(
        @{
            key = 'ceo'
            name = $routing.Roles.ceo
            role = 'ceo'
            title = 'Release strategy, prioritization, routing and final escalation owner'
            icon = 'crown'
            capabilities = 'Roadmap sequencing, issue prioritization, blocker decisions, final release control'
            instructionFile = 'ceo.md'
            reportsTo = $null
            adapterType = 'codex_local'
            heartbeatEnabled = $true
            adapterConfig = @{
                cwd = $paths.Root
                model = 'gpt-5.4'
                instructionsFilePath = Get-VorceStudiosManagedInstructionFilePath -RoleKey 'ceo'
                dangerouslyBypassApprovalsAndSandbox = $true
                timeoutSec = 1800
            }
        }
        @{
            key = 'order_manager'
            name = $routing.Roles.order_manager
            role = 'pm'
            title = 'Creates Jules sessions, tracks PRs, and drives assigned work to merge readiness'
            icon = 'radar'
            capabilities = 'Jules orchestration, PR tracking, merge-readiness classification, execution follow-through'
            instructionFile = 'order-management.md'
            reportsTo = 'ceo'
            adapterType = 'gemini_local'
            heartbeatEnabled = $true
            adapterConfig = @{
                cwd = $paths.Root
                model = 'gemini-2.5-flash'
                instructionsFilePath = Get-VorceStudiosManagedInstructionFilePath -RoleKey 'order_manager'
                yolo = $true
                timeoutSec = 1800
            }
        }
        @{
            key = 'qwen_reviewer'
            name = $routing.Roles.qwen_reviewer
            role = 'qa'
            title = 'On-demand routine reviewer for concrete PRs and narrow coding follow-ups'
            icon = 'shield'
            capabilities = 'Routine PR review, regression checks, missing-test identification, narrow patching'
            instructionFile = 'qwen-reviewer.md'
            reportsTo = 'ceo'
            adapterType = 'process'
            heartbeatEnabled = $false
            adapterConfig = @{
                command = $shell
                args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentScript, '-Role', 'qwen_reviewer')
                cwd = $paths.Root
                env = @{
                    VORCE_STUDIOS_ROLE = 'qwen_reviewer'
                    VORCE_STUDIOS_POLICY_ROOT = $paths.PoliciesDir
                    VORCE_STUDIOS_INSTRUCTIONS_FILE = Get-VorceStudiosManagedInstructionFilePath -RoleKey 'qwen_reviewer'
                }
                timeoutSec = 1800
            }
        }
        @{
            key = 'codex_reviewer'
            name = $routing.Roles.codex_reviewer
            role = 'cto'
            title = 'On-demand escalation reviewer for hard debugging and high-risk diffs'
            icon = 'brain'
            capabilities = 'High-risk review, architecture analysis, difficult debugging, minimum safe implementation'
            instructionFile = 'codex-reviewer.md'
            reportsTo = 'ceo'
            adapterType = 'codex_local'
            heartbeatEnabled = $false
            adapterConfig = @{
                cwd = $paths.Root
                model = 'gpt-5.4'
                instructionsFilePath = Get-VorceStudiosManagedInstructionFilePath -RoleKey 'codex_reviewer'
                dangerouslyBypassApprovalsAndSandbox = $true
                timeoutSec = 1800
            }
        }
    )

    foreach ($definition in $definitions) {
        $definition['payload'] = @{
            name = $definition.name
            role = $definition.role
            title = $definition.title
            icon = $definition.icon
            capabilities = $definition.capabilities
            adapterType = $definition.adapterType
            heartbeatEnabled = [bool]$definition.heartbeatEnabled
            adapterConfig = $definition.adapterConfig
            runtimeConfig = @{
                instructionPath = Join-Path $paths.InstructionsDir $definition.instructionFile
                policyRoot = $paths.PoliciesDir
            }
            budgetMonthlyCents = 0
            permissions = @{
                canCreateAgents = $false
            }
            metadata = @{
                roleKey = $definition.key
                instructionFile = $definition.instructionFile
                heartbeatIntervalSec = Get-VorceStudiosRoleHeartbeatInterval -RoleKey $definition.key
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

$goalsState = Ensure-VorceStudiosGoalsFromPolicy -CompanyId ([string]$company.id)

$existingAgents = @{}
$existingAgentsByRoleKey = @{}
foreach ($agent in (Get-VorceStudiosAgents -CompanyId $company.id)) {
    $existingAgents[[string]$agent.name] = $agent
    $metadata = Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata'
    $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'roleKey')
    if (-not [string]::IsNullOrWhiteSpace($roleKey) -and -not $existingAgentsByRoleKey.ContainsKey($roleKey)) {
        $existingAgentsByRoleKey[$roleKey] = $agent
    }
}

$agentDefinitions = @(Get-VorceStudiosAgentDefinitions)
$resolvedAgentsByKey = @{}
$agentState = @{}
foreach ($definition in $agentDefinitions) {
    $agent = $null
    if ($existingAgentsByRoleKey.ContainsKey($definition.key)) {
        $agent = $existingAgentsByRoleKey[$definition.key]
    } elseif ($existingAgents.ContainsKey($definition.name)) {
        $agent = $existingAgents[$definition.name]
    }

    if ($null -eq $agent) {
        $agent = New-VorceStudiosAgent -CompanyId $company.id -Payload $definition.payload
    } else {
        $updatePayload = @{}
        foreach ($property in @('name', 'role', 'title', 'icon', 'capabilities', 'adapterType', 'heartbeatEnabled')) {
            if ([string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName $property) -ne [string]$definition.payload[$property]) {
                $updatePayload[$property] = $definition.payload[$property]
            }
        }

        foreach ($property in @('adapterConfig', 'runtimeConfig', 'permissions', 'metadata')) {
            $currentValue = Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName $property
            $desiredValue = $definition.payload[$property]
            if (-not (Test-VorceStudiosJsonEquivalent -Left $currentValue -Right $desiredValue)) {
                $updatePayload[$property] = $desiredValue
            }
        }

        if ($updatePayload.Count -gt 0) {
            $agent = Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload $updatePayload
        }
    }

    $resolvedAgentsByKey[$definition.key] = $agent
    $agentState[$definition.key] = @{
        id = $agent.id
        name = $agent.name
        role = $definition.role
        adapterType = $agent.adapterType
        heartbeatEnabled = [bool]$definition.payload.heartbeatEnabled
    }
}

foreach ($definition in $agentDefinitions) {
    $agent = $resolvedAgentsByKey[$definition.key]
    if ($null -eq $agent) {
        continue
    }

    $desiredReportsTo = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$definition.reportsTo) -and $resolvedAgentsByKey.ContainsKey([string]$definition.reportsTo)) {
        $desiredReportsTo = [string]$resolvedAgentsByKey[[string]$definition.reportsTo].id
    }

    $currentReportsTo = [string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'reportsTo')
    $reportsToMatches = (
        ([string]::IsNullOrWhiteSpace($currentReportsTo) -and [string]::IsNullOrWhiteSpace([string]$desiredReportsTo)) -or
        ($currentReportsTo -eq [string]$desiredReportsTo)
    )

    if (-not $reportsToMatches) {
        $agent = Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
            reportsTo = $desiredReportsTo
        }
        $resolvedAgentsByKey[$definition.key] = $agent
        $agentState[$definition.key] = @{
            id = $agent.id
            name = $agent.name
            role = $definition.role
            adapterType = $agent.adapterType
            heartbeatEnabled = [bool]$definition.payload.heartbeatEnabled
        }
    }
}

$instructionSync = Sync-VorceStudiosManagedAgentInstructions -CompanyId ([string]$company.id)

$projectState = Ensure-VorceStudiosPrimaryProject -CompanyId $company.id -NormalizeIssues
$project = $projectState.Project

$companyState = @{
    company = @{
        id = $company.id
        name = $company.name
        issuePrefix = $company.issuePrefix
    }
    goals = $goalsState.goals
    agents = $agentState
    project = if ($null -eq $project) { $null } else { @{ id = $project.id; name = $project.name } }
    atlas = Get-VorceStudiosAtlasState
    instructionBundles = $instructionSync
    initializedAt = Get-VorceStudiosTimestamp
}

Set-VorceStudiosCompanyState -State $companyState
Ensure-VorceStudiosProjectFields
Ensure-VorceStudiosPlugins -Context @{
    Company = $companyState.company
    Agents = $companyState.agents
    Goals = $companyState.goals
    Project = $companyState.project
    Repository = Get-VorceStudiosRepositorySlug
} | Out-Null
Ensure-VorceStudiosGitHubLabels -Repository (Get-VorceStudiosRepositorySlug)
if ($null -ne $companyState.project) {
    $githubSync = Sync-VorceStudiosGitHubIssuesToPaperclip -Context @{
        Company = $companyState.company
        Agents = $companyState.agents
        Goals = $companyState.goals
        Project = $companyState.project
        Repository = Get-VorceStudiosRepositorySlug
    } -State 'all'
    $planningItems = @(Invoke-VorceStudiosPlanningSweep -Repository (Get-VorceStudiosRepositorySlug))
    $companyState['githubSync'] = $githubSync
    $companyState['planning'] = @{
        updatedAt = (Get-VorceStudiosPlanningSnapshot).updatedAt
        top = @($planningItems | Select-Object -First 15)
    }
    Set-VorceStudiosCompanyState -State $companyState
}
Invoke-VorceStudiosGitHubPluginPeriodicSync -IgnoreFailure | Out-Null

if ($StartServer.IsPresent) {
    Set-VorceStudiosRuntimeMode -Mode 'running' -Note 'Initialized with StartServer switch.'
} elseif ($startedHere) {
    Set-VorceStudiosRuntimeMode -Mode 'stopped' -Note 'Initialized; server started for bootstrap.'
}

$companyState
