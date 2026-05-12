# scripts/codex-cli/lib/database-manager.ps1
# Manages the historical quota database using a JSON-based array

Set-StrictMode -Version Latest

$ScriptDir = Join-Path $PSScriptRoot ".."
$DbPath = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "historical-quota-db.json"))

function Initialize-Database {
    <#
    .SYNOPSIS
    Creates the JSON database file if it doesn't exist.
    #>
    if (-not (Test-Path $DbPath)) {
        "[]" | Set-Content -Path $DbPath -Encoding UTF8
        Write-Host "[DB] Created empty database at $DbPath" -ForegroundColor Green
    }
}

function Read-Database {
    <#
    .SYNOPSIS
    Reads the historical database into an array of objects.
    #>
    Initialize-Database
    $content = Get-Content -Path $DbPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($content)) { return @() }
    
    $data = $content | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $data) { return @() }
    
    # Ensure it's an array
    if ($data -isnot [array]) {
        return @($data)
    }
    return $data
}

function Write-Database {
    <#
    .SYNOPSIS
    Writes an array of objects back to the JSON database.
    #>
    param(
        [Parameter(Mandatory)][array]$Data
    )
    ConvertTo-Json -InputObject $Data -Depth 5 | Set-Content -Path $DbPath -Encoding UTF8
}

function Save-DailyUsage {
    <#
    .SYNOPSIS
    Saves or updates the daily usage for a specific provider and model.
    #>
    param(
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][string]$ProviderName,
        [string]$ModelName = "unknown",
        [Parameter(Mandatory)][int]$Calls,
        [Parameter(Mandatory)][double]$CostUsd,
        [Parameter(Mandatory)][int]$InputTokens,
        [Parameter(Mandatory)][int]$OutputTokens,
        [Parameter(Mandatory)][int]$CachedTokens,
        [Parameter(Mandatory)][int]$ReasoningTokens,
        [Parameter(Mandatory)][int]$ToolTokens,
        [Parameter(Mandatory)][int]$DurationMs
    )

    [array]$db = Read-Database

    # Check if entry already exists for this date, provider, and model
    $existingEntry = $null
    for ($i = 0; $i -lt $db.Count; $i++) {
        if ($db[$i].date -eq $Date -and $db[$i].provider_name -eq $ProviderName -and $db[$i].model_name -eq $ModelName) {
            $existingEntry = $db[$i]
            break
        }
    }

    if ($null -ne $existingEntry) {
        # Update existing
        $existingEntry.calls = $Calls
        $existingEntry.cost_usd = $CostUsd
        $existingEntry.input_tokens = $InputTokens
        $existingEntry.output_tokens = $OutputTokens
        $existingEntry.cached_tokens = $CachedTokens
        $existingEntry.reasoning_tokens = $ReasoningTokens
        $existingEntry.tool_tokens = $ToolTokens
        $existingEntry.total_duration_ms = $DurationMs
        Write-Host "[DB] Updated usage for $ProviderName ($ModelName) on $Date" -ForegroundColor DarkGray
    } else {
        # Add new
        $newEntry = [ordered]@{
            date              = $Date
            provider_name     = $ProviderName
            model_name        = $ModelName
            calls             = $Calls
            cost_usd          = $CostUsd
            input_tokens      = $InputTokens
            output_tokens     = $OutputTokens
            cached_tokens     = $CachedTokens
            reasoning_tokens  = $ReasoningTokens
            tool_tokens       = $ToolTokens
            total_duration_ms = $DurationMs
        }
        $db += $newEntry
        Write-Host "[DB] Inserted new usage for $ProviderName ($ModelName) on $Date" -ForegroundColor DarkGray
    }

    Write-Database -Data $db
}
