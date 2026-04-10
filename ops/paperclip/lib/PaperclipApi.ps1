Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')

function Get-VorceStudiosApiBase {
    $system = Get-VorceStudiosSystemPolicy
    return ('http://127.0.0.1:{0}' -f $system.Company.ServerPort)
}

function Get-VorceStudiosApiHeaders {
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($env:PAPERCLIP_API_KEY)) {
        $headers['Authorization'] = 'Bearer {0}' -f $env:PAPERCLIP_API_KEY
    }
    return $headers
}

function Invoke-VorceStudiosApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Body,
        [switch]$IgnoreNotFound,
        [switch]$IgnoreFailure
    )

    $uri = '{0}{1}' -f (Get-VorceStudiosApiBase).TrimEnd('/'), $Path
    $params = @{
        Method = $Method
        Uri = $uri
        Headers = Get-VorceStudiosApiHeaders
        ErrorAction = 'Stop'
        TimeoutSec = 8
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params['ContentType'] = 'application/json'
        $params['Body'] = if ($null -eq $Body) { '{}' } else { $Body | ConvertTo-Json -Depth 30 }
    }

    try {
        $result = Invoke-RestMethod @params
        return $result
    } catch {
        $message = $_.Exception.Message
        if ($IgnoreNotFound.IsPresent -and $message -match '404') {
            return $null
        }
        if ($IgnoreFailure.IsPresent) {
            return $null
        }
        throw
    }
}

function Test-VorceStudiosPaperclipReady {
    try {
        $health = Invoke-VorceStudiosApi -Method GET -Path '/api/health'
        return ($null -ne $health)
    } catch {
        return $false
    }
}

function Test-VorceStudiosBoardAccess {
    $probe = Invoke-VorceStudiosApi -Method GET -Path '/api/plugins' -IgnoreFailure
    return ($null -ne $probe)
}

function Wait-VorceStudiosPaperclipReady {
    param(
        [int]$TimeoutSeconds = 60
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-VorceStudiosPaperclipReady) {
            return $true
        }
        Start-Sleep -Seconds 2
    }

    return $false
}

function Get-VorceStudiosCompanies {
    $companies = Invoke-VorceStudiosApi -Method GET -Path '/api/companies' -IgnoreFailure
    if ($null -eq $companies) {
        return @()
    }
    return @($companies)
}

function Find-VorceStudiosCompany {
    param(
        [string]$Name = 'Vorce-Studios'
    )

    $matches = @(
        Get-VorceStudiosCompanies |
            Where-Object { $_.name -eq $Name } |
            Select-Object -First 1
    )
    if ($matches.Count -eq 0) {
        return $null
    }
    return $matches[0]
}

function New-VorceStudiosCompany {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description,
        [int]$BudgetMonthlyCents = 0
    )

    $payload = @{
        name = $Name
        description = $Description
        budgetMonthlyCents = $BudgetMonthlyCents
    }

    return Invoke-VorceStudiosApi -Method POST -Path '/api/companies' -Body $payload
}

function Get-VorceStudiosProjects {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $projects = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/projects" -f $CompanyId) -IgnoreFailure
    if ($null -eq $projects) {
        return @()
    }

    return @($projects)
}

function Find-VorceStudiosProject {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$Name,
        [switch]$AllowPrefixMatch
    )

    $projects = @(Get-VorceStudiosProjects -CompanyId $CompanyId)
    $matches = @(
        $projects |
            Where-Object { [string]$_.name -eq $Name } |
            Sort-Object createdAt |
            Select-Object -First 1
    )
    if ($matches.Count -gt 0) {
        return $matches[0]
    }

    if ($AllowPrefixMatch.IsPresent) {
        $matches = @(
            $projects |
                Where-Object { [string]$_.name -like ('{0}*' -f $Name) } |
                Sort-Object createdAt |
                Select-Object -First 1
        )
        if ($matches.Count -gt 0) {
            return $matches[0]
        }
    }

    return $null
}

function Get-VorceStudiosGoals {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $goals = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/goals" -f $CompanyId) -IgnoreFailure
    if ($null -eq $goals) {
        return @()
    }

    return @($goals)
}

function Find-VorceStudiosGoalByTitle {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$Title
    )

    $matches = @(
        Get-VorceStudiosGoals -CompanyId $CompanyId |
            Where-Object { [string]$_.title -eq $Title } |
            Select-Object -First 1
    )
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function New-VorceStudiosGoal {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/goals" -f $CompanyId) -Body $Payload
}

function Update-VorceStudiosGoal {
    param(
        [Parameter(Mandatory)][string]$GoalId,
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method PATCH -Path ("/api/goals/{0}" -f $GoalId) -Body (@{
        companyId = $CompanyId
    } + $Payload)
}

function Ensure-VorceStudiosGoalsFromPolicy {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $policy = Get-VorceStudiosPolicy -Name 'goals'
    $existingByTitle = @{}
    foreach ($goal in (Get-VorceStudiosGoals -CompanyId $CompanyId)) {
        $existingByTitle[[string]$goal.title] = $goal
    }

    $created = New-Object System.Collections.Generic.List[string]
    $updated = New-Object System.Collections.Generic.List[string]
    $goalMap = @{}

    foreach ($goalDefinition in @($policy.Goals)) {
        $title = [string]$goalDefinition.Title
        $description = [string]$goalDefinition.Description
        $status = 'active'
        $level = 'company'
        $payload = @{
            title = $title
            description = $description
            level = $level
            status = $status
        }

        if ($existingByTitle.ContainsKey($title)) {
            $existing = $existingByTitle[$title]
            $patch = @{}
            foreach ($property in @('title', 'description', 'level', 'status')) {
                if ([string](Get-VorceStudiosObjectPropertyValue -Object $existing -PropertyName $property) -ne [string]$payload[$property]) {
                    $patch[$property] = $payload[$property]
                }
            }

            $goal = if ($patch.Count -gt 0) {
                $updated.Add($title) | Out-Null
                Update-VorceStudiosGoal -GoalId ([string]$existing.id) -CompanyId $CompanyId -Payload $patch
            } else {
                $existing
            }
            $goalMap[[string]$goalDefinition.Id] = $goal
            continue
        }

        $goal = New-VorceStudiosGoal -CompanyId $CompanyId -Payload $payload
        $created.Add($title) | Out-Null
        $goalMap[[string]$goalDefinition.Id] = $goal
    }

    return @{
        created = $created.ToArray()
        updated = $updated.ToArray()
        goals = $goalMap
    }
}

function Get-VorceStudiosAgents {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $agents = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/agents" -f $CompanyId) -IgnoreFailure
    if ($null -eq $agents) {
        return @()
    }
    return @($agents)
}

function New-VorceStudiosAgent {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/agents" -f $CompanyId) -Body $Payload
}

function Update-VorceStudiosAgent {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method PATCH -Path ("/api/agents/{0}" -f $AgentId) -Body $Payload
}

function Invoke-VorceStudiosHeartbeat {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [string]$Reason = 'manual'
    )

    $payload = @{
        source = 'on_demand'
        triggerDetail = 'manual'
        reason = $Reason
    }

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/agents/{0}/wakeup" -f $AgentId) -Body $payload
}

function Get-VorceStudiosIssues {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $issues = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/issues" -f $CompanyId) -IgnoreFailure
    if ($null -eq $issues) {
        return @()
    }
    return @($issues)
}

function New-VorceStudiosIssue {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/issues" -f $CompanyId) -Body $Payload
}

function Update-VorceStudiosIssue {
    param(
        [Parameter(Mandatory)][string]$IssueId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method PATCH -Path ("/api/issues/{0}" -f $IssueId) -Body $Payload
}

function Set-VorceStudiosIssueProject {
    param(
        [Parameter(Mandatory)][string]$IssueId,
        [Parameter(Mandatory)][string]$ProjectId
    )

    return Update-VorceStudiosIssue -IssueId $IssueId -Payload @{
        projectId = $ProjectId
    }
}

function Add-VorceStudiosIssueComment {
    param(
        [Parameter(Mandatory)][string]$IssueId,
        [Parameter(Mandatory)][string]$Body
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/issues/{0}/comments" -f $IssueId) -Body @{
        body = $Body
    }
}

function Get-VorceStudiosDashboard {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    return Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/dashboard" -f $CompanyId) -IgnoreFailure
}

function Try-New-VorceStudiosProject {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    foreach ($path in @(
        "/api/companies/{0}/projects" -f $CompanyId,
        '/api/projects'
    )) {
        try {
            $body = if ($path -eq '/api/projects') {
                $copy = @{}
                foreach ($key in $Payload.Keys) { $copy[$key] = $Payload[$key] }
                $copy['companyId'] = $CompanyId
                $copy
            } else {
                $Payload
            }
            $created = Invoke-VorceStudiosApi -Method POST -Path $path -Body $body -IgnoreFailure
            if ($null -ne $created) {
                return $created
            }
        } catch {
        }
    }

    return $null
}

function Ensure-VorceStudiosPrimaryProject {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [switch]$NormalizeIssues
    )

    $system = Get-VorceStudiosSystemPolicy
    $projectName = if ($system.ContainsKey('Project') -and $system.Project.ContainsKey('Name')) { [string]$system.Project.Name } else { 'Vorce Release Train' }
    $projectDescription = if ($system.ContainsKey('Project') -and $system.Project.ContainsKey('Description')) { [string]$system.Project.Description } else { 'Primary local control-plane project for release planning and execution.' }

    $projects = @(Get-VorceStudiosProjects -CompanyId $CompanyId)
    $primary = Find-VorceStudiosProject -CompanyId $CompanyId -Name $projectName -AllowPrefixMatch
    if ($null -eq $primary) {
        $primary = Try-New-VorceStudiosProject -CompanyId $CompanyId -Payload @{
            name = $projectName
            description = $projectDescription
            status = 'planned'
        }
        $projects = @(Get-VorceStudiosProjects -CompanyId $CompanyId)
    }

    $migratedIssues = New-Object System.Collections.Generic.List[string]
    $duplicateProjects = @(
        $projects |
            Where-Object {
                [string]$_.id -ne [string]$primary.id -and
                [string]$_.name -like ('{0}*' -f $projectName)
            }
    )

    if ($NormalizeIssues.IsPresent -and $duplicateProjects.Count -gt 0) {
        $duplicateProjectIds = @($duplicateProjects | ForEach-Object { [string]$_.id })
        foreach ($issue in @(Get-VorceStudiosIssues -CompanyId $CompanyId)) {
            if ($duplicateProjectIds -notcontains [string]$issue.projectId) {
                continue
            }

            Set-VorceStudiosIssueProject -IssueId ([string]$issue.id) -ProjectId ([string]$primary.id) | Out-Null
            $migratedIssues.Add([string]$issue.identifier)
        }
    }

    return @{
        Project = $primary
        Duplicates = @($duplicateProjects)
        MigratedIssueCount = $migratedIssues.Count
        MigratedIssues = $migratedIssues.ToArray()
    }
}

function Get-VorceStudiosIssue {
    param(
        [Parameter(Mandatory)][string]$IssueId
    )

    return Invoke-VorceStudiosApi -Method GET -Path ("/api/issues/{0}" -f $IssueId) -IgnoreNotFound
}

function Get-VorceStudiosPlugins {
    $plugins = Invoke-VorceStudiosApi -Method GET -Path '/api/plugins' -IgnoreFailure
    if ($null -eq $plugins) {
        return @()
    }

    return @($plugins)
}

function Find-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    $matches = @(
        Get-VorceStudiosPlugins |
            Where-Object { ([string]$_.id -eq $PluginId) -or ([string]$_.pluginKey -eq $PluginId) -or ([string]$_.packageName -eq $PluginId) } |
            Select-Object -First 1
    )

    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Install-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [string]$Version,
        [switch]$IsLocalPath
    )

    $payload = @{
        packageName = $PackageName
    }
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $payload['version'] = $Version
    }
    if ($IsLocalPath.IsPresent) {
        $payload['isLocalPath'] = $true
    }

    return Invoke-VorceStudiosApi -Method POST -Path '/api/plugins/install' -Body $payload
}

function Enable-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/plugins/{0}/enable" -f $PluginId) -Body @{}
}

function Disable-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/plugins/{0}/disable" -f $PluginId) -Body @{}
}

function Uninstall-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [switch]$Purge
    )

    $path = if ($Purge.IsPresent) {
        "/api/plugins/{0}?purge=true" -f $PluginId
    } else {
        "/api/plugins/{0}" -f $PluginId
    }

    return Invoke-VorceStudiosApi -Method DELETE -Path $path -Body $null
}

function Get-VorceStudiosPluginConfig {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    return Invoke-VorceStudiosApi -Method GET -Path ("/api/plugins/{0}/config" -f $PluginId) -IgnoreNotFound
}

function Set-VorceStudiosPluginConfig {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][hashtable]$Config
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/plugins/{0}/config" -f $PluginId) -Body @{
        configJson = $Config
    }
}

function Get-VorceStudiosPluginJobs {
    param(
        [Parameter(Mandatory)][string]$PluginId
    )

    $items = Invoke-VorceStudiosApi -Method GET -Path ("/api/plugins/{0}/jobs" -f $PluginId) -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Invoke-VorceStudiosPluginJob {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][string]$JobId
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/plugins/{0}/jobs/{1}/trigger" -f $PluginId, $JobId) -Body @{}
}

function Get-VorceStudiosCompanySecrets {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $items = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/secrets" -f $CompanyId) -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function New-VorceStudiosCompanySecret {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [string]$Description = ''
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/secrets" -f $CompanyId) -Body @{
        name = $Name
        value = $Value
        description = $Description
    }
}

function Rotate-VorceStudiosSecret {
    param(
        [Parameter(Mandatory)][string]$SecretId,
        [Parameter(Mandatory)][string]$Value
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/secrets/{0}/rotate" -f $SecretId) -Body @{
        value = $Value
    }
}

function Get-VorceStudiosApprovals {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [ValidateSet('pending', 'approved', 'rejected', 'revision_requested', 'all')][string]$Status = 'all'
    )

    $path = if ($Status -eq 'all') {
        "/api/companies/{0}/approvals" -f $CompanyId
    } else {
        "/api/companies/{0}/approvals?status={1}" -f $CompanyId, $Status
    }

    $items = Invoke-VorceStudiosApi -Method GET -Path $path -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Get-VorceStudiosApproval {
    param(
        [Parameter(Mandatory)][string]$ApprovalId
    )

    return Invoke-VorceStudiosApi -Method GET -Path ("/api/approvals/{0}" -f $ApprovalId) -IgnoreNotFound
}

function New-VorceStudiosApproval {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/approvals" -f $CompanyId) -Body $Payload
}

function Get-VorceStudiosApprovalIssues {
    param(
        [Parameter(Mandatory)][string]$ApprovalId
    )

    $items = Invoke-VorceStudiosApi -Method GET -Path ("/api/approvals/{0}/issues" -f $ApprovalId) -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Invoke-VorceStudiosPluginTool {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][hashtable]$RunContext,
        [AllowNull()][hashtable]$Parameters = @{}
    )

    return Invoke-VorceStudiosApi -Method POST -Path '/api/plugins/tools/execute' -Body @{
        tool = $Tool
        parameters = $Parameters
        runContext = $RunContext
    }
}

function Test-VorceStudiosJsonEquivalent {
    param(
        [AllowNull()][object]$Left,
        [AllowNull()][object]$Right
    )

    $leftJson = if ($null -eq $Left) { '' } else { $Left | ConvertTo-Json -Depth 30 -Compress }
    $rightJson = if ($null -eq $Right) { '' } else { $Right | ConvertTo-Json -Depth 30 -Compress }
    return ($leftJson -eq $rightJson)
}

function Get-VorceStudiosObjectPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($PropertyName)) {
            return $Object[$PropertyName]
        }
    }

    $property = $Object.PSObject.Properties[$PropertyName]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Resolve-VorceStudiosAgentInstructionSourcePath {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $paths = Get-VorceStudiosPaths
    $runtimeConfig = Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'runtimeConfig'
    $runtimeInstructionPath = [string](Get-VorceStudiosObjectPropertyValue -Object $runtimeConfig -PropertyName 'instructionPath')
    if (-not [string]::IsNullOrWhiteSpace($runtimeInstructionPath) -and (Test-Path -LiteralPath $runtimeInstructionPath)) {
        return $runtimeInstructionPath
    }

    $metadata = Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'metadata'
    $instructionFile = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'instructionFile')
    if (-not [string]::IsNullOrWhiteSpace($instructionFile)) {
        $candidate = Join-Path $paths.InstructionsDir $instructionFile
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-VorceStudiosAgentInstructionBundlePath {
    param(
        [Parameter(Mandatory)][object]$Agent,
        [Parameter(Mandatory)][string]$CompanyId
    )

    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy
    $adapterConfig = Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'adapterConfig'
    $managedPath = [string](Get-VorceStudiosObjectPropertyValue -Object $adapterConfig -PropertyName 'instructionsFilePath')
    if (-not [string]::IsNullOrWhiteSpace($managedPath)) {
        return $managedPath
    }

    $agentId = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'id')
    if ([string]::IsNullOrWhiteSpace($agentId)) {
        return $null
    }

    return Join-Path $paths.PaperclipHome ("instances\{0}\companies\{1}\agents\{2}\instructions\AGENTS.md" -f $system.Company.InstanceId, $CompanyId, $agentId)
}

function Get-VorceStudiosRoleKeyForAgent {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $metadata = Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'metadata'
    return [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'roleKey')
}

function Get-VorceStudiosManagedInstructionBundleFiles {
    param(
        [Parameter(Mandatory)][object]$Agent,
        [Parameter(Mandatory)][string]$SourceInstructionPath
    )

    $system = Get-VorceStudiosSystemPolicy
    $routing = Get-VorceStudiosPolicy -Name 'routing'
    $goals = Get-VorceStudiosPolicy -Name 'goals'
    $skills = Get-VorceStudiosPolicy -Name 'skills'
    $agentName = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'name')
    $agentTitle = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'title')
    $agentCapabilities = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'capabilities')
    $adapterType = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'adapterType')
    $heartbeatEnabled = [bool](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'heartbeatEnabled')
    $roleKey = Get-VorceStudiosRoleKeyForAgent -Agent $Agent
    $instructionBody = (Get-Content -LiteralPath $SourceInstructionPath -Raw).Trim()
    $instructionBaseDir = Split-Path -Parent $SourceInstructionPath

    $safeName = $agentName -replace '"', '\"'
    $safeTitle = $agentTitle -replace '"', '\"'

    $heartbeatInterval = ''
    if (
        $routing.ContainsKey('Heartbeats') -and
        $routing.Heartbeats.ContainsKey('IntervalsSec') -and
        $routing.Heartbeats.IntervalsSec.ContainsKey($roleKey)
    ) {
        $heartbeatInterval = [string]$routing.Heartbeats.IntervalsSec[$roleKey]
    }

    $roleFocus = switch ($roleKey) {
        'ceo' {
            @(
                '- Sequence the release roadmap before assigning execution.'
                '- Keep GitHub sync, CI, PR mergeability, and release blockers ahead of feature work.'
                '- Wake reviewers only for concrete diffs or hard blockers.'
            )
        }
        'order_manager' {
            @(
                '- Convert CEO decisions into Jules sessions and PR follow-through.'
                '- Prevent duplicate sessions and keep issue-to-session-to-PR state current.'
                '- Escalate only with exact failing session, PR, or check evidence.'
            )
        }
        'qwen_reviewer' {
            @(
                '- Operate on demand only.'
                '- Review a specific PR or narrow change request and return findings first.'
                '- Do not start speculative work.'
            )
        }
        'codex_reviewer' {
            @(
                '- Operate on demand only.'
                '- Focus on high-risk review, architecture, or ugly debugging.'
                '- If the task is routine, hand it back instead of over-working it.'
            )
        }
        default {
            @('- Follow the assigned role carefully and stop when the current action is complete.')
        }
    }

    $assignedSkills = @(
        $skills.Skills |
            Where-Object { @($_.AssignedTo) -contains $roleKey }
    )

    $goalsLines = New-Object System.Collections.Generic.List[string]
    $goalsLines.Add('# GOALS') | Out-Null
    $goalsLines.Add('') | Out-Null
    $goalsLines.Add(('Mission: {0}' -f [string]$goals.Mission)) | Out-Null
    $goalsLines.Add('') | Out-Null
    $goalsLines.Add('## Release Sequence') | Out-Null
    $goalsLines.Add('') | Out-Null
    foreach ($sequence in @($goals.ReleaseSequence)) {
        $goalsLines.Add(('### {0} {1}' -f [string]$sequence.Id, [string]$sequence.Title)) | Out-Null
        $goalsLines.Add([string]$sequence.Description) | Out-Null
        $goalsLines.Add(('Goal gates: {0}' -f ((@($sequence.GateGoalIds) | ForEach-Object { [string]$_ }) -join ', '))) | Out-Null
        $goalsLines.Add('') | Out-Null
    }
    $goalsLines.Add('## Active Company Goals') | Out-Null
    $goalsLines.Add('') | Out-Null
    foreach ($goal in @($goals.Goals)) {
        $goalsLines.Add(('### {0} {1} [{2}]' -f [string]$goal.Id, [string]$goal.Title, [string]$goal.Priority)) | Out-Null
        $goalsLines.Add([string]$goal.Description) | Out-Null
        $goalsLines.Add(('Labels: {0}' -f ((@($goal.Labels) | ForEach-Object { [string]$_ }) -join ', '))) | Out-Null
        $goalsLines.Add('') | Out-Null
    }

    $skillsLines = New-Object System.Collections.Generic.List[string]
    $skillsLines.Add('# SKILLS') | Out-Null
    $skillsLines.Add('') | Out-Null
    $skillsLines.Add(('Role key: `{0}`' -f $roleKey)) | Out-Null
    $skillsLines.Add('') | Out-Null
    if ($assignedSkills.Count -eq 0) {
        $skillsLines.Add('No role-specific skills are assigned.') | Out-Null
    } else {
        foreach ($skill in $assignedSkills) {
            $skillsLines.Add(('## {0}' -f [string]$skill.Name)) | Out-Null
            $skillsLines.Add([string]$skill.Description) | Out-Null
            $skillsLines.Add('') | Out-Null
        }
    }

    $heartbeatLines = New-Object System.Collections.Generic.List[string]
    $heartbeatLines.Add('# HEARTBEAT') | Out-Null
    $heartbeatLines.Add('') | Out-Null
    $heartbeatLines.Add(('Heartbeat enabled: {0}' -f ($(if ($heartbeatEnabled) { 'yes' } else { 'no' })))) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($heartbeatInterval)) {
        $heartbeatLines.Add(('Nominal interval: {0}s' -f $heartbeatInterval)) | Out-Null
    } else {
        $heartbeatLines.Add('Nominal interval: on-demand only') | Out-Null
    }
    $heartbeatLines.Add('') | Out-Null
    if ($heartbeatEnabled) {
        $heartbeatLines.Add('Rules:') | Out-Null
        $heartbeatLines.Add('- Perform one concrete management action per heartbeat and then stop.') | Out-Null
        $heartbeatLines.Add('- If nothing actionable changed, emit a short no-op and exit.') | Out-Null
    } else {
        $heartbeatLines.Add('Rules:') | Out-Null
        $heartbeatLines.Add('- This role is on-demand only.') | Out-Null
        $heartbeatLines.Add('- If invoked without a concrete assignment, no-op immediately.') | Out-Null
        $heartbeatLines.Add('- Do not invent work or self-queue tasks.') | Out-Null
    }

    $toolsLines = New-Object System.Collections.Generic.List[string]
    $toolsLines.Add('# TOOLS') | Out-Null
    $toolsLines.Add('') | Out-Null
    $toolsLines.Add(('Primary adapter: `{0}`' -f $adapterType)) | Out-Null
    $toolsLines.Add('Useful local tooling:') | Out-Null
    $toolsLines.Add('- `pnpm dlx paperclipai@2026.403.0 dashboard get -c .paperclip/config.json -d .paperclip-home -C <companyId>`') | Out-Null
    $toolsLines.Add('- `gh issue list --repo Vorce-Studios/Vorce`') | Out-Null
    $toolsLines.Add('- `gh pr list --repo Vorce-Studios/Vorce --state open`') | Out-Null
    $toolsLines.Add('- `gh pr checks <number> --repo Vorce-Studios/Vorce`') | Out-Null
    $toolsLines.Add('- `pwsh -File scripts/jules/create-jules-session.ps1 -IssueNumber <n> -Repository Vorce-Studios/Vorce -AutoCreatePr`') | Out-Null
    $toolsLines.Add('- `pwsh -File scripts/jules/monitor-jules-sessions.ps1 -Repository Vorce-Studios/Vorce -OnlyActive -IncludeActivities`') | Out-Null
    $toolsLines.Add('- `GET http://127.0.0.1:{0}/api/health`' -f [int]$system.Company.ServerPort) | Out-Null

    $soulLines = New-Object System.Collections.Generic.List[string]
    $soulLines.Add('# SOUL') | Out-Null
    $soulLines.Add('') | Out-Null
    $soulLines.Add(('Company: {0}' -f [string]$system.Company.Name)) | Out-Null
    $soulLines.Add(('Mission: {0}' -f [string]$goals.Mission)) | Out-Null
    $soulLines.Add(('Role key: `{0}`' -f $roleKey)) | Out-Null
    $soulLines.Add(('Capabilities: {0}' -f $agentCapabilities)) | Out-Null
    $soulLines.Add('') | Out-Null
    $soulLines.Add('Role focus:') | Out-Null
    foreach ($line in $roleFocus) {
        $soulLines.Add($line) | Out-Null
    }

    $agentsLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @(
        '---',
        ('name: "{0}"' -f $safeName),
        ('title: "{0}"' -f $safeTitle),
        ('roleKey: "{0}"' -f ($roleKey -replace '"', '\"')),
        '---',
        '',
        'Read these files in order before acting:',
        '1. `SOUL.md`',
        '2. `GOALS.md`',
        '3. `HEARTBEAT.md`',
        '4. `SKILLS.md`',
        '5. `TOOLS.md`',
        '',
        ('_Instructions source: {0}_' -f $SourceInstructionPath),
        ('_Resolve any relative file references from {0}._' -f $instructionBaseDir),
        '',
        $instructionBody,
        ''
    )) {
        $agentsLines.Add([string]$line) | Out-Null
    }

    return [ordered]@{
        'AGENTS.md'    = ($agentsLines -join "`n")
        'SOUL.md'      = ($soulLines -join "`n")
        'GOALS.md'     = ($goalsLines -join "`n")
        'SKILLS.md'    = ($skillsLines -join "`n")
        'HEARTBEAT.md' = ($heartbeatLines -join "`n")
        'TOOLS.md'     = ($toolsLines -join "`n")
    }
}

function Sync-VorceStudiosManagedAgentInstructions {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    try {
        $agents = @(Get-VorceStudiosAgents -CompanyId $CompanyId)
    } catch {
        return @{
            total = 0
            updated = 0
            skipped = 0
            failed = $true
            error = $_.Exception.Message
        }
    }

    $updated = 0
    $skipped = 0

    foreach ($agent in $agents) {
        $sourceInstructionPath = Resolve-VorceStudiosAgentInstructionSourcePath -Agent $agent
        if ([string]::IsNullOrWhiteSpace($sourceInstructionPath)) {
            $skipped++
            continue
        }

        $targetBundlePath = Resolve-VorceStudiosAgentInstructionBundlePath -Agent $agent -CompanyId $CompanyId
        if ([string]::IsNullOrWhiteSpace($targetBundlePath)) {
            $skipped++
            continue
        }

        $bundleDirectory = Split-Path -Parent $targetBundlePath
        if (-not [string]::IsNullOrWhiteSpace($bundleDirectory)) {
            Ensure-VorceStudiosDirectory -Path $bundleDirectory
        }

        $bundleFiles = $null
        try {
            $bundleFiles = Get-VorceStudiosManagedInstructionBundleFiles -Agent $agent -SourceInstructionPath $sourceInstructionPath
        } catch {
            $skipped++
            continue
        }

        foreach ($entry in $bundleFiles.GetEnumerator()) {
            $path = Join-Path $bundleDirectory $entry.Key
            $current = ''
            if (Test-Path -LiteralPath $path) {
                $current = Get-Content -LiteralPath $path -Raw
            }

            if ($current -eq [string]$entry.Value) {
                continue
            }

            [System.IO.File]::WriteAllText($path, [string]$entry.Value, (New-Object System.Text.UTF8Encoding($false)))
            $updated++
        }
    }

    return @{
        total = $agents.Count
        updated = $updated
        skipped = $skipped
        failed = $false
        error = ''
    }
}
