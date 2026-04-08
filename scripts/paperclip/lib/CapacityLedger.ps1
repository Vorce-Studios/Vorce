Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')

function Get-VorceStudiosCapacityLedger {
    $ledger = Read-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CapacityLedgerPath -Default @{
        updatedAt = Get-VorceStudiosTimestamp
        capacity = @{}
    }
    if ($null -eq $ledger) {
        $ledger = @{ updatedAt = Get-VorceStudiosTimestamp; capacity = @{} }
    }
    if (-not $ledger.ContainsKey('capacity')) {
        $ledger['capacity'] = @{}
    }
    return $ledger
}

function Set-VorceStudiosCapacityLedger {
    param(
        [Parameter(Mandatory)][hashtable]$Ledger
    )

    $Ledger['updatedAt'] = Get-VorceStudiosTimestamp
    Write-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CapacityLedgerPath -Value $Ledger
}

function Update-VorceStudiosCapacityLedgerFromProbe {
    $ledger = Get-VorceStudiosCapacityLedger

    $ledger.capacity['jules'] = @{ dailySessions = 10; concurrentSessions = 2 }
    $ledger.capacity['antigravity'] = @{ dailySessions = 5; concurrentSessions = 1 }
    $ledger.capacity['codex'] = @{ dailyTokens = 500000 }
    $ledger.capacity['gemini'] = @{ dailyTokens = 1000000 }
    $ledger.capacity['qwen'] = @{ dailyTokens = 500000 }

    Set-VorceStudiosCapacityLedger -Ledger $ledger
    return $ledger
}

function Get-VorceStudiosPreferredTool {
    param(
        [Parameter(Mandatory)][string[]]$Chain
    )

    $ledger = Get-VorceStudiosCapacityLedger
    foreach ($tool in $Chain) {
        if ($ledger.capacity.ContainsKey($tool)) {
            return $tool
        }
    }

    return $Chain[0]
}
