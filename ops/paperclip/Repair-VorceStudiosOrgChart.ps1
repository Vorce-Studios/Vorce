[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$routing = Get-VorceStudiosPolicy -Name 'routing'
$companyState = Get-VorceStudiosCompanyState

if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    Write-Host 'Fehler: Keine Company gefunden.' -ForegroundColor Red
    exit 1
}

$companyId = [string]$companyState.company.id
$agents = @(Get-VorceStudiosAgents -CompanyId $companyId)

Write-Host "Gefundene Agenten ($($agents.Count)):" -ForegroundColor Cyan
foreach ($a in $agents) {
    $metaRole = ''
    if ($a.metadata -and $a.metadata.roleKey) { $metaRole = [string]$a.metadata.roleKey }
    $reportsTo = ''
    if ($a.PSObject.Properties['reportsTo'] -and $null -ne $a.reportsTo) { $reportsTo = [string]$a.reportsTo }
    Write-Host "  [$metaRole] $($a.name) (id: $($a.id), reportsTo: $reportsTo)" -ForegroundColor DarkGray
}
Write-Host ''

# ===== 1. BESTEHENDE AGENTEN DURCH metadata.roleKey FINDEN =====
$agentByKey = @{}
foreach ($agent in $agents) {
    if ($agent.metadata -and $agent.metadata.roleKey) {
        $key = [string]$agent.metadata.roleKey
        $agentByKey[$key] = $agent
    }
}

# Fuer Keys ohne metadata: versuche ueber Name-Pattern zu matchen
if (-not $agentByKey.ContainsKey('ceo')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'ceo' -or [string]$a.name -match 'CEO|Victor') {
            $agentByKey['ceo'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('chief_of_staff')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'pm' -and [string]$a.name -match 'Chief|Leon|Liam') {
            $agentByKey['chief_of_staff'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('discovery')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'researcher' -and [string]$a.name -match 'Discovery|Noah') {
            $agentByKey['discovery'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('jules')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'engineer' -and [string]$a.name -match 'Julio.*Builder|Jules.*Builder|Julio \(Builder\)|Jules \(Builder\)') {
            $agentByKey['jules'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('gemini_review')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'qa' -and [string]$a.name -match 'Gemini|Mia') {
            $agentByKey['gemini_review'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('qwen_review')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'qa' -and [string]$a.name -match 'Qwen|Elias') {
            $agentByKey['qwen_review'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('codex_review')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'cto' -and [string]$a.name -match 'Codex|Caleb') {
            $agentByKey['codex_review'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('ops')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'devops' -and [string]$a.name -match 'Ops|Sophia') {
            $agentByKey['ops'] = $a; break
        }
    }
}
if (-not $agentByKey.ContainsKey('atlas')) {
    foreach ($a in $agents) {
        if ([string]$a.role -eq 'researcher' -and [string]$a.name -match 'Atlas') {
            $agentByKey['atlas'] = $a; break
        }
    }
}

Write-Host "Zugeordnete Agenten: $($agentByKey.Count) von 13" -ForegroundColor Cyan
Write-Host ''

# ===== 2. FEHLENDE AGENTEN ERSTELLEN =====
$shell = Get-VorceStudiosShellExecutable
$agentScript = Join-Path (Get-VorceStudiosRoot) 'ops\paperclip\qwen-agent.ps1'
$paths = Get-VorceStudiosPaths

$desiredAgents = [ordered]@{
    'ceo'              = @{ role='ceo'; title='Strategic owner, escalation and release authority'; icon='crown'; caps='Architecture, prioritization, escalation, release decisions'; inst='ceo.md' }
    'lena_assistant'   = @{ role='assistant'; title='Personal assistant to CEO, briefing and filtering'; icon='clipboard'; caps='Issue aggregation, briefing generation, routine filtering'; inst='lena-assistant.md' }
    'chief_of_staff'   = @{ role='pm'; title='Dynamic routing, queue health and capacity failover'; icon='radar'; caps='Routing, quota management, task assignment'; inst='chief-of-staff.md' }
    'discovery'        = @{ role='researcher'; title='Proactive discovery and backlog enrichment'; icon='search'; caps='Issue discovery, regression scanning, stale failure triage'; inst='discovery-scout.md' }
    'jules'            = @{ role='engineer'; title='Primary implementation worker via Jules'; icon='wand'; caps='Issue implementation, Jules session orchestration'; inst='jules-builder.md' }
    'jules_monitor'    = @{ role='qa'; title='Jules session monitoring and deadlock resolution'; icon='activity'; caps='Session monitoring, timeout detection, escalation'; inst='jules-session-monitor.md' }
    'pr_monitor'       = @{ role='qa'; title='GitHub PR monitoring and CI check management'; icon='git-pull-request'; caps='PR status tracking, CI retry, conflict detection'; inst='github-pr-monitor.md' }
    'gemini_review'    = @{ role='qa'; title='Preferred reviewer and analysis worker'; icon='shield'; caps='Review, triage, summary generation'; inst='gemini-reviewer.md' }
    'qwen_review'      = @{ role='qa'; title='Fallback reviewer and triage worker'; icon='shield'; caps='Fallback review, diff summaries, bug triage'; inst='qwen-reviewer.md' }
    'codex_review'     = @{ role='cto'; title='High-risk reviewer and architecture escalation worker'; icon='brain'; caps='High-risk review, architecture and difficult debugging'; inst='codex-reviewer.md' }
    'ops'              = @{ role='devops'; title='PR checks, governance and merge stewardship'; icon='terminal'; caps='Checks, merge gates, audit notes, status maintenance'; inst='ops-steward.md' }
    'atlas'            = @{ role='researcher'; title='Atlas-backed repo context worker'; icon='microscope'; caps='Atlas summaries, codebase map, context distillation'; inst='atlas-context.md' }
    'antigravity'      = @{ role='engineer'; title='Antigravity swarm builder for parallel missions'; icon='zap'; caps='Swarm orchestration, parallel execution, multi-crate work'; inst='antigravity-builder.md' }
}

foreach ($key in $desiredAgents.Keys) {
    if ($agentByKey.ContainsKey($key)) { continue }

    $cfg = $desiredAgents[$key]
    $agentName = $routing.Roles.$key
    if ([string]::IsNullOrWhiteSpace($agentName)) { $agentName = $cfg.title }

    Write-Host "Erstelle $agentName ($key)..." -NoNewline

    $payload = @{
        name = $agentName
        role = $cfg.role
        title = $cfg.title
        icon = $cfg.icon
        capabilities = $cfg.caps
        adapterType = 'process'
        adapterConfig = @{
            command = $shell
            commandArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentScript)
            cwd = $paths.Root
            env = @{ VORCE_STUDIOS_ROLE = $key }
        }
        runtimeConfig = @{
            instructionPath = Join-Path $paths.InstructionsDir $cfg.inst
            policyRoot = $paths.PoliciesDir
        }
        budgetMonthlyCents = 0
        permissions = @{ canCreateAgents = ($key -eq 'ceo') }
        metadata = @{
            roleKey = $key
            instructionFile = $cfg.inst
        }
    }

    try {
        $created = Invoke-VorceStudiosApi -Method POST -Path "/api/companies/$companyId/agents" -Body $payload -IgnoreFailure
        if ($null -ne $created) {
            $agentByKey[$key] = $created
            Write-Host ' OK' -ForegroundColor Green
        } else {
            Write-Host ' FEHLER' -ForegroundColor Red
        }
    } catch {
        Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ===== 3. REPORTSTo SETZEN =====
$reportsToMap = @{
    'lena_assistant'   = 'ceo'
    'chief_of_staff'   = 'ceo'
    'discovery'        = 'chief_of_staff'
    'jules'            = 'chief_of_staff'
    'jules_monitor'    = 'chief_of_staff'
    'pr_monitor'       = 'chief_of_staff'
    'gemini_review'    = 'chief_of_staff'
    'qwen_review'      = 'chief_of_staff'
    'codex_review'     = 'chief_of_staff'
    'ops'              = 'chief_of_staff'
    'atlas'            = 'discovery'
    'antigravity'      = 'chief_of_staff'
}

Write-Host ''
Write-Host '=== reportsTo setzen ===' -ForegroundColor Yellow

foreach ($entry in $reportsToMap.GetEnumerator()) {
    $agentKey = $entry.Key
    $managerKey = $entry.Value

    $agent = $agentByKey[$agentKey]
    $manager = $agentByKey[$managerKey]

    if ($null -eq $agent) {
        Write-Host "  $agentKey : Agent nicht gefunden" -ForegroundColor Red
        continue
    }
    if ($null -eq $manager) {
        Write-Host "  $($agent.name) -> Manager $managerKey nicht gefunden" -ForegroundColor Red
        continue
    }

    $managerName = [string]$manager.name

    $currentReportsTo = ''
    if ($agent.PSObject.Properties['reportsTo'] -and $null -ne $agent.reportsTo) {
        $currentReportsTo = [string]$agent.reportsTo
    }

    if ($currentReportsTo -eq $managerName) {
        Write-Host "  $($agent.name) -> $managerName : bereits korrekt" -ForegroundColor DarkGray
        continue
    }

    Write-Host "  $($agent.name) -> $managerName" -NoNewline
    try {
        $result = Invoke-VorceStudiosApi -Method PATCH -Path "/api/agents/$($agent.id)" -Body @{ reportsTo = $managerName } -IgnoreFailure
        if ($null -ne $result) {
            Write-Host ' OK' -ForegroundColor Green
        } else {
            Write-Host ' FEHLER (keine Antwort)' -ForegroundColor Red
        }
    } catch {
        Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host 'Fertig. Org-Chart: http://localhost:3140/VOR/org' -ForegroundColor Cyan

$syncScript = Join-Path $ScriptDir 'Sync-Vorce-StudiosPaperclip.ps1'
if (Test-Path -LiteralPath $syncScript) {
    Write-Host 'Fuehre anschliessend den zentralen Paperclip-Sync aus...' -ForegroundColor Yellow
    & $syncScript -SkipPlugins -SkipInstructions -SkipVictorSkills | Out-Null
}
