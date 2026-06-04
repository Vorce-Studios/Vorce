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
        [Parameter(Mandatory=$false)][string]$TaskType,
        [object]$Store,
        [switch]$DryRun
    )

    if (-not $Store) {
        $Store = Read-MemoryStore
    }

    $allMemories = Get-RelevantMemories -Store $Store
    if ($allMemories.Count -eq 0) { return "" }

    # Context-aware filtering: filter memories by current TaskType scope or "all"
    $resolvedTaskType = if ([string]::IsNullOrWhiteSpace($TaskType)) { "all" } else { $TaskType.ToLower() }
    $scopedMemories = @($allMemories | Where-Object {
        $mScopes = if ($_.PSObject.Properties.Name -contains "scopes") { @($_.scopes) } else { @("all") }
        $mScopes -contains "all" -or $mScopes -contains $resolvedTaskType
    })

    if ($scopedMemories.Count -eq 0) { return "" }

    # Only inject CRITICAL priority memories automatically
    $critical = @($scopedMemories | Where-Object { $_.priority -eq "critical" })
    $otherCount = $scopedMemories.Count - $critical.Count

    if ($critical.Count -eq 0 -and $otherCount -eq 0) { return "" }

    $lines = @("[KONTEXT-ERINNERUNGEN]")
    $needSave = $false
    $nowStr = (Get-Date -Format 'o')

    if ($critical.Count -gt 0) {
        foreach ($m in $critical) {
            $typeLabel = if ($m.type -eq "temporary") { "[TEMPORAER]" } else { "[RICHTLINIE]" }
            $lines += "- $typeLabel $($m.text)"

            # Update access timestamp in the original store object
            $storeMem = @($Store.memories | Where-Object { $_.id -eq $m.id })[0]
            if ($storeMem) {
                if ($storeMem.PSObject.Properties.Name -contains "last_accessed_at") {
                    $storeMem.last_accessed_at = $nowStr
                } else {
                    $storeMem | Add-Member -MemberType NoteProperty -Name "last_accessed_at" -Value $nowStr -Force
                }
                $needSave = $true
            }
        }
    }

    if ($otherCount -gt 0) {
        $lines += "- [INFO] $otherCount weitere Erinnerungen fuer '$resolvedTaskType' gespeichert (on-demand via Search-Memories abrufbar)."
    }

    $lines += "---"
    $lines += ""

    $block = $lines -join "`n"

    # Atomically save updated access timestamps
    if ($needSave -and -not $DryRun.IsPresent) {
        Save-MemoryStore -Store $Store
    }

    $tokenEstimate = [Math]::Ceiling($block.Length / 4)
    Write-Host "[MEMORY] $($critical.Count) kritische Erinnerungen injiziert fuer '$resolvedTaskType', $otherCount on-demand verfuegbar (~${tokenEstimate} Tokens)" -ForegroundColor DarkGray

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
        [string[]]$Scopes = @("all"),
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

    # Validate scopes
    $allowedScopes = @("planning", "monitoring", "audit", "coding", "all")
    $validatedScopes = @()
    foreach ($s in $Scopes) {
        $sLower = $s.ToLower().Trim()
        if ($allowedScopes -contains $sLower) {
            $validatedScopes += $sLower
        } else {
            Write-Warning "[MEMORY] Ungueltiger Scope '$s' ignoriert."
        }
    }
    if ($validatedScopes.Count -eq 0) {
        $validatedScopes = @("all")
    }

    $id = "mem-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 4))"

    $entry = [ordered]@{
        id               = $id
        text             = $Text
        type             = $Type
        priority         = $Priority
        scopes           = $validatedScopes
        created_at       = (Get-Date -Format 'o')
        last_accessed_at = (Get-Date -Format 'o')
        source           = $Source
    }

    $store.memories += @($entry)
    Save-MemoryStore -Store $store

    Write-Host "[MEMORY] Erinnerung '$id' hinzugefuegt ($Type) mit Scopes ($($validatedScopes -join ', '))." -ForegroundColor Green
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

function Optimize-AutopilotMemories {
    <#
    .SYNOPSIS
    Runs an LLM-based audit to consolidate, prioritize, or prune autopilot memories.
    #>
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$QuotaRegistry,
        [switch]$DryRun
    )

    $store = Read-MemoryStore
    if (-not $store.memories -or $store.memories.Count -eq 0) {
        Write-Host "[MEMORY-OPTIMIZE] Keine Erinnerungen zum Optimieren vorhanden." -ForegroundColor Gray
        return
    }

    Write-Host "`n[MEMORY-OPTIMIZE] Starte autonome Memory-Optimierung..." -ForegroundColor Blue

    $memoriesData = @()
    foreach ($m in $store.memories) {
        $scopesStr = if ($m.PSObject.Properties.Name -contains "scopes") { $m.scopes -join ", " } else { "all" }
        $lastAccessed = if ($m.PSObject.Properties.Name -contains "last_accessed_at") { $m.last_accessed_at } else { "never" }
        $memoriesData += [ordered]@{
            id = $m.id
            text = $m.text
            type = $m.type
            priority = $m.priority
            scopes = $scopesStr
            created_at = $m.created_at
            last_accessed_at = $lastAccessed
        }
    }
    $memoriesJson = $memoriesData | ConvertTo-Json -Depth 5

    $promptText = @"
Du bist das autonome Memory-Optimierungs-Modul des Vorce-Autopiloten.
Deine Aufgabe ist es, den Speicher (autopilot-memories.json) sauber, hochrelevant und token-effizient zu halten.

Hier ist die Liste der aktuellen Erinnerungen:
$memoriesJson

Analysiere diese Erinnerungen und bestimme:
1. Redundanzen & Ähnlichkeiten: Gibt es Erinnerungen, die sich überschneiden oder das Gleiche aussagen? Wenn ja, schlage eine Zusammenführung ("merge") vor.
2. Veraltetes/Inaktivität (Decay): Erinnerungen vom Typ 'temporary', die seit längerer Zeit nicht mehr per 'last_accessed_at' aufgerufen wurden, sind wahrscheinlich veraltet oder gelöst. Wenn sie nicht mehr nützlich sind, schlage das Löschen ("delete") vor.
3. Falsche Scopes oder Prioritäten: Überprüfe, ob die Priorität (critical, high, medium, low) oder der Scope (planning, monitoring, audit, coding, all) angepasst werden sollte, um Token in unrelevanten Phasen zu sparen (z.B. eine reine Programmier-Richtlinie braucht keinen 'planning' oder 'audit' Scope).

Gib ein JSON-Objekt zurück, das strikt die folgende Struktur hat:
{
  "actions": [
    {
      "action": "delete",
      "id": "mem-id-hier"
    },
    {
      "action": "merge",
      "ids": ["mem-id-1", "mem-id-2"],
      "merged_memory": {
        "text": "Der konsolidierte, präzise Text, der beide Erinnerungen zusammenfasst (auf Deutsch)",
        "type": "temporary|permanent",
        "priority": "critical|high|medium|low",
        "scopes": ["all", "planning", "coding"]
      }
    },
    {
      "action": "modify",
      "id": "mem-id-hier",
      "priority": "new-priority-hier",
      "scopes": ["new-scope-1", "new-scope-2"]
    }
  ]
}

WICHTIGE REGELN:
1. Deine Antwort MUSS ausschließlich valides JSON sein. Kein Markdown-Codeblock, kein Begleittext!
2. Jede Konsolidierung oder Textänderung MUSS auf DEUTSCH sein.
3. Sei vorsichtig bei permanenten Richtlinien (type=permanent). Diese sollten selten gelöscht werden, es sei denn, sie widersprechen sich oder sind redundant.
4. Wenn keine Optimierungen nötig sind, gib ein leeres Array zurück: { "actions": [] }
"@

    $libDir = Split-Path $PSCommandPath
    $ScriptDir = Split-Path $libDir

    $promptFile = Join-Path $ScriptDir "tmp\memory-opt-prompt.txt"
    $promptText | Out-File -FilePath $promptFile -Encoding UTF8

    $outputFile = Join-Path $ScriptDir "tmp\memory-opt-result.json"
    $cliArgsFile = Join-Path $ScriptDir "tmp\memory-opt-args.json"
    @("-m", "gemini-2.5-flash", "--output-format", "json", "-y") | ConvertTo-Json -Depth 5 -Compress | Out-File $cliArgsFile -Encoding UTF8

    $statusFile = Join-Path $ScriptDir "tmp\memory-opt-status.txt"
    $runVisibleCmd = Join-Path $ScriptDir "tools\run-visible-ceo-phase.ps1"

    $cliArgs = @{
        CliCommand   = "gemini"
        CliArgsFile  = $cliArgsFile
        OutputFile   = $outputFile
        StatusFile   = $statusFile
        PhaseName    = "Memory-Optimierung"
        ProviderName = "Gemini"
        PromptFile   = $promptFile
    }

    if ($DryRun.IsPresent) {
        Write-Host "[MEMORY-OPTIMIZE] [DRY RUN] Memory-Optimierung uebersprungen." -ForegroundColor DarkYellow
    } else {
        Write-Host "[MEMORY-OPTIMIZE] Starte visible Terminal zur Memory-Optimierung..." -ForegroundColor Cyan
        & $runVisibleCmd @cliArgs | Out-Null

        if (Test-Path $outputFile) {
            try {
                $resultJson = Get-Content $outputFile -Raw -Encoding UTF8
                $parsedObj = $null
                $jsonObjMatch = [regex]::Match($resultJson, '(?s)\{.*\}')
                if ($jsonObjMatch.Success) {
                    $parsedObj = $jsonObjMatch.Value | ConvertFrom-Json
                    
                    # Handle wrapper JSON from CLI router if present
                    if ($null -ne $parsedObj -and $parsedObj.PSObject.Properties.Name -contains "response") {
                        $cleanJson = $parsedObj.response -replace '(?s)```json\s*', '' -replace '(?s)```\s*$', ''
                        try {
                            $parsedObj = $cleanJson | ConvertFrom-Json
                        } catch {
                            Write-Warning "[MEMORY-OPTIMIZE] Konnte eingebettetes JSON im Response nicht parsen."
                        }
                    }
                }

                $actions = @()
                if ($parsedObj -and $parsedObj.actions) {
                    $actions = @($parsedObj.actions)
                }

                if ($actions.Count -eq 0) {
                    Write-Host "[MEMORY-OPTIMIZE] Keine Optimierungsmassnahmen vorgeschlagen." -ForegroundColor Green
                } else {
                    $newMemories = [System.Collections.ArrayList]@($store.memories)
                    $modifiedAny = $false

                    foreach ($act in $actions) {
                        switch ($act.action) {
                            "delete" {
                                $targetId = $act.id
                                $found = $null
                                for ($i = 0; $i -lt $newMemories.Count; $i++) {
                                    if ($newMemories[$i].id -eq $targetId) {
                                        $found = $newMemories[$i]
                                        break
                                    }
                                }
                                if ($found) {
                                    $newMemories.Remove($found)
                                    Write-Host "[MEMORY-OPTIMIZE] Geloescht: $($found.id) - '$($found.text)'" -ForegroundColor Yellow
                                    $modifiedAny = $true
                                }
                            }

                            "merge" {
                                $mergedIds = @($act.ids)
                                $toRemove = @()
                                foreach ($mem in $newMemories) {
                                    if ($mergedIds -contains $mem.id) {
                                        $toRemove += $mem
                                    }
                                }
                                foreach ($tr in $toRemove) {
                                    $newMemories.Remove($tr)
                                    Write-Host "[MEMORY-OPTIMIZE] Entfernt fuer Merge: $($tr.id)" -ForegroundColor DarkGray
                                }

                                $mMem = $act.merged_memory
                                $newId = "mem-$(Get-Date -Format 'yyyyMMddHHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 4))"
                                $nowStr = (Get-Date -Format 'o')
                                $mScopes = if ($mMem.scopes) { @($mMem.scopes) } else { @("all") }

                                $newEntry = [ordered]@{
                                    id               = $newId
                                    text             = $mMem.text
                                    type             = $mMem.type
                                    priority         = $mMem.priority
                                    scopes           = $mScopes
                                    created_at       = $nowStr
                                    last_accessed_at = $nowStr
                                    source           = "optimization"
                                }
                                $newMemories.Add($newEntry)
                                Write-Host "[MEMORY-OPTIMIZE] Zusammengefuehrt: $newId - '$($mMem.text)'" -ForegroundColor Green
                                $modifiedAny = $true
                            }

                            "modify" {
                                $targetId = $act.id
                                $found = $null
                                for ($i = 0; $i -lt $newMemories.Count; $i++) {
                                    if ($newMemories[$i].id -eq $targetId) {
                                        $found = $newMemories[$i]
                                        break
                                    }
                                }
                                if ($found) {
                                    if ($act.priority) {
                                        if ($found.PSObject.Properties.Name -contains "priority") {
                                            $found.priority = $act.priority
                                        } else {
                                            $found | Add-Member -MemberType NoteProperty -Name "priority" -Value $act.priority -Force
                                        }
                                    }
                                    if ($act.scopes) {
                                        $newScopesList = @($act.scopes)
                                        if ($found.PSObject.Properties.Name -contains "scopes") {
                                            $found.scopes = $newScopesList
                                        } else {
                                            $found | Add-Member -MemberType NoteProperty -Name "scopes" -Value $newScopesList -Force
                                        }
                                    }
                                    Write-Host "[MEMORY-OPTIMIZE] Modifiziert: $targetId (Prio: $($act.priority), Scopes: $($act.scopes -join ', '))" -ForegroundColor Cyan
                                    $modifiedAny = $true
                                }
                            }
                        }
                    }

                    if ($modifiedAny) {
                        $store.memories = @($newMemories)
                        Save-MemoryStore -Store $store
                        Write-Host "[MEMORY-OPTIMIZE] Optimierungen wurden erfolgreich gespeichert." -ForegroundColor Green
                    }
                }
            } catch {
                Write-Warning "[MEMORY-OPTIMIZE] Fehler beim Parsen des Optimierungs-Ergebnisses: $_"
            }
        }

        # Cleanup temp files
        Remove-Item -Path $promptFile, $outputFile, $cliArgsFile, $statusFile -Force -ErrorAction SilentlyContinue
    }
}
