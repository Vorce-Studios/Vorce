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
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method,
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

function Reset-VorceStudiosAgentRuntimeSession {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [string]$TaskKey
    )

    $payload = @{}
    if (-not [string]::IsNullOrWhiteSpace($TaskKey)) {
        $payload.taskKey = $TaskKey
    }

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/agents/{0}/runtime-state/reset-session" -f $AgentId) -Body $payload
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

function Upgrade-VorceStudiosPlugin {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [string]$Version
    )

    $payload = @{}
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $payload['version'] = $Version
    }

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/plugins/{0}/upgrade" -f $PluginId) -Body $payload
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

function Get-VorceStudiosCompanySkills {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $items = Invoke-VorceStudiosApi -Method GET -Path ("/api/companies/{0}/skills" -f $CompanyId) -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Import-VorceStudiosCompanySkill {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$Source
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/companies/{0}/skills/import" -f $CompanyId) -Body @{
        source = $Source
    }
}

function Get-VorceStudiosAgentSkills {
    param(
        [Parameter(Mandatory)][string]$AgentId
    )

    $items = Invoke-VorceStudiosApi -Method GET -Path ("/api/agents/{0}/skills" -f $AgentId) -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Sync-VorceStudiosAgentSkills {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [AllowEmptyCollection()][string[]]$DesiredSkills = @()
    )

    return Invoke-VorceStudiosApi -Method POST -Path ("/api/agents/{0}/skills/sync" -f $AgentId) -Body @{
        desiredSkills = @($DesiredSkills)
    }
}

function Get-VorceStudiosSchedulerHeartbeats {
    $items = Invoke-VorceStudiosApi -Method GET -Path '/api/instance/scheduler-heartbeats' -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Get-VorceStudiosHeartbeatRuns {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [string]$AgentId,
        [int]$Limit = 20
    )

    $query = @()
    if (-not [string]::IsNullOrWhiteSpace($AgentId)) {
        $query += ('agentId={0}' -f [uri]::EscapeDataString($AgentId))
    }
    if ($Limit -gt 0) {
        $query += ('limit={0}' -f $Limit)
    }

    $path = "/api/companies/{0}/heartbeat-runs" -f $CompanyId
    if ($query.Count -gt 0) {
        $path = '{0}?{1}' -f $path, ($query -join '&')
    }

    $items = Invoke-VorceStudiosApi -Method GET -Path $path -IgnoreFailure
    if ($null -eq $items) {
        return @()
    }

    return @($items)
}

function Get-VorceStudiosHeartbeatRunLog {
    param(
        [Parameter(Mandatory)][string]$RunId
    )

    return Invoke-VorceStudiosApi -Method GET -Path ("/api/heartbeat-runs/{0}/log" -f $RunId) -IgnoreFailure
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

function Get-VorceStudiosManagedInstructionBundleContent {
    param(
        [Parameter(Mandatory)][object]$Agent,
        [Parameter(Mandatory)][string]$SourceInstructionPath
    )

    $agentName = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'name')
    $agentTitle = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'title')
    $instructionBody = (Get-Content -LiteralPath $SourceInstructionPath -Raw).Trim()
    $instructionBaseDir = Split-Path -Parent $SourceInstructionPath

    $safeName = $agentName -replace '"', '\"'
    $safeTitle = $agentTitle -replace '"', '\"'

    return @(
        '---'
        ('name: "{0}"' -f $safeName)
        ('title: "{0}"' -f $safeTitle)
        '---'
        ''
        ('_Instructions source: {0}_' -f $SourceInstructionPath)
        ('_Resolve any relative file references from {0}._' -f $instructionBaseDir)
        ''
        $instructionBody
        ''
    ) -join "`n"
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

        $content = ''
        try {
            $content = Get-VorceStudiosManagedInstructionBundleContent -Agent $agent -SourceInstructionPath $sourceInstructionPath
        } catch {
            $skipped++
            continue
        }
        $current = ''
        if (Test-Path -LiteralPath $targetBundlePath) {
            $current = Get-Content -LiteralPath $targetBundlePath -Raw
        }

        if ($current -eq $content) {
            continue
        }

        [System.IO.File]::WriteAllText($targetBundlePath, $content, (New-Object System.Text.UTF8Encoding($false)))
        $updated++
    }

    return @{
        total = $agents.Count
        updated = $updated
        skipped = $skipped
        failed = $false
        error = ''
    }
}
