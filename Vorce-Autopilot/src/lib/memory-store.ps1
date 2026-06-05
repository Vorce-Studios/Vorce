# Vorce-Autopilot/src/lib/memory-store.ps1
# On-Demand Memory System
# Stores permanent rules and temporary context.
# Only CRITICAL memories are auto-injected into prompts.
# All other memories are available via Search-Memories for on-demand retrieval.

Set-StrictMode -Version Latest

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:VarDbDir = Join-Path $script:ScriptRoot "var/db"
$script:MemoryFilePath = Join-Path $script:VarDbDir "autopilot-memories.json"

# Ensure var/db directory exists
if (-not (Test-Path -Path $script:VarDbDir)) {
    New-Item -ItemType Directory -Path $script:VarDbDir -Force | Out-Null
}

function Read-MemoryStore {
    <#
    .SYNOPSIS
    Reads the memory store from autopilot-memories.json.
    Returns the parsed object, or a default empty store if missing.
    #>

    if (-not (Test-Path $script:MemoryFilePath)) {
        $defaultPath = Join-Path $script:ScriptRoot "dashboard/memories.json"
        if (Test-Path $defaultPath) {
            Copy-Item $defaultPath $script:MemoryFilePath -Force | Out-Null
        } else {
            return [PSCustomObject]@{
                schema_version = 1
                memories       = @()
            }
        }
    }

    try {
        $content = Get-Content $script:MemoryFilePath -Raw -Encoding UTF8
        return ($content | ConvertFrom-Json)
    } catch {
        Write-Warning "[MEMORY] Konnte Memory-Store nicht lesen: $_"
        return [PSCustomObject]@{
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

    $memories = @()
    if ($Store) {
        if ($Store -is [System.Collections.IDictionary]) {
            $memories = @($Store["memories"])
        } else {
            try { $memories = @($Store.memories) } catch { }
        }
    }
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
    ON-DEMAND MODEL: Loads only relevant memories dynamically depending on TaskType to reduce token usage.
    Returns an empty string if no relevant memories exist.
    #>
    param(
        [Parameter(Mandatory=$false)][string]$TaskType, # Kept for backward compatibility
        [object]$Store
    )

    $allMemories = @(Get-RelevantMemories -Store $Store)
    if ($allMemories.Count -eq 0) { return "" }

    $relevantMemories = @()
    $otherCount = 0

    if ([string]::IsNullOrWhiteSpace($TaskType)) {
        # Fallback if no TaskType is provided: only inject CRITICAL priority memories automatically
        $relevantMemories = @($allMemories | Where-Object { $_.priority -eq "critical" })
        $otherCount = $allMemories.Count - $relevantMemories.Count
    } else {
        $keywordMap = @{
            "planning" = @("issue", "backlog", "roadmap", "naming", "convention", "plan", "generation", "proposal")
            "monitoring" = @("monitor", "health", "ci", "build", "stalled", "conflict", "fail", "alert")
            "merge_conflict_resolution" = @("conflict", "merge", "git", "branch", "pr", "resolution")
            "coding" = @("code", "implement", "feature", "bug", "fix", "jules", "detailed", "description", "cli")
            "debugging" = @("bug", "fix", "fail", "log", "ci", "error", "debugging")
            "code_review" = @("review", "pr", "quality", "convention", "qa")
            "complex_review" = @("review", "pr", "architecture", "security", "design")
            "simple_review" = @("review", "pr", "syntax", "quick")
            "qa_disposition" = @("qa", "disposition", "approve", "release", "merge")
            "audit" = @("audit", "quota", "budget", "limit", "cost", "telemetry", "efficiency", "token")
            "analysis" = @("analysis", "optim", "refactor", "crate", "module")
        }

        $taskParts = @($TaskType -split '[_-]')
        $taskKeywords = if ($keywordMap.ContainsKey($TaskType)) { @($keywordMap[$TaskType]) } else { @() }

        foreach ($m in $allMemories) {
            # Skip low priority memories to save tokens
            if ($m.priority -eq "low") {
                $otherCount++
                continue
            }

            $text = "$($m.text) $($m.id)".ToLower()
            $isRelevant = $false

            # Check if matches any task-specific keywords
            foreach ($kw in $taskKeywords) {
                if ($text -like "*$kw*") {
                    $isRelevant = $true
                    break
                }
            }

            # Check if matches any parts of the TaskType name
            if (-not $isRelevant) {
                foreach ($part in $taskParts) {
                    if ($part.Length -ge 3 -and $text -like "*$part*") {
                        $isRelevant = $true
                        break
                    }
                }
            }

            # Check if matches universal rules/guidelines
            if (-not $isRelevant) {
                $universalKeywords = @("global", "always", "convention", "rule", "guideline", "naming")
                foreach ($ukw in $universalKeywords) {
                    if ($text -like "*$ukw*") {
                        $isRelevant = $true
                        break
                    }
                }
            }

            if ($isRelevant) {
                $relevantMemories += $m
            } else {
                $otherCount++
            }
        }
    }

    if ($relevantMemories.Count -eq 0 -and $otherCount -eq 0) { return "" }

    $lines = @("[KONTEXT-ERINNERUNGEN]")

    if ($relevantMemories.Count -gt 0) {
        foreach ($m in $relevantMemories) {
            $typeLabel = if ($m.type -eq "temporary") { "[TEMPORAER]" } else { "[RICHTLINIE]" }
            $lines += "- $typeLabel $($m.text)"
        }
    }

    if ($otherCount -gt 0) {
        $lines += "- [INFO] $otherCount weitere Erinnerungen gespeichert (on-demand via Search-Memories abrufbar)."
    }

    $lines += "---"
    $lines += ""

    $block = $lines -join "`n"

    $tokenEstimate = [Math]::Ceiling($block.Length / 4)
    Write-Host "[MEMORY] $($relevantMemories.Count) relevante Erinnerungen fuer '$TaskType' injiziert, $otherCount verfuegbar (~${tokenEstimate} Tokens)" -ForegroundColor DarkGray

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
    #>
    param(
        [Parameter(Mandatory)][string]$Query,
        [object]$Store
    )

    if (-not $Store) {
        $Store = Read-MemoryStore
    }

    $allMemories = @()
    if ($Store) {
        if ($Store -is [System.Collections.IDictionary]) {
            $allMemories = @($Store["memories"])
        } else {
            try { $allMemories = @($Store.memories) } catch { }
        }
    }
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
    $matchingMemories = @($allMemories | Where-Object {
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

    if ($matchingMemories.Count -eq 0) {
        Write-Host "[MEMORY] Keine Treffer fuer '$Query'." -ForegroundColor DarkGray
        return ""
    }

    $lines = @("[MEMORY-SUCHE: '$Query'] $($matchingMemories.Count) Treffer:")
    foreach ($m in $matchingMemories) {
        $typeLabel = if ($m.type -eq "temporary") { "TEMP" } else { "PERM" }
        $prioLabel = $m.priority.ToUpper()
        $lines += "- [$typeLabel|$prioLabel] $($m.text)"
    }
    $lines += "---"

    $block = $lines -join "`n"
    Write-Host "[MEMORY] $($matchingMemories.Count) Treffer fuer '$Query' gefunden." -ForegroundColor Green
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

    $all = @()
    if ($Store) {
        if ($Store -is [System.Collections.IDictionary]) {
            $all = @($Store["memories"])
        } else {
            try { $all = @($Store.memories) } catch { }
        }
    }
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
    $memories = @()
    if ($store -is [System.Collections.IDictionary]) {
        $memories = @($store["memories"])
    } else {
        try { $memories = @($store.memories) } catch { }
    }

    # Enforce max 30 memories
    if ($memories.Count -ge 30) {
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

    if ($store -is [System.Collections.IDictionary]) {
        $store["memories"] = @($memories + $entry)
    } else {
        $store.memories = @($memories + $entry)
    }
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
    $memories = @()
    if ($store -is [System.Collections.IDictionary]) {
        $memories = @($store["memories"])
    } else {
        try { $memories = @($store.memories) } catch { }
    }
    $before = $memories.Count
    $kept = @($memories | Where-Object { $_.id -ne $Id })
    $after = $kept.Count

    if ($before -eq $after) {
        Write-Warning "[MEMORY] Erinnerung '$Id' nicht gefunden."
        return $false
    }

    if ($store -is [System.Collections.IDictionary]) {
        $store["memories"] = @($kept)
    } else {
        $store.memories = @($kept)
    }
    Save-MemoryStore -Store $store
    Write-Host "[MEMORY] Erinnerung '$Id' entfernt." -ForegroundColor Green
    return $true
}

function Optimize-AutopilotMemories {
    <#
    .SYNOPSIS
    Keeps the memory store within the hard 30-entry limit without invoking an
    external model. Critical memories are kept first, then newer entries.
    #>
    param(
        [object]$State,
        [object]$Config,
        [object]$QuotaRegistry,
        [switch]$DryRun
    )

    $store = Read-MemoryStore
    $memories = @()
    if ($store -is [System.Collections.IDictionary]) {
        $memories = @($store["memories"])
    } else {
        try { $memories = @($store.memories) } catch { }
    }
    if ($memories.Count -le 30) {
        Write-Host "[MEMORY] Optimierung nicht noetig ($($memories.Count)/30)." -ForegroundColor DarkGray
        return
    }

    $priorityWeight = @{
        critical = 0
        high     = 1
        medium   = 2
        low      = 3
    }

    $kept = @($memories | Sort-Object `
        @{ Expression = {
            $priority = [string]$_.priority
            if ($priorityWeight.ContainsKey($priority)) { $priorityWeight[$priority] } else { 9 }
        }; Ascending = $true },
        @{ Expression = {
            try { [datetimeoffset]::Parse([string]$_.created_at).UtcDateTime } catch { [datetime]::MinValue }
        }; Ascending = $false } |
        Select-Object -First 30)

    $removed = $memories.Count - $kept.Count
    if ($DryRun.IsPresent) {
        Write-Host "[MEMORY] [DRY RUN] Wuerde $removed alte Erinnerungen entfernen." -ForegroundColor DarkYellow
        return
    }

    if ($store -is [System.Collections.IDictionary]) {
        $store["memories"] = @($kept)
    } else {
        $store.memories = @($kept)
    }
    Save-MemoryStore -Store $store
    Write-Host "[MEMORY] $removed alte Erinnerungen entfernt; 30 bleiben aktiv." -ForegroundColor Green
}
