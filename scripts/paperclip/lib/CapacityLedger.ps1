Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')

function Get-VorceStudiosCapacityLedgerSeed {
    $seed = Import-PowerShellDataFile -Path (Join-Path (Get-VorceStudiosPaths).TemplatesDir 'capacity-ledger.seed.psd1')
    return ConvertTo-VorceStudiosHashtable -InputObject $seed
}

function Get-VorceStudiosCapacityLedger {
    $paths = Get-VorceStudiosPaths
    $ledger = Read-VorceStudiosJsonFile -Path $paths.CapacityLedgerPath -Default $null
    if ($null -ne $ledger) {
        return $ledger
    }

    $seed = Get-VorceStudiosCapacityLedgerSeed
    $seed['generatedAt'] = Get-VorceStudiosTimestamp
    Write-VorceStudiosJsonFile -Path $paths.CapacityLedgerPath -Value $seed
    return $seed
}

function Set-VorceStudiosCapacityLedger {
    param(
        [Parameter(Mandatory)][hashtable]$Ledger
    )

    $Ledger['generatedAt'] = Get-VorceStudiosTimestamp
    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CapacityLedgerPath -Value $Ledger
}

function Test-VorceStudiosCommandAvailable {
    param(
        [Parameter(Mandatory)][string]$CommandName
    )

    return ($null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue))
}

function Set-VorceStudiosToolState {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][ValidateSet('available', 'degraded', 'quota_exhausted', 'offline', 'manual_only', 'optional')][string]$Status,
        [string]$Notes = ''
    )

    $ledger = Get-VorceStudiosCapacityLedger
    if (-not $ledger.tools.ContainsKey($Tool)) {
        $ledger.tools[$Tool] = @{}
    }

    $ledger.tools[$Tool]['status'] = $Status
    $ledger.tools[$Tool]['lastCheckedAt'] = Get-VorceStudiosTimestamp
    if (-not [string]::IsNullOrWhiteSpace($Notes)) {
        $ledger.tools[$Tool]['notes'] = $Notes
    }

    Set-VorceStudiosCapacityLedger -Ledger $ledger
    return $ledger.tools[$Tool]
}

function Test-VorceStudiosQuotaFailureText {
    param(
        [AllowNull()][string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return ($Text -match '(quota|rate limit|limit reached|too many requests|429|daily limit|usage cap)')
}

function Update-VorceStudiosCapacityLedgerFromProbe {
    $ledger = Get-VorceStudiosCapacityLedger

    $toolChecks = @(
        @{ Name = 'gemini'; Command = 'gemini'; PresentState = 'available'; MissingState = 'offline' },
        @{ Name = 'qwen'; Command = 'qwen'; PresentState = 'available'; MissingState = 'offline' },
        @{ Name = 'codex'; Command = 'codex'; PresentState = 'available'; MissingState = 'offline' },
        @{ Name = 'copilot'; Command = 'copilot'; PresentState = 'degraded'; MissingState = 'offline' },
        @{ Name = 'antigravity'; Command = 'antigravity'; PresentState = 'manual_only'; MissingState = 'offline' }
    )

    foreach ($tool in $toolChecks) {
        $status = if (Test-VorceStudiosCommandAvailable -CommandName $tool.Command) { $tool.PresentState } else { $tool.MissingState }
        if (-not $ledger.tools.ContainsKey($tool.Name)) {
            $ledger.tools[$tool.Name] = @{}
        }
        $ledger.tools[$tool.Name]['status'] = $status
        $ledger.tools[$tool.Name]['lastCheckedAt'] = Get-VorceStudiosTimestamp
    }

    $julesAvailable = -not [string]::IsNullOrWhiteSpace($env:JULES_API_KEY)
    if (-not $ledger.tools.ContainsKey('jules')) {
        $ledger.tools['jules'] = @{}
    }
    $ledger.tools['jules']['status'] = if ($julesAvailable) { 'available' } else { 'offline' }
    $ledger.tools['jules']['lastCheckedAt'] = Get-VorceStudiosTimestamp

    $atlasState = Get-VorceStudiosAtlasState
    if (-not $ledger.tools.ContainsKey('atlas')) {
        $ledger.tools['atlas'] = @{}
    }
    $ledger.tools['atlas']['status'] = if ($atlasState.available) { 'available' } else { 'optional' }
    $ledger.tools['atlas']['lastCheckedAt'] = Get-VorceStudiosTimestamp

    Set-VorceStudiosCapacityLedger -Ledger $ledger
    return $ledger
}

function Get-VorceStudiosPreferredTool {
    param(
        [Parameter(Mandatory)][string[]]$Chain,
        [switch]$AllowManualOnly
    )

    $ledger = Get-VorceStudiosCapacityLedger
    foreach ($candidate in $Chain) {
        if (-not $ledger.tools.ContainsKey($candidate)) {
            continue
        }

        $status = [string]$ledger.tools[$candidate]['status']
        if (@('available', 'degraded') -contains $status) {
            return $candidate
        }
        if ($AllowManualOnly.IsPresent -and $status -eq 'manual_only') {
            return $candidate
        }
    }

    return $null
}
