[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$companyState = Get-VorceStudiosCompanyState
if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    throw 'Keine Company gefunden. Bitte zuerst Start- oder Initialize-Vorce-Studios.ps1 ausfuehren.'
}

$companyId = [string]$companyState.company.id
$agents = @(Get-VorceStudiosAgents -CompanyId $companyId)
$routing = Get-VorceStudiosPolicy -Name 'routing'
$shell = Get-VorceStudiosShellExecutable
$paths = Get-VorceStudiosPaths
$agentScript = Join-Path (Get-VorceStudiosRoot) 'scripts\paperclip\Invoke-Vorce-StudiosAgent.ps1'

if ($Apply.IsPresent -and -not (Test-VorceStudiosBoardAccess)) {
    Write-Warning 'Board-Admin-Rechte fehlen. Bitte in der Paperclip-Web-UI einloggen und danach Clean-VorceStudiosAgents.ps1 -Apply erneut ausfuehren.'
    return
}

$desiredAgents = [ordered]@{
    'ceo' = @{
        name = $routing.Roles.ceo
        role = 'ceo'
        title = 'Strategic owner, escalation and release authority'
        icon = 'crown'
        capabilities = 'Architecture, prioritization, escalation, release decisions'
        instructionFile = 'ceo.md'
        reportsTo = $null
    }
    'lena_assistant' = @{
        name = $routing.Roles.lena_assistant
        role = 'assistant'
        title = 'Personal assistant to CEO, briefing and filtering'
        icon = 'clipboard'
        capabilities = 'Issue aggregation, briefing generation, routine filtering'
        instructionFile = 'lena-assistant.md'
        reportsTo = 'ceo'
    }
    'chief_of_staff' = @{
        name = $routing.Roles.chief_of_staff
        role = 'pm'
        title = 'Dynamic routing, queue health and capacity failover'
        icon = 'radar'
        capabilities = 'Routing, quota management, task assignment'
        instructionFile = 'chief-of-staff.md'
        reportsTo = 'ceo'
    }
    'discovery' = @{
        name = $routing.Roles.discovery
        role = 'researcher'
        title = 'Proactive discovery and backlog enrichment'
        icon = 'search'
        capabilities = 'Issue discovery, regression scanning, stale failure triage'
        instructionFile = 'discovery-scout.md'
        reportsTo = 'chief_of_staff'
    }
    'jules' = @{
        name = $routing.Roles.jules
        role = 'engineer'
        title = 'Primary low-cost implementation worker via Jules'
        icon = 'wand'
        capabilities = 'Issue implementation, Jules session orchestration'
        instructionFile = 'jules-builder.md'
        reportsTo = 'chief_of_staff'
    }
    'jules_monitor' = @{
        name = $routing.Roles.jules_monitor
        role = 'qa'
        title = 'Jules session monitoring and deadlock resolution'
        icon = 'activity'
        capabilities = 'Session monitoring, timeout detection, escalation'
        instructionFile = 'jules-session-monitor.md'
        reportsTo = 'chief_of_staff'
    }
    'pr_monitor' = @{
        name = $routing.Roles.pr_monitor
        role = 'qa'
        title = 'GitHub PR monitoring and CI check management'
        icon = 'git-pull-request'
        capabilities = 'PR status tracking, CI retry, conflict detection'
        instructionFile = 'github-pr-monitor.md'
        reportsTo = 'chief_of_staff'
    }
    'gemini_review' = @{
        name = $routing.Roles.gemini_review
        role = 'qa'
        title = 'Preferred reviewer and analysis worker'
        icon = 'shield'
        capabilities = 'Review, triage, summary generation'
        instructionFile = 'gemini-reviewer.md'
        reportsTo = 'chief_of_staff'
    }
    'qwen_review' = @{
        name = $routing.Roles.qwen_review
        role = 'qa'
        title = 'Fallback reviewer and triage worker'
        icon = 'shield'
        capabilities = 'Fallback review, diff summaries, bug triage'
        instructionFile = 'qwen-reviewer.md'
        reportsTo = 'chief_of_staff'
    }
    'codex_review' = @{
        name = $routing.Roles.codex_review
        role = 'cto'
        title = 'High-risk reviewer and architecture escalation worker'
        icon = 'brain'
        capabilities = 'High-risk review, architecture and difficult debugging'
        instructionFile = 'codex-reviewer.md'
        reportsTo = 'chief_of_staff'
    }
    'ops' = @{
        name = $routing.Roles.ops
        role = 'devops'
        title = 'PR checks, governance and merge stewardship'
        icon = 'terminal'
        capabilities = 'Checks, merge gates, audit notes, status maintenance'
        instructionFile = 'ops-steward.md'
        reportsTo = 'chief_of_staff'
    }
    'atlas' = @{
        name = $routing.Roles.atlas
        role = 'researcher'
        title = 'Optional atlas-backed repo context worker'
        icon = 'microscope'
        capabilities = 'Atlas summaries, codebase map, context distillation'
        instructionFile = 'atlas-context.md'
        reportsTo = 'discovery'
    }
    'antigravity' = @{
        name = $routing.Roles.antigravity
        role = 'engineer'
        title = 'Antigravity swarm builder for parallel multi-agent missions'
        icon = 'zap'
        capabilities = 'Swarm orchestration, parallel execution, multi-crate work'
        instructionFile = 'antigravity-builder.md'
        reportsTo = 'chief_of_staff'
    }
}

function New-VorceStudiosDesiredAgentPayload {
    param(
        [Parameter(Mandatory)][string]$RoleKey,
        [Parameter(Mandatory)][hashtable]$Definition
    )

    return @{
        name = $Definition.name
        role = $Definition.role
        title = $Definition.title
        icon = $Definition.icon
        capabilities = $Definition.capabilities
        adapterType = 'process'
        adapterConfig = @{
            command = $shell
            commandArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentScript, '-Role', $RoleKey)
            cwd = $paths.Root
            env = @{
                VORCE_STUDIOS_ROLE = $RoleKey
            }
        }
        runtimeConfig = @{
            instructionPath = Join-Path $paths.InstructionsDir $Definition.instructionFile
            policyRoot = $paths.PoliciesDir
        }
        budgetMonthlyCents = 0
        permissions = @{
            canCreateAgents = ($RoleKey -eq 'ceo')
        }
        metadata = @{
            roleKey = $RoleKey
            instructionFile = $Definition.instructionFile
        }
    }
}

function Invoke-VorceStudiosAgentCleanupAction {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    if (-not $Apply.IsPresent) {
        Write-Host ("  WOULD: {0}" -f $Description) -ForegroundColor Yellow
        return $null
    }

    try {
        return (& $Action)
    } catch {
        if ($_.Exception.Message -match 'Board access required|403') {
            throw 'Board-Admin-Rechte fehlen. Bitte in der Paperclip-Web-UI einloggen und den Bereinigungslauf erneut starten.'
        }
        throw
    }
}

$agentsByRoleKey = @{}
foreach ($agent in $agents) {
    $metadata = Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata'
    $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'roleKey')
    if (-not $agentsByRoleKey.ContainsKey($roleKey)) {
        $agentsByRoleKey[$roleKey] = @()
    }
    $agentsByRoleKey[$roleKey] += $agent
}

$keptAgentByKey = @{}
Write-Host '=== Duplikate bereinigen ===' -ForegroundColor Yellow
foreach ($roleKey in $desiredAgents.Keys) {
    $list = if ($agentsByRoleKey.ContainsKey($roleKey)) { @($agentsByRoleKey[$roleKey]) } else { @() }
    if ($list.Count -eq 0) {
        continue
    }

    $definition = $desiredAgents[$roleKey]
    $keep = $list | Where-Object { [string]$_.name -eq [string]$definition.name } | Select-Object -First 1
    if ($null -eq $keep) {
        $keep = $list | Sort-Object createdAt | Select-Object -First 1
    }
    $keptAgentByKey[$roleKey] = $keep

    foreach ($agent in $list) {
        if ([string]$agent.id -eq [string]$keep.id) {
            continue
        }

        $description = "Loesche Duplikat $($agent.name) [$roleKey]"
        Invoke-VorceStudiosAgentCleanupAction -Description $description -Action {
            Invoke-VorceStudiosApi -Method DELETE -Path "/api/agents/$($agent.id)" | Out-Null
            Write-Host ("  OK: {0}" -f $description) -ForegroundColor Green
        } | Out-Null
    }
}

Write-Host ''
Write-Host '=== Fehlende Agenten erstellen ===' -ForegroundColor Yellow
foreach ($roleKey in $desiredAgents.Keys) {
    if ($keptAgentByKey.ContainsKey($roleKey)) {
        continue
    }

    $definition = $desiredAgents[$roleKey]
    $payload = New-VorceStudiosDesiredAgentPayload -RoleKey $roleKey -Definition $definition
    $description = "Erstelle $($definition.name) [$roleKey]"
    $created = Invoke-VorceStudiosAgentCleanupAction -Description $description -Action {
        $newAgent = New-VorceStudiosAgent -CompanyId $companyId -Payload $payload
        Write-Host ("  OK: {0}" -f $description) -ForegroundColor Green
        return $newAgent
    }
    if ($null -ne $created) {
        $keptAgentByKey[$roleKey] = $created
    }
}

if ($Apply.IsPresent) {
    $agents = @(Get-VorceStudiosAgents -CompanyId $companyId)
    $keptAgentByKey = @{}
    foreach ($agent in $agents) {
        $metadata = Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata'
        $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'roleKey')
        if ([string]::IsNullOrWhiteSpace($roleKey) -or $keptAgentByKey.ContainsKey($roleKey)) {
            continue
        }
        $keptAgentByKey[$roleKey] = $agent
    }
}

Write-Host ''
Write-Host '=== Agenten normalisieren ===' -ForegroundColor Yellow
foreach ($roleKey in $desiredAgents.Keys) {
    if (-not $keptAgentByKey.ContainsKey($roleKey)) {
        continue
    }

    $agent = $keptAgentByKey[$roleKey]
    $definition = $desiredAgents[$roleKey]
    $payload = @{}

    foreach ($property in @('name', 'role', 'title', 'icon', 'capabilities')) {
        if ([string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName $property) -ne [string]$definition[$property]) {
            $payload[$property] = $definition[$property]
        }
    }

    $runtimeConfig = @{
        instructionPath = Join-Path $paths.InstructionsDir $definition.instructionFile
        policyRoot = $paths.PoliciesDir
    }
    $permissions = @{
        canCreateAgents = ($roleKey -eq 'ceo')
    }
    $metadata = @{
        roleKey = $roleKey
        instructionFile = $definition.instructionFile
    }

    if (-not (Test-VorceStudiosJsonEquivalent -Left (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'runtimeConfig') -Right $runtimeConfig)) {
        $payload['runtimeConfig'] = $runtimeConfig
    }
    if (-not (Test-VorceStudiosJsonEquivalent -Left (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'permissions') -Right $permissions)) {
        $payload['permissions'] = $permissions
    }
    if (-not (Test-VorceStudiosJsonEquivalent -Left (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata') -Right $metadata)) {
        $payload['metadata'] = $metadata
    }

    if ($payload.Count -eq 0) {
        Write-Host ("  Bereits konsistent: {0}" -f $definition.name) -ForegroundColor DarkGray
        continue
    }

    $description = "Normalisiere $($definition.name) [$roleKey]"
    $updated = Invoke-VorceStudiosAgentCleanupAction -Description $description -Action {
        $result = Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload $payload
        Write-Host ("  OK: {0}" -f $description) -ForegroundColor Green
        return $result
    }
    if ($null -ne $updated) {
        $keptAgentByKey[$roleKey] = $updated
    }
}

Write-Host ''
Write-Host '=== reportsTo setzen ===' -ForegroundColor Yellow
foreach ($roleKey in $desiredAgents.Keys) {
    $definition = $desiredAgents[$roleKey]
    if (-not $keptAgentByKey.ContainsKey($roleKey)) {
        continue
    }

    $agent = $keptAgentByKey[$roleKey]
    $desiredReportsTo = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$definition.reportsTo) -and $keptAgentByKey.ContainsKey([string]$definition.reportsTo)) {
        $desiredReportsTo = [string]$keptAgentByKey[[string]$definition.reportsTo].id
    }

    $currentReportsTo = [string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'reportsTo')
    $reportsToMatches = (
        ([string]::IsNullOrWhiteSpace($currentReportsTo) -and [string]::IsNullOrWhiteSpace([string]$desiredReportsTo)) -or
        ($currentReportsTo -eq [string]$desiredReportsTo)
    )

    if ($reportsToMatches) {
        Write-Host ("  Bereits korrekt: {0}" -f $definition.name) -ForegroundColor DarkGray
        continue
    }

    $description = "Setze reportsTo fuer $($definition.name) [$roleKey]"
    $updated = Invoke-VorceStudiosAgentCleanupAction -Description $description -Action {
        $result = Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
            reportsTo = $desiredReportsTo
        }
        Write-Host ("  OK: {0}" -f $description) -ForegroundColor Green
        return $result
    }
    if ($null -ne $updated) {
        $keptAgentByKey[$roleKey] = $updated
    }
}

Write-Host ''
Write-Host '=== Instruction Bundles ===' -ForegroundColor Yellow
if (-not $Apply.IsPresent) {
    Write-Host '  WOULD: Sync managed AGENTS.md bundles' -ForegroundColor Yellow
} else {
    $instructionSync = Sync-VorceStudiosManagedAgentInstructions -CompanyId $companyId
    if ($instructionSync.failed) {
        Write-Warning ("Instruction-Bundle-Sync fehlgeschlagen: {0}" -f [string]$instructionSync.error)
    } else {
        Write-Host ("  OK: updated={0}, skipped={1}" -f [int]$instructionSync.updated, [int]$instructionSync.skipped) -ForegroundColor Green
    }
}

Write-Host ''
if ($Apply.IsPresent) {
    Write-Host 'Bereinigung abgeschlossen.' -ForegroundColor Cyan
} else {
    Write-Host 'Dry-run abgeschlossen. Mit -Apply ausfuehren, um Aenderungen zu uebernehmen.' -ForegroundColor Cyan
}
