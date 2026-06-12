# Vorce-Autopilot/src/lib/database-manager.ps1
# Manages the historical quota database using a JSON-based array

Set-StrictMode -Version Latest

# Dot-source state-manager to get Read-JsonLocked/Write-JsonLocked
. (Join-Path $PSScriptRoot "state-manager.ps1")

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:VarDbDir = Join-Path $script:ScriptRoot "var/db"
$DbPath = Join-Path $script:VarDbDir "historical-quota-db.json"

# Ensure var/db exists
if (-not (Test-Path -Path $script:VarDbDir)) {
    New-Item -ItemType Directory -Path $script:VarDbDir -Force | Out-Null
}

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
    $data = Read-JsonLocked -Path $DbPath
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
    Write-JsonLocked -Path $DbPath -Data $Data | Out-Null
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

    Update-JsonLocked -Path $DbPath -DefaultValue @() -Updater {
        param($currentData)

        [array]$db = @($currentData | Where-Object { $null -ne $_ })

        # Check if entry already exists for this date, provider, and model
        $existingEntry = $null
        for ($i = 0; $i -lt $db.Count; $i++) {
            if (
                (Test-ObjectProperty -Object $db[$i] -Name "date") -and
                (Test-ObjectProperty -Object $db[$i] -Name "provider_name") -and
                (Test-ObjectProperty -Object $db[$i] -Name "model_name") -and
                $db[$i].date -eq $Date -and
                $db[$i].provider_name -eq $ProviderName -and
                $db[$i].model_name -eq $ModelName
            ) {
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

        return @($db)
    } | Out-Null
}

function Clear-DailyUsageForProvider {
    <#
    .SYNOPSIS
    Removes all rows for a provider on a date before writing a fresh telemetry snapshot.
    #>
    param(
        [Parameter(Mandatory)][string]$Date,
        [Parameter(Mandatory)][string]$ProviderName
    )

    Update-JsonLocked -Path $DbPath -DefaultValue @() -Updater {
        param($currentData)

        [array]$db = @($currentData | Where-Object { $null -ne $_ })
        $filtered = @($db | Where-Object {
            -not (
                (Test-ObjectProperty -Object $_ -Name "date") -and
                (Test-ObjectProperty -Object $_ -Name "provider_name") -and
                $_.date -eq $Date -and
                $_.provider_name -eq $ProviderName
            )
        })
        return @($filtered)
    } | Out-Null
}
