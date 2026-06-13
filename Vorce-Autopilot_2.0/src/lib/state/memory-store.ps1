# Vorce-Autopilot/src/lib/memory-store.ps1
# Einfacher Memory-Store zur kontextuellen Optimierung von KI-Prompts

Set-StrictMode -Version Latest

function Get-MemoryFilePath {
    if ($null -eq (Get-Variable -Name "VorceAutopilotMemoryFilePath" -Scope Global -ErrorAction SilentlyContinue)) {
        $global:VorceAutopilotMemoryFilePath = Join-Path $PSScriptRoot "../../../var/db/memory-store.json"
    }
    return $global:VorceAutopilotMemoryFilePath
}

function New-MemoryStore {
    return [pscustomobject]@{
        schema_version = 1
        memories       = @()
    }
}

function Read-MemoryStore {
    $path = Get-MemoryFilePath
    if (-not (Test-Path $path)) {
        return New-MemoryStore
    }

    try {
        $content = Get-Content $path -Raw -Encoding UTF8
        $obj = $content | ConvertFrom-Json
        if (-not $obj.memories) { $obj.memories = @() }
        return $obj
    } catch {
        Write-Warning "Memory-Store beschaedigt: $_"
        return New-MemoryStore
    }
}

function Save-MemoryStore {
    param([Parameter(Mandatory)][object]$Store)
    $path = Get-MemoryFilePath
    $json = $Store | ConvertTo-Json -Depth 20 -Compress
    $json | Out-File -FilePath $path -Encoding UTF8 -Force
}

function Add-AutopilotMemory {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Type = "temporary", # permanent | temporary
        [string]$Priority = "medium", # critical | high | medium | low
        [string]$Source = "system"
    )

    $Store = Read-MemoryStore
    $id = "mem-$(Get-Date -Format 'yyyyMMdd')-$([guid]::NewGuid().ToString().Substring(0,8))"

    $entry = [ordered]@{
        id         = $id
        text       = $Text
        type       = $Type
        priority   = $Priority
        created_at = (Get-Date -Format 'o')
        source     = $Source
    }

    $Store.memories += @($entry)
    Save-MemoryStore -Store $Store
    Write-Host "[MEMORY] Neue Erinnerung gespeichert ($Priority): $($Text.Substring(0, [Math]::Min(50, $Text.Length)))..." -ForegroundColor Gray
}

function Get-RelevantMemories {
    param([string]$ContextHint = "")

    $Store = Read-MemoryStore
    # Zukuenftig: Hier koennte semantische Suche (Embedding) implementiert werden
    # Vorerst: Einfach die letzten 10 temporaeren und alle permanenten/critical Memories

    $relevant = $Store.memories | Where-Object { $_.priority -eq "critical" -or $_.type -eq "permanent" }
    $recentTemp = $Store.memories | Where-Object { $_.type -eq "temporary" -and $_.priority -ne "critical" } | Select-Object -Last 10

    return ($relevant + $recentTemp) | Sort-Object created_at
}

function Format-MemoryBlock {
    param([string]$ContextHint = "")

    $memories = Get-RelevantMemories -ContextHint $ContextHint
    if (@($memories).Count -eq 0) { return "" }

    $block = "`n### AUTOPILOT LONG-TERM MEMORY (PAST EXPERIENCE):`n"
    foreach ($m in $memories) {
        $block += "- [$($m.created_at)] ($($m.priority)): $($m.text)`n"
    }
    return $block
}

function Optimize-AutopilotMemories {
    Write-Host "[MEMORY] Optimiere Memory-Store..." -ForegroundColor DarkGray
    $Store = Read-MemoryStore

    # 1. Entferne sehr alte temporaere Memories (älter als 30 Tage)
    $threshold = (Get-Date).AddDays(-30)
    $oldCount = $Store.memories.Count
    $Store.memories = $Store.memories | Where-Object {
        $_.type -eq "permanent" -or $_.priority -eq "critical" -or (Get-Date $_.created_at) -gt $threshold
    }

    $removed = $oldCount - $Store.memories.Count
    if ($removed -gt 0) {
        Write-Host "[MEMORY] $removed veraltete temporaere Erinnerungen entfernt." -ForegroundColor Gray
    }

    # 2. Begrenze Gesamtanzahl auf 200 (außer critical)
    if ($Store.memories.Count -gt 200) {
        $critical = $Store.memories | Where-Object { $_.priority -eq "critical" }
        $others = $Store.memories | Where-Object { $_.priority -ne "critical" } | Select-Object -Last (200 - $critical.Count)
        $Store.memories = $critical + $others
    }

    Save-MemoryStore -Store $Store
}

# Export-ModuleMember ist nur fuer .psm1 Module relevant.
# Export-ModuleMember -Function Read-MemoryStore, Save-MemoryStore, Add-AutopilotMemory, Get-RelevantMemories, Format-MemoryBlock, Optimize-AutopilotMemories
