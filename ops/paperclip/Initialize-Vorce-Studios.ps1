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
        @{ key = 'ceo'; name = $routing.Roles.ceo; role = 'ceo'; title = 'Strategic owner, escalation and release authority'; icon = 'crown'; capabilities = 'Architecture, prioritization, escalation, release decisions'; instructionFile = 'ceo.md'; reportsTo = $null },
        @{ key = 'lena_assistant'; name = $routing.Roles.lena_assistant; role = 'researcher'; title = 'Personal assistant to CEO, briefing and filtering'; icon = 'message-square'; capabilities = 'Issue aggregation, briefing generation, routine filtering'; instructionFile = 'lena-assistant.md'; reportsTo = 'ceo' },
        @{ key = 'chief_of_staff'; name = $routing.Roles.chief_of_staff; role = 'pm'; title = 'Dynamic routing, queue health and capacity failover'; icon = 'radar'; capabilities = 'Routing, quota management, task assignment'; instructionFile = 'chief-of-staff.md'; reportsTo = 'ceo' },
        @{ key = 'discovery'; name = $routing.Roles.discovery; role = 'researcher'; title = 'Proactive discovery and backlog enrichment'; icon = 'search'; capabilities = 'Issue discovery, regression scanning, stale failure triage'; instructionFile = 'discovery-scout.md'; reportsTo = 'chief_of_staff' },
        @{ key = 'jules'; name = $routing.Roles.jules; role = 'engineer'; title = 'Primary low-cost implementation worker via Jules'; icon = 'wand'; capabilities = 'Issue implementation, Jules session orchestration'; instructionFile = 'jules-builder.md'; reportsTo = 'chief_of_staff' },
        @{ key = 'jules_monitor'; name = $routing.Roles.jules_monitor; role = 'qa'; title = 'Jules session monitoring and deadlock resolution'; icon = 'radar'; capabilities = 'Session monitoring, timeout detection, escalation'; instructionFile = 'jules-session-monitor.md'; reportsTo = 'chief_of_staff' },
        @{ key = 'pr_monitor'; name = $routing.Roles.pr_monitor; role = 'qa'; title = 'GitHub PR monitoring and CI check management'; icon = 'git-branch'; capabilities = 'PR status tracking, CI retry, conflict detection'; instructionFile = 'github-pr-monitor.md'; reportsTo = 'chief_of_staff' },
        @{ key = 'gemini_review'; name = $routing.Roles.gemini_review; role = 'qa'; title = 'Preferred reviewer and analysis worker'; icon = 'shield'; capabilities = 'Review, triage, summary generation'; instructionFile = 'gemini-reviewer.md'; reportsTo = 'chief_of_staff'; adapterType = 'process' },
        @{ key = 'qwen_review'; name = $routing.Roles.qwen_review; role = 'qa'; title = 'Fallback reviewer and triage worker'; icon = 'shield'; capabilities = 'Fallback review, diff summaries, bug triage'; instructionFile = 'qwen-reviewer.md'; reportsTo = 'chief_of_staff'; adapterType = 'process' },
        @{ key = 'codex_review'; name = $routing.Roles.codex_review; role = 'cto'; title = 'High-risk reviewer and architecture escalation worker'; icon = 'brain'; capabilities = 'High-risk review, architecture and difficult debugging'; instructionFile = 'codex-reviewer.md'; reportsTo = 'chief_of_staff'; adapterType = 'codex_local' },
        @{ key = 'ops'; name = $routing.Roles.ops; role = 'devops'; title = 'PR checks, governance and merge stewardship'; icon = 'terminal'; capabilities = 'Checks, merge gates, audit notes, status maintenance'; instructionFile = 'ops-steward.md'; reportsTo = 'chief_of_staff' },
        @{ key = 'atlas'; name = $routing.Roles.atlas; role = 'researcher'; title = 'Optional atlas-backed repo context worker'; icon = 'microscope'; capabilities = 'Atlas summaries, codebase map, context distillation'; instructionFile = 'atlas-context.md'; reportsTo = 'discovery' },
        @{ key = 'antigravity'; name = $routing.Roles.antigravity; role = 'engineer'; title = 'Antigravity swarm builder for parallel multi-agent missions'; icon = 'zap'; capabilities = 'Swarm orchestration, parallel execution, multi-crate work'; instructionFile = 'antigravity-builder.md'; reportsTo = 'chief_of_staff'; adapterType = 'process' }
    )

    foreach ($definition in $definitions) {
        $adapterType = if ($definition.ContainsKey('adapterType')) { $definition.adapterType } else { 'process' }
        $payload = @{
            name = $definition.name
            role = $definition.role
            title = $definition.title
            icon = $definition.icon
            capabilities = $definition.capabilities
            adapterType = $adapterType
            heartbeatEnabled = $true
            adapterConfig = if ($adapterType -eq 'process') {
                @{
                    command = $shell
                    args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentScript, '-Role', $definition.key)
                    cwd = $paths.Root
                    env = @{
                        VORCE_STUDIOS_ROLE = $definition.key
                    }
                }
            } elseif ($adapterType -eq 'codex_local') {
                @{
                    model = 'google/gemini-2.0-flash'
                }
            } else {
                @{}
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

        $definition['payload'] = $payload
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

        foreach ($property in @('runtimeConfig', 'permissions', 'metadata')) {
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
