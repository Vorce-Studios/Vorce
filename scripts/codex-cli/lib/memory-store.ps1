# scripts/codex-cli/lib/memory-store.ps1
# On-Demand Memory System
# Stores permanent rules and temporary context.
# Only CRITICAL memories are auto-injected into prompts.
# All other memories are available via Search-Memories for on-demand retrieval.

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
    Creates a MINIMAL memory injection block for prompts.
    ON-DEMAND MODEL: Only CRITICAL-priority memories are auto-injected.
    All other memories are available via Search-Memories for explicit retrieval.
    Returns an empty string if no critical memories exist.
    #>
    param(
        [Parameter(Mandatory=$false)][string]$TaskType, # Kept for backward compatibility
        [string]$Prompt = "",
        [object]$Store
    )

    $allMemories = @(Get-RelevantMemories -TaskType $TaskType -Store $Store)
    if ($allMemories.Count -eq 0) { return "" }

    $taskKeywords = @{
        planning   = @("working", "token")
        monitoring = @("pr", "merge", "conflict", "session", "jules", "ci", "working")
        audit      = @("audit", "remediation", "escalation", "problem")
        coding     = @("bugfix", "script", "ci", "local", "cli", "test", "format")
    }
    $stopWords = @("github", "issue", "issues", "status", "context", "repo", "repository", "vorce", "autopilot", "scripte", "scripts", "daten", "entscheidung", "analysiere", "user", "alpha", "beta")
    $keywords = @()
    $keywords += @($Prompt -split '[^a-zA-Z0-9_-]+' | Where-Object { $_.Length -ge 4 -and $stopWords -notcontains $_.ToLowerInvariant() } | Select-Object -First 20)
    if ($taskKeywords.ContainsKey($TaskType)) { $keywords += $taskKeywords[$TaskType] }
    if ($Prompt -match '(?i)jules') { $keywords += @("jules") }
    if ($Prompt -match '(?i)(\bpr\b|pull|merge|konflikt|conflict|ci)') { $keywords += @("pr", "merge", "conflict", "ci") }
    if ($Prompt -match '(?i)(working|local|cli|tool)') { $keywords += @("working", "local", "cli") }
    $keywords = @($keywords | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    $scoredMemories = @($allMemories | ForEach-Object {
        $memory = $_
        $text = [string]$_.text
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        $score = 0
        foreach ($kw in $keywords) {
            if ($text -match [regex]::Escape($kw)) { $score++ }
        }
        if ($score -gt 0) {
            [pscustomobject]@{ memory = $memory; score = $score }
        }
    } | Sort-Object -Property @{Expression="score";Descending=$true})

    $relevant = @($scoredMemories | ForEach-Object { $_.memory })

    $critical = @($relevant | Where-Object { $_.priority -eq "critical" } | Select-Object -First 1)
    $high = @($relevant | Where-Object { $_.priority -eq "high" } | Select-Object -First 1)
    $selected = @($critical + $high)
    $otherCount = [Math]::Max(0, $allMemories.Count - $selected.Count)

    if ($selected.Count -eq 0) {
        Write-Host "[MEMORY] Keine session-spezifischen Erinnerungen injiziert, $($allMemories.Count) on-demand verfuegbar" -ForegroundColor DarkGray
        return ""
    }

    $lines = @("[KONTEXT-ERINNERUNGEN]")

    foreach ($m in $selected) {
        $typeLabel = if ($m.type -eq "temporary") { "[TEMPORAER]" } else { "[RICHTLINIE]" }
        $priorityLabel = [string]$m.priority
        $lines += "- $typeLabel [$priorityLabel] $($m.text)"
    }

    if ($otherCount -gt 0) {
        $lines += "- [INFO] $otherCount weitere Erinnerungen gespeichert (on-demand via Search-Memories abrufbar)."
    }

    $lines += "---"
    $lines += ""

    $block = $lines -join "`n"

    $tokenEstimate = [Math]::Ceiling($block.Length / 4)
    Write-Host "[MEMORY] $($selected.Count) session-spezifische Erinnerungen injiziert, $otherCount on-demand verfuegbar (~${tokenEstimate} Tokens)" -ForegroundColor DarkGray

    return $block
}

function Search-Memories {
    <#
    .SYNOPSIS
    Searches the memory store by keyword(s). Returns matching memories as a formatted block.
    Agents call this explicitly when they need specific context.
    .PARAMETER Query
    One or more keywords to search for (space-separated, OR logic).
    .PARAMETER Store
    Optional pre-loaded memory store object.
    .EXAMPLE
    Search-Memories -Query "cargo fmt"
    Search-Memories -Query "Issue PR merge"
    #>
    param(
        [Parameter(Mandatory)][string]$Query,
        [object]$Store
    )

    if (-not $Store) {
        $Store = Read-MemoryStore
    }

    $allMemories = @($Store.memories)
    if ($allMemories.Count -eq 0) {
        Write-Host "[MEMORY] Keine Erinnerungen im Store." -ForegroundColor DarkGray
        return ""
    }

    # Split query into keywords
    $keywords = @($Query -split '\s+' | Where-Object { $_.Length -ge 2 })
    if ($keywords.Count -eq 0) {
        Write-Warning "[MEMORY] Suchbegriff zu kurz oder leer."
        return ""
    }

    # Search: match any keyword in text or id (case-insensitive)
    $matches = @($allMemories | Where-Object {
        $text = "$($_.text) $($_.id)"
        $found = $false
        foreach ($kw in $keywords) {
            if ($text -match [regex]::Escape($kw)) {
                $found = $true
                break
            }
        }
        $found
    })

    if ($matches.Count -eq 0) {
        Write-Host "[MEMORY] Keine Treffer fuer '$Query'." -ForegroundColor DarkGray
        return ""
    }

    $lines = @("[MEMORY-SUCHE: '$Query'] $($matches.Count) Treffer:")
    foreach ($m in $matches) {
        $typeLabel = if ($m.type -eq "temporary") { "TEMP" } else { "PERM" }
        $prioLabel = $m.priority.ToUpper()
        $lines += "- [$typeLabel|$prioLabel] $($m.text)"
    }
    $lines += "---"

    $block = $lines -join "`n"
    Write-Host "[MEMORY] $($matches.Count) Treffer fuer '$Query' gefunden." -ForegroundColor Green
    return $block
}

function Get-MemorySummary {
    <#
    .SYNOPSIS
    Returns a one-line summary of the memory store for lightweight prompt inclusion.
    Use this instead of Format-MemoryBlock when you only need to inform the agent
    that memories exist without injecting their content.
    #>
    param([object]$Store)

    if (-not $Store) {
        $Store = Read-MemoryStore
    }

    $all = @($Store.memories)
    if ($all.Count -eq 0) { return "" }

    $permCount = @($all | Where-Object { $_.type -eq "permanent" }).Count
    $tempCount = @($all | Where-Object { $_.type -eq "temporary" }).Count
    $critCount = @($all | Where-Object { $_.priority -eq "critical" }).Count

    return "[MEMORY] $($all.Count) Erinnerungen gespeichert ($permCount permanent, $tempCount temporaer, $critCount kritisch). Nutze Search-Memories fuer Details."
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
