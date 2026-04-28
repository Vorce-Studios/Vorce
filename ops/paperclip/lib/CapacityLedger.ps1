Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'PaperclipApi.ps1')

function Get-VorceStudiosCapacityLedger {
    return Read-VorceStudiosJsonFile -Path (Get-VorceStudiosPaths).CapacityLedgerPath -Default @{
        updatedAt = Get-VorceStudiosTimestamp
        capacity = @{}
    }
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

    # Static defaults for now, can be enriched by external probes
    $ledger.capacity['jules'] = @{ dailySessions = 10; concurrentSessions = 2 }
    $ledger.capacity['antigravity'] = @{ dailySessions = 5; concurrentSessions = 1 }
    $ledger.capacity['codex'] = @{ dailyTokens = 500000 }
    $ledger.capacity['gemini'] = @{ dailyTokens = 1000000 }

    Set-VorceStudiosCapacityLedger -Ledger $ledger
    return $ledger
}
