[CmdletBinding()]
param()

function New-VorceTestContext {
    param(
        [string]$Name = 'VorceTest'
    )

    [pscustomobject]@{
        Name      = $Name
        PassCount = 0
        FailCount = 0
        TotalCount = 0
    }
}

function Write-VorceTestResult {
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [bool]$Passed
    )

    $status = if ($Passed) { '[PASS]' } else { '[FAIL]' }
    Write-Host "$status $Message"

    $Context.TotalCount++
    if ($Passed) {
        $Context.PassCount++
    } else {
        $Context.FailCount++
    }
}

function Assert-VorceTestThrows {
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$ExpectedMessagePattern
    )

    try {
        & $ScriptBlock
        Write-VorceTestResult -Context $Context -Message $Message -Passed $false
        return $false
    } catch {
        if ($ExpectedMessagePattern) {
            $matchesPattern = $_.Exception.Message -match $ExpectedMessagePattern
            Write-VorceTestResult -Context $Context -Message $Message -Passed $matchesPattern
            return $matchesPattern
        }

        Write-VorceTestResult -Context $Context -Message $Message -Passed $true
        return $true
    }
}

function Complete-VorceTest {
    param(
        [Parameter(Mandatory)]
        [psobject]$Context
    )

    Write-Host ""
    Write-Host "Ergebnis: $($Context.PassCount)/$($Context.TotalCount) Checks bestanden"
    Write-Host "Bestanden: $($Context.PassCount)"
    Write-Host "Fehlgeschlagen: $($Context.FailCount)"

    if ($Context.FailCount -gt 0) {
        exit 1
    }

    exit 0
}
