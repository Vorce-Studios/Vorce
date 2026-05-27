# scripts/codex-cli/lib/memory-store.ps1
# Selective Memory Injection System
# Stores permanent rules and temporary context, injecting them into prompts.

Set-StrictMode -Version Latest

$script:MemoryFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "autopilot-memories.json"

function Read-MemoryStore {
    <#
    .SYNOPSIS
    Reads the memory store from autopilot-memories.json.
    Returns the parsed object, or a default empty store if missing.
    #>

    if (-not (Test-Path $script:MemoryFilePath)) {
        return [ordered]@{
            schema_version = 1
            memories       = @()
        }
    }

    try {
        $content = Get-Content $script:MemoryFilePath -Raw -Encoding UTF8
        return ($content | ConvertFrom-Json)
    } catch {
        Write-Warning "[MEMORY] Konnte Memory-Store nicht lesen: $_"
        return [ordered]@{
            schema_version = 1
            memories       = @()
        }
    }
}

function Save-MemoryStore {
    <#
    .SYNOPSIS
    Atomically saves the memory store to autopilot-memories.json.
    #>
    param([Parameter(Mandatory)][object]$Store)

    try {
        if (Get-Command Write-SafeJson -ErrorAction SilentlyContinue) {
            Write-SafeJson -FilePath $script:MemoryFilePath -Data $Store
        } else {
            $Store | ConvertTo-Json -Depth 5 | Set-Content $script:MemoryFilePath -Encoding UTF8
        }
    } catch {
        Write-Warning "[MEMORY] Konnte Memory-Store nicht speichern: $_"
    }
}

function Get-RelevantMemories {
    <#
    .SYNOPSIS
    Returns all memories in the store, sorted by type (temporary first) and priority.
    #>
    param(
        [Parameter(Mandatory=$false)][string]$TaskType, # Kept for backward compatibility
        [object]$Store
    )

    if (-not $Store) {
        $Store = Read-MemoryStore
    }

    $memories = @($Store.memories)
    if ($memories.Count -eq 0) { return @() }

    # Sort order: temporary first, then permanent
    $typeOrder = @{ "temporary" = 0; "permanent" = 1 }

    # Sort order for priority: critical = 0, high = 1, medium = 2, low = 3
    $priorityOrder = @{ "critical" = 0; "high" = 1; "medium" = 2; "low" = 3 }

    $sorted = @($memories | Sort-Object {
        $t = [string]$_.type
        $p = [string]$_.priority

        $typeWeight = if ($typeOrder.ContainsKey($t)) { $typeOrder[$t] } else { 99 }
        $priorityWeight = if ($priorityOrder.ContainsKey($p)) { $priorityOrder[$p] } else { 99 }

        # Sort key logic: type weight first, then priority weight
        # Format as padded string to sort correctly
        "{0:D2}_{1:D2}" -f $typeWeight, $priorityWeight
    })

    return $sorted
}

function Format-MemoryBlock {
    <#
    .SYNOPSIS
    Creates a compact memory injection block.
    Returns an empty string if no memories exist.
    This block is prepended to prompts to give the agent context.
    #>
    param(
        [Parameter(Mandatory=$false)][string]$TaskType, # Kept for backward compatibility
        [object]$Store
    )

    $memories = Get-RelevantMemories -Store $Store
    if ($memories.Count -eq 0) { return "" }

    $lines = @("[KONTEXT-ERINNERUNGEN]")
    foreach ($m in $memories) {
        $typeLabel = if ($m.type -eq "temporary") { "[TEMPORAER]" } else { "[RICHTLINIE]" }
        $lines += "- $typeLabel $($m.text)"
    }
    $lines += "---"
    $lines += ""

    $block = $lines -join "`n"

    $tokenEstimate = [Math]::Ceiling($block.Length / 4)
    Write-Host "[MEMORY] $($memories.Count) Erinnerungen (permanent & temporaer) injiziert (~${tokenEstimate} Tokens)" -ForegroundColor DarkGray

    return $block
}

function Add-Memory {
    <#
    .SYNOPSIS
    Adds a new memory to the store. Max 30 memories enforced.
    #>
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Type, # "permanent" or "temporary"
        [string]$Priority = "medium",
        [string]$Source = "autopilot"
    )

    $store = Read-MemoryStore

    # Enforce max 30 memories
    if ($store.memories.Count -ge 30) {
        Write-Warning "[MEMORY] Maximum von 30 Erinnerungen erreicht. Loeschen Sie alte Eintraege zuerst."
        return $false
    }

    # Validate type
    if ($Type -ne "permanent" -and $Type -ne "temporary") {
        Write-Warning "[MEMORY] Ungueltiger Memory-Typ '$Type'. Verwende 'temporary'."
        $Type = "temporary"
    }

    $id = "mem-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 4))"

    $entry = [ordered]@{
        id         = $id
        text       = $Text
        type       = $Type
        priority   = $Priority
        created_at = (Get-Date -Format 'o')
        source     = $Source
    }

    $store.memories += @($entry)
    Save-MemoryStore -Store $store

    Write-Host "[MEMORY] Erinnerung '$id' hinzugefuegt ($Type)." -ForegroundColor Green
    return $true
}

function Remove-Memory {
    <#
    .SYNOPSIS
    Removes a memory by its ID.
    #>
    param([Parameter(Mandatory)][string]$Id)

    $store = Read-MemoryStore
    $before = $store.memories.Count
    $store.memories = @($store.memories | Where-Object { $_.id -ne $Id })
    $after = $store.memories.Count

    if ($before -eq $after) {
        Write-Warning "[MEMORY] Erinnerung '$Id' nicht gefunden."
        return $false
    }

    Save-MemoryStore -Store $store
    Write-Host "[MEMORY] Erinnerung '$Id' entfernt." -ForegroundColor Green
    return $true
}
