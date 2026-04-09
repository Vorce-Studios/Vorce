[CmdletBinding()]
param(
    [switch]$SkipPlugins,
    [switch]$SkipInstructions,
    [switch]$SkipHeartbeats,
    [switch]$SkipVictorSkills
)

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipPlugins.ps1')

$LocalAdapterTypes = @('claude_local', 'codex_local', 'cursor', 'gemini_local', 'opencode_local', 'pi_local')
$HeartbeatPolicyByRoleKey = @{
    ceo = 'CEO'
    chief_of_staff = 'ChiefOfStaff'
    lena_assistant = 'LenaAssistant'
    antigravity = 'AntigravityBuilder'
    atlas = 'DiscoveryScout'
    codex_review = 'ReviewPool'
    gemini_review = 'ReviewPool'
    discovery = 'DiscoveryScout'
    qwen_review = 'ReviewPool'
    jules = 'JulesBuilder'
    jules_monitor = 'JulesSessionMonitor'
    pr_monitor = 'PrMonitor'
    ops = 'OpsSteward'
}
$AutonomousAdapterTargetsByRoleKey = @{
    qwen_review = @{
        adapterType = 'gemini_local'
        adapterConfig = @{
            yolo = $true
            model = 'auto'
            graceSec = 15
            timeoutSec = 600
            instructionsBundleMode = 'managed'
        }
    }
    jules_monitor = @{
        adapterType = 'gemini_local'
        adapterConfig = @{
            yolo = $true
            model = 'auto'
            graceSec = 15
            timeoutSec = 600
            instructionsBundleMode = 'managed'
        }
    }
    jules = @{
        adapterType = 'codex_local'
        adapterConfig = @{
            model = 'gpt-5.4'
            graceSec = 15
            timeoutSec = 600
            instructionsBundleMode = 'managed'
            dangerouslyBypassApprovalsAndSandbox = $true
        }
    }
    pr_monitor = @{
        adapterType = 'codex_local'
        adapterConfig = @{
            model = 'gpt-5.3-codex'
            search = $true
            graceSec = 15
            timeoutSec = 600
            instructionsBundleMode = 'managed'
            dangerouslyBypassApprovalsAndSandbox = $true
        }
    }
}
$LeadershipSkillSources = @(
    'paperclipai/paperclip/paperclip',
    'paperclipai/paperclip/paperclip-create-agent',
    'paperclipai/paperclip/paperclip-create-plugin',
    'paperclipai/paperclip/para-memory-files',
    'obra/superpowers/dispatching-parallel-agents',
    'obra/superpowers/brainstorming',
    'github/awesome-copilot/gh-cli',
    'github/awesome-copilot/refactor-plan',
    'github/awesome-copilot/create-agentsmd',
    'vercel-labs/skills/find-skills'
)

function Merge-VorceStudiosHashtable {
    param(
        [AllowNull()][object]$Base,
        [AllowNull()][object]$Overlay
    )

    $result = @{}
    $baseMap = ConvertTo-VorceStudiosHashtable -InputObject $Base
    $overlayMap = ConvertTo-VorceStudiosHashtable -InputObject $Overlay

    if ($baseMap -is [System.Collections.IDictionary]) {
        foreach ($key in $baseMap.Keys) {
            $result[[string]$key] = $baseMap[$key]
        }
    }

    if ($overlayMap -is [System.Collections.IDictionary]) {
        foreach ($key in $overlayMap.Keys) {
            $keyString = [string]$key
            $overlayValue = $overlayMap[$key]
            if (($result[$keyString] -is [System.Collections.IDictionary]) -and ($overlayValue -is [System.Collections.IDictionary])) {
                $result[$keyString] = Merge-VorceStudiosHashtable -Base $result[$keyString] -Overlay $overlayValue
            } else {
                $result[$keyString] = $overlayValue
            }
        }
    }

    return $result
}

function ConvertTo-VorceStudiosMarkdownList {
    param(
        [AllowEmptyCollection()][string[]]$Items = @()
    )

    if ($Items.Count -eq 0) {
        return '- none'
    }

    return ($Items | ForEach-Object { '- {0}' -f $_ }) -join "`n"
}

function Get-VorceStudiosInstructionTemplatePath {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $metadata = Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'metadata'
    $instructionFile = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'instructionFile')
    if ([string]::IsNullOrWhiteSpace($instructionFile)) {
        return $null
    }

    $candidate = Join-Path (Get-VorceStudiosPaths).InstructionsDir $instructionFile
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $null
    }

    return $candidate
}

function Get-VorceStudiosManagedInstructionRoot {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$AgentId
    )

    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy
    return Join-Path $paths.PaperclipHome ("instances\{0}\companies\{1}\agents\{2}\instructions" -f $system.Company.InstanceId, $CompanyId, $AgentId)
}

function Get-VorceStudiosManagedInstructionAdapterConfig {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][string]$AgentId
    )

    $root = Get-VorceStudiosManagedInstructionRoot -CompanyId $CompanyId -AgentId $AgentId
    return [ordered]@{
        instructionsFilePath = Join-Path $root 'AGENTS.md'
        instructionsRootPath = $root
        instructionsEntryFile = 'AGENTS.md'
        instructionsBundleMode = 'managed'
    }
}

function New-VorceStudiosCliProbeResult {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [bool]$Available = $false,
        [string]$Reason = ''
    )

    return [ordered]@{
        tool = $Tool
        available = $Available
        reason = $Reason
    }
}

function Test-VorceStudiosCliSmoke {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $command = Get-Command $Tool -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return New-VorceStudiosCliProbeResult -Tool $Tool -Reason 'command-not-found'
    }

    try {
        $output = (& $command.Source @Arguments 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0) {
            return New-VorceStudiosCliProbeResult -Tool $Tool -Available $true -Reason 'ok'
        }

        if ($output -match 'QUOTA_EXHAUSTED') {
            return New-VorceStudiosCliProbeResult -Tool $Tool -Reason 'quota-exhausted'
        }

        if ($output -match 'usage limit') {
            return New-VorceStudiosCliProbeResult -Tool $Tool -Reason 'usage-limit'
        }

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            return New-VorceStudiosCliProbeResult -Tool $Tool -Reason $output
        }
    } catch {
        return New-VorceStudiosCliProbeResult -Tool $Tool -Reason $_.Exception.Message
    }

    return New-VorceStudiosCliProbeResult -Tool $Tool -Reason 'probe-failed'
}

function Get-VorceStudiosLocalToolAvailability {
    $availability = [ordered]@{}
    $availability['codex'] = Test-VorceStudiosCliSmoke -Tool 'codex' -Arguments @('exec', '--dangerously-bypass-approvals-and-sandbox', '-s', 'danger-full-access', '--skip-git-repo-check', 'Reply with OK only.')
    $availability['qwen'] = Test-VorceStudiosCliSmoke -Tool 'qwen' -Arguments @('-y', '-p', 'Reply with OK only.')
    $availability['gemini'] = Test-VorceStudiosCliSmoke -Tool 'gemini' -Arguments @('-m', 'gemini-2.5-flash', '--output-format', 'json', '-p', 'Reply with OK only.')
    return $availability
}

function New-VorceStudiosCodexLocalTarget {
    param(
        [int]$TimeoutSec = 600,
        [switch]$Search,
        [string]$ReasoningEffort = 'high'
    )

    return [ordered]@{
        adapterType = 'codex_local'
        adapterConfig = [ordered]@{
            model = 'gpt-5.4'
            graceSec = 15
            timeoutSec = $TimeoutSec
            search = $Search.IsPresent
            modelReasoningEffort = $ReasoningEffort
            dangerouslyBypassApprovalsAndSandbox = $true
        }
    }
}

function New-VorceStudiosGeminiLocalTarget {
    param(
        [int]$TimeoutSec = 600
    )

    return [ordered]@{
        adapterType = 'gemini_local'
        adapterConfig = [ordered]@{
            yolo = $true
            model = 'auto'
            graceSec = 15
            timeoutSec = $TimeoutSec
            instructionsBundleMode = 'managed'
        }
    }
}

function New-VorceStudiosQwenProcessTarget {
    param(
        [int]$TimeoutSec = 600
    )

    $paths = Get-VorceStudiosPaths
    $shell = Get-VorceStudiosShellExecutable
    $scriptPath = Join-Path $paths.Root 'ops\paperclip\qwen-agent.ps1'

    return [ordered]@{
        adapterType = 'process'
        adapterConfig = [ordered]@{
            command = $shell
            commandArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
            cwd = $paths.Root
            graceSec = 15
            timeoutSec = $TimeoutSec
            env = @{}
        }
    }
}

function Get-VorceStudiosManagedInstructionProcessEnv {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][object]$Agent
    )

    $paths = Get-VorceStudiosPaths
    $agentId = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'id')
    $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'metadata') -PropertyName 'roleKey')
    $instructionSourcePath = Resolve-VorceStudiosAgentInstructionSourcePath -Agent $Agent
    $managedConfig = Get-VorceStudiosManagedInstructionAdapterConfig -CompanyId $CompanyId -AgentId $agentId

    return [ordered]@{
        VORCE_STUDIOS_ROLE = $roleKey
        INSTRUCTION_PATH = $instructionSourcePath
        POLICY_ROOT = $paths.PoliciesDir
        INSTRUCTION_BUNDLE_ROOT = [string](Get-VorceStudiosObjectPropertyValue -Object $managedConfig -PropertyName 'instructionsRootPath')
        INSTRUCTION_ENTRY_FILE = [string](Get-VorceStudiosObjectPropertyValue -Object $managedConfig -PropertyName 'instructionsEntryFile')
    }
}

function Get-VorceStudiosAutonomousAdapterTarget {
    param(
        [Parameter(Mandatory)][string]$RoleKey,
        [Parameter(Mandatory)][hashtable]$Availability
    )

    $codexAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $Availability -PropertyName 'codex') -PropertyName 'available')
    $qwenAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $Availability -PropertyName 'qwen') -PropertyName 'available')
    $geminiAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $Availability -PropertyName 'gemini') -PropertyName 'available')

    switch ($RoleKey) {
        'ceo' {
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 900 -Search -ReasoningEffort 'xhigh' }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 900 }
            return New-VorceStudiosGeminiLocalTarget -TimeoutSec 900
        }
        'chief_of_staff' {
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 900 -ReasoningEffort 'high' }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 900 }
            return New-VorceStudiosGeminiLocalTarget -TimeoutSec 900
        }
        'codex_review' {
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 900 -ReasoningEffort 'high' }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 900 }
            return New-VorceStudiosGeminiLocalTarget -TimeoutSec 900
        }
        'lena_assistant' { if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 } }
        'jules_monitor' { if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 } }
        'pr_monitor' { if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 } }
        'qwen_review' { if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 } }
        'discovery' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 600 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 600 -ReasoningEffort 'medium' }
        }
        'jules' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 600 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 600 -ReasoningEffort 'medium' }
        }
        'gemini_review' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 600 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 600 -ReasoningEffort 'medium' }
        }
        'ops' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 600 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 600 -ReasoningEffort 'medium' }
        }
        'atlas' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 600 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 600 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 600 -ReasoningEffort 'medium' }
        }
        'antigravity' {
            if ($geminiAvailable) { return New-VorceStudiosGeminiLocalTarget -TimeoutSec 900 }
            if ($qwenAvailable) { return New-VorceStudiosQwenProcessTarget -TimeoutSec 900 }
            if ($codexAvailable) { return New-VorceStudiosCodexLocalTarget -TimeoutSec 900 -ReasoningEffort 'high' }
        }
    }

    return $null
}

function New-VorceStudiosGenericInstructionContent {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $name = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'name')
    $role = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'role')
    $title = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'title')
    $capabilities = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'capabilities')

    return @(
        '# Role'
        ("You are {0}, {1}." -f $name, $title)
        ''
        '## Mission'
        ('Operate as the Paperclip {0} for Vorce-Studios and keep work aligned with the company goals and assigned issues.' -f $role)
        ''
        '## Capabilities'
        (if ([string]::IsNullOrWhiteSpace($capabilities)) { '- Use the available local tooling and Paperclip APIs to complete assigned work.' } else { '- {0}' -f $capabilities })
        ''
        '## Operating Rules'
        '- Prefer concrete execution over abstract planning when the next action is clear.'
        '- Keep changes scoped, verifiable, and consistent with the local repository.'
        '- Escalate blockers explicitly instead of silently stalling.'
    ) -join "`n"
}

function New-VorceStudiosManagedAgentsContent {
    param(
        [Parameter(Mandatory)][string]$BaseContent
    )

    $trimmed = $BaseContent.Trim()
    $referenceBlock = @(
        '## Working Set',
        '- Read `SOUL.md`, `HEARTBEAT.md`, `GOALS.md`, `SKILLS.md`, and `TOOLS.md` before substantial work.',
        '- Treat `GOALS.md` as the live assignment and company-priority projection for this agent.',
        '- Treat `SKILLS.md` as the live Paperclip skill snapshot for this agent.',
        '- Use the Paperclip API for issue, goal, approval, heartbeat, and plugin mutations when operating inside the control plane.'
    ) -join "`n"

    if ($trimmed -match 'GOALS\.md' -and $trimmed -match 'SKILLS\.md' -and $trimmed -match 'HEARTBEAT\.md') {
        return $trimmed + "`n"
    }

    return ($trimmed + "`n`n" + $referenceBlock + "`n")
}

function New-VorceStudiosSoulContent {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $name = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'name')
    $role = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'role')
    $title = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'title')
    $capabilities = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'capabilities')
    $strengthLine = if ([string]::IsNullOrWhiteSpace($capabilities)) { '- Use the available adapter and repository context effectively.' } else { '- {0}' -f $capabilities }

    return @(
        '# SOUL.md'
        ''
        ('Identity: {0} ({1})' -f $name, $title)
        ('Role Key: {0}' -f $role)
        ''
        '## Operating Intent'
        '- Keep Vorce shipping by reducing ambiguity, executing assigned work, and surfacing blockers quickly.'
        '- Preserve autonomy without freelancing outside the current company goals.'
        '- Prefer durable fixes over temporary workarounds when the scope is controlled.'
        ''
        '## Native Strengths'
        $strengthLine
        ''
        '## Non-Negotiables'
        '- Stay consistent with the managed instructions bundle in this directory.'
        '- Do not ignore failing heartbeats or stale assignments.'
        '- Leave the system in a state that the next heartbeat can continue autonomously.'
    ) -join "`n"
}

function New-VorceStudiosHeartbeatContent {
    param(
        [Parameter(Mandatory)][object]$Agent
    )

    $runtimeConfig = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'runtimeConfig')
    $heartbeat = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $runtimeConfig -PropertyName 'heartbeat')
    $interval = [string](Get-VorceStudiosObjectPropertyValue -Object $heartbeat -PropertyName 'intervalSec')
    $cooldown = [string](Get-VorceStudiosObjectPropertyValue -Object $heartbeat -PropertyName 'cooldownSec')
    $wakeOnDemand = [string](Get-VorceStudiosObjectPropertyValue -Object $heartbeat -PropertyName 'wakeOnDemand')
    $maxConcurrentRuns = [string](Get-VorceStudiosObjectPropertyValue -Object $heartbeat -PropertyName 'maxConcurrentRuns')

    return @(
        '# HEARTBEAT.md'
        ''
        '## Runtime Contract'
        ('- Interval: {0}s' -f $interval)
        ('- Cooldown: {0}s' -f $cooldown)
        ('- Wake On Demand: {0}' -f $wakeOnDemand)
        ('- Max Concurrent Runs: {0}' -f $maxConcurrentRuns)
        ''
        '## Expectations'
        '- Each heartbeat should advance assigned work, update state, or produce a clear blocker signal.'
        '- Keep work incremental and checkpoint-friendly so a follow-up heartbeat can continue safely.'
        '- When blocked by platform or credential issues, record the exact failure and switch to the next safe path.'
    ) -join "`n"
}

function New-VorceStudiosToolsContent {
    param(
        [Parameter(Mandatory)][object]$Plugins
    )

    $pluginKeys = @(
        @($Plugins) |
            Where-Object { [string]$_.status -eq 'ready' } |
            ForEach-Object { [string]$_.pluginKey }
    )

    return @(
        '# TOOLS.md'
        ''
        '## Control Plane'
        ('- Paperclip API: {0}' -f (Get-VorceStudiosApiBase))
        '- Local repository access is available in the current working tree.'
        '- Managed instruction bundle files in this directory are part of the runtime contract.'
        ''
        '## Installed Plugins'
        (ConvertTo-VorceStudiosMarkdownList -Items $pluginKeys)
        ''
        '## Usage Rules'
        '- Prefer the Paperclip API for company, issue, approval, skill, and plugin state changes.'
        '- Use plugin capabilities only when the plugin is loaded and configured.'
        '- Keep external side effects explicit and observable from Paperclip state when possible.'
    ) -join "`n"
}

function New-VorceStudiosGoalsContent {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][object]$Agent
    )

    $agentId = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'id')
    $agentName = [string](Get-VorceStudiosObjectPropertyValue -Object $Agent -PropertyName 'name')
    $goals = @(Get-VorceStudiosGoals -CompanyId $CompanyId)
    $issues = @(
        Get-VorceStudiosIssues -CompanyId $CompanyId |
            Where-Object {
                ([string]$_.assigneeAgentId -eq $agentId) -and
                @('todo', 'in_progress', 'blocked') -contains [string]$_.status
            }
    )

    $goalLines = if ($goals.Count -eq 0) {
        @('- No company goals are currently stored in Paperclip.')
    } else {
        @(
            $goals | ForEach-Object {
                $status = if ([string]::IsNullOrWhiteSpace([string]$_.status)) { 'unknown' } else { [string]$_.status }
                '- [{0}] {1}' -f $status, [string]$_.title
            }
        )
    }

    $issueLines = if ($issues.Count -eq 0) {
        @('- No assigned issues are currently open for this agent.')
    } else {
        @(
            $issues | ForEach-Object {
                $identifier = if ([string]::IsNullOrWhiteSpace([string]$_.identifier)) { [string]$_.id } else { [string]$_.identifier }
                '- [{0}] {1}: {2}' -f [string]$_.status, $identifier, [string]$_.title
            }
        )
    }

    $idleGuidanceLine = if (($goals.Count -eq 0) -and ($issues.Count -eq 0)) {
        '- If there are no assigned issues and no company goals, record an idle/no-op heartbeat and stop instead of exploring speculative work.'
    } else {
        '- If no issue is assigned, align with the highest-priority company goal without inventing side quests.'
    }

    return @(
        '# GOALS.md'
        ''
        ('Generated: {0}' -f (Get-VorceStudiosTimestamp))
        ('Agent: {0}' -f $agentName)
        ''
        '## Company Goals'
        ($goalLines -join "`n")
        ''
        '## Assigned Work'
        ($issueLines -join "`n")
        ''
        '## Guidance'
        '- Prioritize explicitly assigned work first.'
        $idleGuidanceLine
    ) -join "`n"
}

function New-VorceStudiosSkillsContent {
    param(
        [Parameter(Mandatory)][object]$SkillSnapshot
    )

    $warnings = @($SkillSnapshot.warnings)
    $entries = @($SkillSnapshot.entries)
    $desired = @($SkillSnapshot.desiredSkills)

    $desiredLines = if ($desired.Count -eq 0) {
        @('- No desired skills are configured.')
    } else {
        foreach ($skillKey in $desired) {
            $entry = $entries | Where-Object { [string]$_.key -eq [string]$skillKey } | Select-Object -First 1
            if ($null -eq $entry) {
                '- {0} (not currently visible in runtime snapshot)' -f [string]$skillKey
                continue
            }

            $state = [string]$entry.state
            $origin = [string]$entry.originLabel
            '- {0} [{1}] ({2})' -f [string]$entry.key, $state, $origin
        }
    }

    $otherVisible = @(
        $entries |
            Where-Object { -not $_.desired } |
            Select-Object -First 12
    )

    $otherLines = if ($otherVisible.Count -eq 0) {
        @('- No additional runtime skills detected.')
    } else {
        @(
            $otherVisible | ForEach-Object {
                $runtimeName = [string]$_.runtimeName
                if ([string]::IsNullOrWhiteSpace($runtimeName)) {
                    $runtimeName = [string]$_.key
                }
                '- {0} [{1}]' -f $runtimeName, [string]$_.state
            }
        )
    }

    $warningLines = if ($warnings.Count -eq 0) {
        @('- none')
    } else {
        @($warnings | ForEach-Object { '- {0}' -f [string]$_ })
    }

    return @(
        '# SKILLS.md'
        ''
        '## Desired Skills'
        ($desiredLines -join "`n")
        ''
        '## Other Visible Runtime Skills'
        ($otherLines -join "`n")
        ''
        '## Warnings'
        ($warningLines -join "`n")
    ) -join "`n"
}

function Ensure-VorceStudiosRunLogDirectories {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $paths = Get-VorceStudiosPaths
    $system = Get-VorceStudiosSystemPolicy
    $base = Join-Path $paths.PaperclipHome ("instances\{0}\data\run-logs\{1}" -f $system.Company.InstanceId, $CompanyId)
    Ensure-VorceStudiosDirectory -Path $base

    $agentIds = @(
        Get-VorceStudiosAgents -CompanyId $CompanyId |
            ForEach-Object { [string]$_.id } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($agentId in $agentIds) {
        Ensure-VorceStudiosDirectory -Path (Join-Path $base $agentId)
    }

    return @{
        base = $base
        agentCount = $agentIds.Count
    }
}

function Sync-VorceStudiosLocalAgentInstructionBundles {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $plugins = @(Get-VorceStudiosPlugins)
    $agents = @(
        Get-VorceStudiosAgents -CompanyId $CompanyId |
            Where-Object { ($LocalAdapterTypes -contains [string]$_.adapterType) -or ([string]$_.adapterType -eq 'process') }
    )

    $updatedAgents = New-Object System.Collections.Generic.List[string]
    $updatedFiles = New-Object System.Collections.Generic.List[string]

    foreach ($agent in $agents) {
        $agentId = [string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'id')
        $agentName = [string](Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'name')
        $root = Get-VorceStudiosManagedInstructionRoot -CompanyId $CompanyId -AgentId $agentId
        Ensure-VorceStudiosDirectory -Path $root

        $templatePath = Get-VorceStudiosInstructionTemplatePath -Agent $agent
        $baseContent = if ($null -ne $templatePath) { Get-Content -LiteralPath $templatePath -Raw } else { New-VorceStudiosGenericInstructionContent -Agent $agent }
        $skillSnapshot = Get-VorceStudiosAgentSkills -AgentId $agentId
        $files = [ordered]@{
            'AGENTS.md' = New-VorceStudiosManagedAgentsContent -BaseContent $baseContent
            'SOUL.md' = New-VorceStudiosSoulContent -Agent $agent
            'HEARTBEAT.md' = New-VorceStudiosHeartbeatContent -Agent $agent
            'TOOLS.md' = New-VorceStudiosToolsContent -Plugins $plugins
            'GOALS.md' = New-VorceStudiosGoalsContent -CompanyId $CompanyId -Agent $agent
            'SKILLS.md' = New-VorceStudiosSkillsContent -SkillSnapshot $skillSnapshot
        }

        foreach ($entry in $files.GetEnumerator()) {
            $target = Join-Path $root $entry.Key
            $existing = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
            if ($existing -ne [string]$entry.Value) {
                [System.IO.File]::WriteAllText($target, [string]$entry.Value, (New-Object System.Text.UTF8Encoding($false)))
                $updatedFiles.Add($target)
            }
        }

        $adapterConfig = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'adapterConfig')
        $managedConfig = Get-VorceStudiosManagedInstructionAdapterConfig -CompanyId $CompanyId -AgentId $agentId
        $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $adapterConfig -Overlay $managedConfig

        if (-not (Test-VorceStudiosJsonEquivalent -Left $adapterConfig -Right $nextAdapterConfig)) {
            Update-VorceStudiosAgent -AgentId $agentId -Payload @{
                adapterConfig = $nextAdapterConfig
            } | Out-Null
            $updatedAgents.Add($agentName)
        }
    }

    return @{
        totalAgents = $agents.Count
        updatedAgents = $updatedAgents.ToArray()
        updatedFileCount = $updatedFiles.Count
        updatedFiles = $updatedFiles.ToArray()
    }
}

function Sync-VorceStudiosHeartbeatPolicy {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $system = Get-VorceStudiosSystemPolicy
    $intervals = ConvertTo-VorceStudiosHashtable -InputObject $system.Supervisor.AgentIntervals
    $updated = New-Object System.Collections.Generic.List[string]

    foreach ($agent in @(Get-VorceStudiosAgents -CompanyId $CompanyId)) {
        $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata') -PropertyName 'roleKey')
        $policyKey = [string](Get-VorceStudiosObjectPropertyValue -Object $HeartbeatPolicyByRoleKey -PropertyName $roleKey)
        if ([string]::IsNullOrWhiteSpace($policyKey)) {
            continue
        }

        $intervalSec = [int](Get-VorceStudiosObjectPropertyValue -Object $intervals -PropertyName $policyKey)
        if ($intervalSec -le 0) {
            continue
        }

        $runtimeConfig = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'runtimeConfig')
        $heartbeat = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $runtimeConfig -PropertyName 'heartbeat')
        $nextHeartbeat = Merge-VorceStudiosHashtable -Base $heartbeat -Overlay @{
            enabled = $true
            cooldownSec = 30
            intervalSec = $intervalSec
            wakeOnDemand = $true
            maxConcurrentRuns = 1
        }
        $nextRuntimeConfig = Merge-VorceStudiosHashtable -Base $runtimeConfig -Overlay @{
            heartbeat = $nextHeartbeat
        }

        if (-not (Test-VorceStudiosJsonEquivalent -Left $runtimeConfig -Right $nextRuntimeConfig)) {
            Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
                runtimeConfig = $nextRuntimeConfig
            } | Out-Null
            $updated.Add([string]$agent.name)
        }
    }

    return @{
        updatedAgents = $updated.ToArray()
        updatedCount = $updated.Count
    }
}

function Ensure-VorceStudiosAutonomousAgentAdapters {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $paths = Get-VorceStudiosPaths
    $updated = New-Object System.Collections.Generic.List[string]
    $resetSessions = New-Object System.Collections.Generic.List[string]
    $availability = Get-VorceStudiosLocalToolAvailability

    foreach ($agent in @(Get-VorceStudiosAgents -CompanyId $CompanyId)) {
        $metadata = Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'metadata'
        $roleKey = [string](Get-VorceStudiosObjectPropertyValue -Object $metadata -PropertyName 'roleKey')
        $target = Get-VorceStudiosAutonomousAdapterTarget -RoleKey $roleKey -Availability $availability
        if ($null -eq $target) {
            continue
        }

        $adapterConfig = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $agent -PropertyName 'adapterConfig')
        $targetAdapterType = [string](Get-VorceStudiosObjectPropertyValue -Object $target -PropertyName 'adapterType')
        $cwd = [string](Get-VorceStudiosObjectPropertyValue -Object $adapterConfig -PropertyName 'cwd')
        if ([string]::IsNullOrWhiteSpace($cwd)) {
            $cwd = $paths.Root
        }

        $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $adapterConfig -Overlay (Get-VorceStudiosObjectPropertyValue -Object $target -PropertyName 'adapterConfig')
        $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $nextAdapterConfig -Overlay @{
            cwd = $cwd
        }
        if ($targetAdapterType -ne 'process') {
            $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $nextAdapterConfig -Overlay @{
                command = $null
                args = $null
                commandArgs = $null
            }
        }
        $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $nextAdapterConfig -Overlay (Get-VorceStudiosManagedInstructionAdapterConfig -CompanyId $CompanyId -AgentId ([string]$agent.id))
        if ($targetAdapterType -eq 'process') {
            $processEnv = Get-VorceStudiosManagedInstructionProcessEnv -CompanyId $CompanyId -Agent $agent
            $nextAdapterConfig = Merge-VorceStudiosHashtable -Base $nextAdapterConfig -Overlay @{
                env = Merge-VorceStudiosHashtable -Base (Get-VorceStudiosObjectPropertyValue -Object $nextAdapterConfig -PropertyName 'env') -Overlay $processEnv
            }
        }

        $adapterTypeChanged = ([string]$agent.adapterType -ne $targetAdapterType)
        if ($adapterTypeChanged -or -not (Test-VorceStudiosJsonEquivalent -Left $adapterConfig -Right $nextAdapterConfig)) {
            Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
                adapterType = $targetAdapterType
                adapterConfig = $nextAdapterConfig
            } | Out-Null
            $updated.Add([string]$agent.name)
            if ($adapterTypeChanged) {
                Reset-VorceStudiosAgentRuntimeSession -AgentId ([string]$agent.id) | Out-Null
                $resetSessions.Add([string]$agent.name)
            }
        }
    }

    return @{
        updatedAgents = $updated.ToArray()
        updatedCount = $updated.Count
        resetSessions = $resetSessions.ToArray()
        resetSessionCount = $resetSessions.Count
        availability = $availability
    }
}

function Get-VorceStudiosQwenFallbackAdapterConfig {
    param(
        [Parameter(Mandatory)][string]$CompanyId,
        [Parameter(Mandatory)][object]$Agent
    )

    $target = New-VorceStudiosQwenProcessTarget -TimeoutSec 600
    $adapterConfig = ConvertTo-VorceStudiosHashtable -InputObject (Get-VorceStudiosObjectPropertyValue -Object $target -PropertyName 'adapterConfig')
    $processEnv = Get-VorceStudiosManagedInstructionProcessEnv -CompanyId $CompanyId -Agent $Agent
    return Merge-VorceStudiosHashtable -Base $adapterConfig -Overlay @{
        env = Merge-VorceStudiosHashtable -Base (Get-VorceStudiosObjectPropertyValue -Object $adapterConfig -PropertyName 'env') -Overlay $processEnv
    }
}

function Test-VorceStudiosCodexFallbackError {
    param(
        [AllowNull()][object]$Log
    )

    if ($null -eq $Log) {
        return $false
    }

    $serialized = $Log | ConvertTo-Json -Depth 20
    return ($serialized -match 'usage limit') -or ($serialized -match 'not supported when using Codex with a ChatGPT account')
}

function Ensure-VorceStudiosCodexFallbackAdapters {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $updated = New-Object System.Collections.Generic.List[string]
    $availability = Get-VorceStudiosLocalToolAvailability
    $codexAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $availability -PropertyName 'codex') -PropertyName 'available')
    $qwenAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $availability -PropertyName 'qwen') -PropertyName 'available')
    $geminiAvailable = [bool](Get-VorceStudiosObjectPropertyValue -Object (Get-VorceStudiosObjectPropertyValue -Object $availability -PropertyName 'gemini') -PropertyName 'available')

    if ($codexAvailable) {
        return @{
            updatedAgents = @()
            updatedCount = 0
        }
    }

    foreach ($agent in @(Get-VorceStudiosAgents -CompanyId $CompanyId | Where-Object { [string]$_.adapterType -eq 'codex_local' })) {
        $runs = @(Get-VorceStudiosHeartbeatRuns -CompanyId $CompanyId -AgentId ([string]$agent.id) -Limit 3)
        $latestRun = @(
            $runs |
                Where-Object { @('failed', 'error') -contains [string]$_.status } |
                Select-Object -First 1
        )[0]
        if ($null -eq $latestRun) {
            continue
        }

        $log = Get-VorceStudiosHeartbeatRunLog -RunId ([string]$latestRun.id)
        if (-not (Test-VorceStudiosCodexFallbackError -Log $log)) {
            continue
        }

        if ($qwenAvailable) {
            Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
                adapterType = 'process'
                adapterConfig = Get-VorceStudiosQwenFallbackAdapterConfig -CompanyId $CompanyId -Agent $agent
            } | Out-Null
        } elseif ($geminiAvailable) {
            Update-VorceStudiosAgent -AgentId ([string]$agent.id) -Payload @{
                adapterType = 'gemini_local'
                adapterConfig = Get-VorceStudiosObjectPropertyValue -Object (New-VorceStudiosGeminiLocalTarget -TimeoutSec 600) -PropertyName 'adapterConfig'
            } | Out-Null
        } else {
            continue
        }
        Reset-VorceStudiosAgentRuntimeSession -AgentId ([string]$agent.id) | Out-Null
        $updated.Add([string]$agent.name)
    }

    return @{
        updatedAgents = $updated.ToArray()
        updatedCount = $updated.Count
    }
}

function Ensure-VorceStudiosHelpfulLeadershipSkills {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $existing = @(
        Get-VorceStudiosCompanySkills -CompanyId $CompanyId |
            ForEach-Object { [string]$_.key }
    )

    $imported = New-Object System.Collections.Generic.List[string]
    foreach ($source in $LeadershipSkillSources) {
        if ($existing -contains $source) {
            continue
        }

        try {
            Import-VorceStudiosCompanySkill -CompanyId $CompanyId -Source $source | Out-Null
            $imported.Add($source)
        } catch {
        }
    }

    return @{
        imported = $imported.ToArray()
        importedCount = $imported.Count
    }
}

function Ensure-VorceStudiosLeadershipSkills {
    param(
        [Parameter(Mandatory)][string]$CompanyId
    )

    $leadershipAgents = @(
        Get-VorceStudiosAgents -CompanyId $CompanyId |
            Where-Object { ([string]$_.urlKey -eq 'victor') -or ([string]$_.role -eq 'ceo') -or ([string]$_.name -eq 'Victor') }
    )

    if ($leadershipAgents.Count -eq 0) {
        return @{
            updated = $false
            agents = @()
            desiredSkills = @()
        }
    }

    $companySkills = @(Get-VorceStudiosCompanySkills -CompanyId $CompanyId)
    $availableKeys = @($companySkills | ForEach-Object { [string]$_.key })
    $desiredSkills = @($LeadershipSkillSources | Where-Object { $availableKeys -contains $_ })
    $snapshots = @(
        foreach ($leader in $leadershipAgents) {
            @{
                agent = [string]$leader.name
                snapshot = Sync-VorceStudiosAgentSkills -AgentId ([string]$leader.id) -DesiredSkills $desiredSkills
            }
        }
    )

    return @{
        updated = $true
        agents = @($leadershipAgents | ForEach-Object { [string]$_.name })
        desiredSkills = $desiredSkills
        snapshots = $snapshots
    }
}

function Ensure-VorceStudiosPlugins {
    $results = foreach ($vendor in Get-VorceStudiosPluginVendors) {
        try {
            $install = Ensure-VorceStudiosVendorPluginInstalled -Name ([string]$vendor.name) -Enable
            [ordered]@{
                name = [string]$vendor.name
                ok = $true
                error = $null
                source = $install.source
                prepare = $install.prepare
                upgrade = $install.upgrade
                plugin = $install.plugin
            }
        } catch {
            [ordered]@{
                name = [string]$vendor.name
                ok = $false
                error = $_.Exception.Message
                source = $null
                prepare = $null
                upgrade = $null
                plugin = $null
            }
        }
    }

    return @{
        requested = @((Get-VorceStudiosPluginVendors | ForEach-Object { [string]$_.name }))
        installed = @($results)
        plugins = @(Get-VorceStudiosPlugins)
    }
}

Import-VorceStudiosPaperclipEnvironment

if (-not (Test-VorceStudiosPaperclipReady)) {
    throw 'Paperclip API ist nicht bereit.'
}

$system = Get-VorceStudiosSystemPolicy
$company = Find-VorceStudiosCompany -Name $system.Company.Name
if ($null -eq $company) {
    throw "Paperclip-Firma '$($system.Company.Name)' wurde nicht gefunden."
}

$result = [ordered]@{
    companyId = [string]$company.id
    runLogs = $null
    adapterRepairs = $null
    codexFallbacks = $null
    plugins = $null
    heartbeatPolicy = $null
    instructions = $null
    victorSkills = $null
    scheduler = $null
}

$result.runLogs = Ensure-VorceStudiosRunLogDirectories -CompanyId ([string]$company.id)
$result.adapterRepairs = Ensure-VorceStudiosAutonomousAgentAdapters -CompanyId ([string]$company.id)
$result.codexFallbacks = Ensure-VorceStudiosCodexFallbackAdapters -CompanyId ([string]$company.id)

if (-not $SkipPlugins.IsPresent) {
    $result.plugins = Ensure-VorceStudiosPlugins
}

if (-not $SkipHeartbeats.IsPresent) {
    $result.heartbeatPolicy = Sync-VorceStudiosHeartbeatPolicy -CompanyId ([string]$company.id)
}

if (-not $SkipInstructions.IsPresent) {
    $result.instructions = Sync-VorceStudiosLocalAgentInstructionBundles -CompanyId ([string]$company.id)
}

if (-not $SkipVictorSkills.IsPresent) {
    Ensure-VorceStudiosHelpfulLeadershipSkills -CompanyId ([string]$company.id) | Out-Null
    $result.victorSkills = Ensure-VorceStudiosLeadershipSkills -CompanyId ([string]$company.id)
}

$result.scheduler = Get-VorceStudiosSchedulerHeartbeats
$result
