# MemoryManager.ps1 (Vorce 3.0)
# Deterministische Memory-Auswahl, Inventory, Maintenance und Reporting.

function Get-VorceMemoryProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-VorceMemoryCanonicalObject {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $ordered[$key] = ConvertTo-VorceMemoryCanonicalObject -Value $Value[$key]
        }
        return [pscustomobject]$ordered
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-VorceMemoryCanonicalObject -Value $_ })
    }

    $orderedObject = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object Name)) {
        $orderedObject[$property.Name] = ConvertTo-VorceMemoryCanonicalObject -Value $property.Value
    }
    return [pscustomobject]$orderedObject
}

function Get-VorceMemoryStableHash {
    param([AllowNull()][object]$InputObject)

    $canonical = ConvertTo-VorceMemoryCanonicalObject -Value $InputObject
    $json = if ($null -eq $canonical) { 'null' } else { $canonical | ConvertTo-Json -Depth 50 -Compress }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$json)
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

function Get-VorceMemoryFileHash {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    try {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    } catch {
        return Get-VorceMemoryStableHash -InputObject (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    }
}

function ConvertTo-VorceMemoryDate {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    try {
        return [datetime]$Value
    } catch {
        return $null
    }
}

function ConvertTo-VorceMemoryDateString {
    param([AllowNull()][object]$Value)

    $date = ConvertTo-VorceMemoryDate -Value $Value
    if ($null -eq $date) { return $null }
    return $date.ToUniversalTime().ToString('o')
}

function Get-VorceMemoryNormalizedText {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (([string]$Text).Trim().ToLowerInvariant() -replace '\s+', ' ')
}

function Get-VorceMemoryTextFingerprint {
    param([AllowNull()][string]$Text)

    $normalized = Get-VorceMemoryNormalizedText -Text $Text
    if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }
    return Get-VorceMemoryStableHash -InputObject $normalized
}

function Get-VorceMemoryEstimatedTokens {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    return [int][math]::Max(1, [math]::Ceiling(([string]$Text).Length / 4.0))
}

function Get-VorceMemoryPriorityRank {
    param([AllowNull()][object]$Priority)

    switch (([string]$Priority).ToLowerInvariant()) {
        'critical' { return 4 }
        'high' { return 3 }
        'medium' { return 2 }
        'low' { return 1 }
        default { return 2 }
    }
}

function Test-VorceProtectedMemory {
    param([AllowNull()][object]$Memory)

    if ($null -eq $Memory) { return $false }
    $type = ([string](Get-VorceMemoryProperty -InputObject $Memory -Name 'type' -Default '')).ToLowerInvariant()
    $scope = ([string](Get-VorceMemoryProperty -InputObject $Memory -Name 'scope' -Default '')).ToLowerInvariant()
    $isPermanent = [bool](Get-VorceMemoryProperty -InputObject $Memory -Name 'is_permanent' -Default $false)
    $permanent = [bool](Get-VorceMemoryProperty -InputObject $Memory -Name 'permanent' -Default $false)
    $protected = [bool](Get-VorceMemoryProperty -InputObject $Memory -Name 'protected' -Default $false)

    return (
        $type -in @('permanent', 'user', 'user_memory', 'user-memory') -or
        $scope -eq 'user' -or
        $isPermanent -or
        $permanent -or
        $protected
    )
}

function Get-VorceMemoryItemsFromStore {
    param([AllowNull()][object]$MemoryStore)

    if ($null -eq $MemoryStore) { return @() }

    $memories = Get-VorceMemoryProperty -InputObject $MemoryStore -Name 'memories' -Default $null
    if ($null -ne $memories) { return @($memories) }

    if ($MemoryStore -is [System.Collections.IEnumerable] -and -not ($MemoryStore -is [string])) {
        return @($MemoryStore)
    }

    return @($MemoryStore)
}

function Read-VorceMemoryStore {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            available = $false
            path = $Path
            store = [pscustomobject]@{ schema_version = 1; memories = @() }
            error = 'missing'
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{
                available = $false
                path = $Path
                store = [pscustomobject]@{ schema_version = 1; memories = @() }
                error = 'empty'
            }
        }

        return [pscustomobject]@{
            available = $true
            path = $Path
            store = ($raw | ConvertFrom-Json)
            error = $null
        }
    } catch {
        return [pscustomobject]@{
            available = $false
            path = $Path
            store = [pscustomobject]@{ schema_version = 1; memories = @() }
            error = $_.Exception.Message
        }
    }
}

function New-VorceMemoryStoreWithMemories {
    param(
        [AllowNull()][object]$OriginalStore,
        [Parameter(Mandatory)][object[]]$Memories
    )

    $ordered = [ordered]@{}
    if ($null -ne $OriginalStore -and -not ($OriginalStore -is [System.Array])) {
        foreach ($property in $OriginalStore.PSObject.Properties) {
            if ($property.Name -ne 'memories') {
                $ordered[$property.Name] = $property.Value
            }
        }
    }

    if (-not $ordered.Contains('schema_version')) { $ordered['schema_version'] = 1 }
    $ordered['memories'] = @($Memories)
    return [pscustomobject]$ordered
}

function LoadAndNormalizeMemories {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$MemoryStore = $null,
        [string]$Path = $null,
        [datetime]$Now = (Get-Date)
    )

    $sourcePath = $Path
    if ($Path) {
        $read = Read-VorceMemoryStore -Path $Path
        $MemoryStore = $read.store
    }

    $items = @(Get-VorceMemoryItemsFromStore -MemoryStore $MemoryStore)
    $normalized = @()
    $index = 0

    foreach ($item in $items) {
        $rawId = Get-VorceMemoryProperty -InputObject $item -Name 'id' -Default $null
        $text = [string](Get-VorceMemoryProperty -InputObject $item -Name 'text' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) {
            $text = [string](Get-VorceMemoryProperty -InputObject $item -Name 'content' -Default '')
        }

        $idMissing = [string]::IsNullOrWhiteSpace([string]$rawId)
        $generatedId = "mem-missing-$index-$(Get-VorceMemoryTextFingerprint -Text $text)"
        $id = if ($idMissing) { $generatedId } else { ([string]$rawId).Trim() }

        $type = [string](Get-VorceMemoryProperty -InputObject $item -Name 'type' -Default 'ephemeral')
        if ([string]::IsNullOrWhiteSpace($type)) { $type = 'ephemeral' }
        $priority = [string](Get-VorceMemoryProperty -InputObject $item -Name 'priority' -Default 'medium')
        if ([string]::IsNullOrWhiteSpace($priority)) { $priority = 'medium' }
        $source = [string](Get-VorceMemoryProperty -InputObject $item -Name 'source' -Default 'unknown')
        if ([string]::IsNullOrWhiteSpace($source)) { $source = 'unknown' }
        $scope = [string](Get-VorceMemoryProperty -InputObject $item -Name 'scope' -Default '')
        $status = [string](Get-VorceMemoryProperty -InputObject $item -Name 'status' -Default 'active')
        if ([string]::IsNullOrWhiteSpace($status)) { $status = 'active' }

        $tagsValue = Get-VorceMemoryProperty -InputObject $item -Name 'tags' -Default @()
        $tags = @($tagsValue | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace([string]$_)) { ([string]$_).Trim().ToLowerInvariant() } })
        $createdRaw = Get-VorceMemoryProperty -InputObject $item -Name 'created_at' -Default $null
        $updatedRaw = Get-VorceMemoryProperty -InputObject $item -Name 'updated_at' -Default $null
        $expiresRaw = Get-VorceMemoryProperty -InputObject $item -Name 'expires_at' -Default $null
        $ttlDays = Get-VorceMemoryProperty -InputObject $item -Name 'ttl_days' -Default $null

        $normalizedItem = [pscustomobject]@{
            id = $id
            original_id = if ($idMissing) { $null } else { [string]$rawId }
            id_missing = [bool]$idMissing
            text = $text
            normalized_text = Get-VorceMemoryNormalizedText -Text $text
            text_fingerprint = Get-VorceMemoryTextFingerprint -Text $text
            type = $type.ToLowerInvariant()
            priority = $priority.ToLowerInvariant()
            priority_rank = Get-VorceMemoryPriorityRank -Priority $priority
            source = $source
            scope = $scope
            status = $status.ToLowerInvariant()
            tags = @($tags)
            created_at = ConvertTo-VorceMemoryDateString -Value $createdRaw
            updated_at = ConvertTo-VorceMemoryDateString -Value $updatedRaw
            expires_at = ConvertTo-VorceMemoryDateString -Value $expiresRaw
            created_at_parse_error = ($null -ne $createdRaw -and -not [string]::IsNullOrWhiteSpace([string]$createdRaw) -and $null -eq (ConvertTo-VorceMemoryDate -Value $createdRaw))
            expires_at_parse_error = ($null -ne $expiresRaw -and -not [string]::IsNullOrWhiteSpace([string]$expiresRaw) -and $null -eq (ConvertTo-VorceMemoryDate -Value $expiresRaw))
            ttl_days = $ttlDays
            token_estimate = Get-VorceMemoryEstimatedTokens -Text $text
            is_protected = Test-VorceProtectedMemory -Memory $item
            original_index = $index
            raw = $item
        }
        $normalizedItem | Add-Member -NotePropertyName normalized_hash -NotePropertyValue (Get-VorceMemoryStableHash -InputObject $normalizedItem) -Force
        $normalized += $normalizedItem
        $index++
    }

    return [pscustomobject]@{
        schema_version = 1
        source_path = $sourcePath
        loaded_at = $Now.ToUniversalTime().ToString('o')
        total_count = @($normalized).Count
        memories = @($normalized)
        raw_store_hash = Get-VorceMemoryStableHash -InputObject $MemoryStore
    }
}

function DetectExpiredDuplicateAndInvalidMemories {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject = $null,
        [AllowNull()][object]$MemoryStore = $null,
        [string]$Path = $null,
        [datetime]$Now = (Get-Date)
    )

    $inventory = $InputObject
    if ($null -eq $inventory -or $inventory.PSObject.Properties.Name -notcontains 'memories') {
        $inventory = LoadAndNormalizeMemories -MemoryStore $MemoryStore -Path $Path -Now $Now
    }

    $memories = @($inventory.memories)
    $expired = @()
    $invalid = @()

    foreach ($memory in $memories) {
        $invalidReasons = @()
        if ([bool]$memory.id_missing) { $invalidReasons += 'missing_id' }
        if ([string]::IsNullOrWhiteSpace([string]$memory.text)) { $invalidReasons += 'empty_text' }
        if ([bool]$memory.created_at_parse_error) { $invalidReasons += 'invalid_created_at' }
        if ([bool]$memory.expires_at_parse_error) { $invalidReasons += 'invalid_expires_at' }

        if ($invalidReasons.Count -gt 0) {
            $invalid += [pscustomobject]@{
                memory_id = $memory.id
                original_index = $memory.original_index
                protected = [bool]$memory.is_protected
                reasons = @($invalidReasons)
            }
        }

        $isExpired = $false
        $expiryReason = $null
        if ($memory.expires_at) {
            $expires = ConvertTo-VorceMemoryDate -Value $memory.expires_at
            if ($null -ne $expires -and $expires -le $Now) {
                $isExpired = $true
                $expiryReason = 'expires_at'
            }
        }

        if (-not $isExpired -and $null -ne $memory.ttl_days -and $memory.created_at) {
            try {
                $ttl = [double]$memory.ttl_days
                $created = ConvertTo-VorceMemoryDate -Value $memory.created_at
                if ($null -ne $created -and $ttl -ge 0 -and $created.AddDays($ttl) -le $Now) {
                    $isExpired = $true
                    $expiryReason = 'ttl_days'
                }
            } catch {}
        }

        if ($isExpired -or $memory.status -eq 'expired') {
            $expired += [pscustomobject]@{
                memory_id = $memory.id
                original_index = $memory.original_index
                protected = [bool]$memory.is_protected
                reason = if ($expiryReason) { $expiryReason } else { 'status' }
            }
        }
    }

    $duplicates = @()
    $duplicateGroups = @()
    $groups = @($memories | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.text_fingerprint) } | Group-Object -Property text_fingerprint)
    foreach ($group in @($groups | Where-Object { $_.Count -gt 1 })) {
        $orderedGroup = @($group.Group | Sort-Object `
            @{ Expression = { if ($_.is_protected) { 1 } else { 0 } }; Descending = $true },
            @{ Expression = { [int]$_.priority_rank }; Descending = $true },
            @{ Expression = { if ($_.created_at) { (ConvertTo-VorceMemoryDate -Value $_.created_at).Ticks } else { 0 } }; Descending = $true },
            @{ Expression = { [string]$_.id }; Descending = $false })

        $keeper = $orderedGroup[0]
        $losers = @($orderedGroup | Select-Object -Skip 1)
        $duplicateGroups += [pscustomobject]@{
            fingerprint = $group.Name
            keeper_id = $keeper.id
            duplicate_ids = @($losers | ForEach-Object { $_.id })
            memory_ids = @($orderedGroup | ForEach-Object { $_.id })
        }

        foreach ($loser in $losers) {
            $duplicates += [pscustomobject]@{
                memory_id = $loser.id
                original_index = $loser.original_index
                protected = [bool]$loser.is_protected
                duplicate_of = $keeper.id
                fingerprint = $group.Name
            }
        }
    }

    $candidateIds = @(
        @($expired | ForEach-Object { $_.memory_id }) +
        @($duplicates | ForEach-Object { $_.memory_id }) +
        @($invalid | ForEach-Object { $_.memory_id })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique

    return [pscustomobject]@{
        schema_version = 1
        analysed_at = $Now.ToUniversalTime().ToString('o')
        total_count = @($memories).Count
        memories = @($memories)
        expired = @($expired)
        duplicates = @($duplicates)
        duplicate_groups = @($duplicateGroups)
        invalid = @($invalid)
        candidate_ids = @($candidateIds)
        summary = [pscustomobject]@{
            expired_count = @($expired).Count
            duplicate_count = @($duplicates).Count
            invalid_count = @($invalid).Count
            candidate_count = @($candidateIds).Count
        }
    }
}

function Get-VorceMemoryQueryTerms {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $clean = ([string]$Text).ToLowerInvariant() -replace '[^\p{L}\p{Nd}_#-]+', ' '
    $stop = @('the', 'and', 'oder', 'und', 'mit', 'for', 'from', 'eine', 'einer', 'der', 'die', 'das')
    return @($clean -split '\s+' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -ge 2 -and $stop -notcontains $_
    } | Sort-Object -Unique)
}

function ScoreMemoryRelevance {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Memories = $null,
        [AllowNull()][object]$MemoryStore = $null,
        [AllowNull()][object]$Analysis = $null,
        [string]$Path = $null,
        [string]$Query = '',
        [string]$Context = '',
        [string[]]$Tags = @(),
        [switch]$IncludeZeroScore,
        [datetime]$Now = (Get-Date)
    )

    $inventory = $Memories
    if ($null -eq $inventory -or $inventory.PSObject.Properties.Name -notcontains 'memories') {
        $inventory = LoadAndNormalizeMemories -MemoryStore $MemoryStore -Path $Path -Now $Now
    }

    if ($null -eq $Analysis) {
        $Analysis = DetectExpiredDuplicateAndInvalidMemories -InputObject $inventory -Now $Now
    }

    $excludedIds = @(
        @($Analysis.expired | ForEach-Object { $_.memory_id }) +
        @($Analysis.invalid | ForEach-Object { $_.memory_id }) +
        @($Analysis.duplicates | ForEach-Object { $_.memory_id })
    ) | Sort-Object -Unique

    $queryText = @($Query, $Context, (@($Tags) -join ' ')) -join ' '
    $queryTerms = @(Get-VorceMemoryQueryTerms -Text $queryText)
    $tagTerms = @($Tags | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $scored = @()

    foreach ($memory in @($inventory.memories)) {
        $excluded = $excludedIds -contains $memory.id
        $memoryTerms = @(Get-VorceMemoryQueryTerms -Text ([string]$memory.text))
        $memoryTags = @($memory.tags)
        $termMatches = @($queryTerms | Where-Object { $memoryTerms -contains $_ })
        $tagMatches = @($tagTerms | Where-Object { $memoryTags -contains $_ })
        $phraseMatch = $false
        if (-not [string]::IsNullOrWhiteSpace($Query) -and -not [string]::IsNullOrWhiteSpace([string]$memory.normalized_text)) {
            $phraseMatch = ([string]$memory.normalized_text).Contains((Get-VorceMemoryNormalizedText -Text $Query))
        }

        $score = 0
        $score += @($termMatches).Count * 20
        $score += @($tagMatches).Count * 15
        if ($phraseMatch) { $score += 25 }
        $score += [int]$memory.priority_rank * 3
        if ($memory.is_protected -and @($termMatches).Count -gt 0) { $score += 2 }
        if ($excluded) { $score = 0 }

        if ($IncludeZeroScore -or $score -gt 0) {
            $createdSort = 0
            if ($memory.created_at) {
                $createdDate = ConvertTo-VorceMemoryDate -Value $memory.created_at
                if ($null -ne $createdDate) { $createdSort = $createdDate.Ticks }
            }

            $scored += [pscustomobject]@{
                id = $memory.id
                text = $memory.text
                type = $memory.type
                priority = $memory.priority
                priority_rank = [int]$memory.priority_rank
                source = $memory.source
                tags = @($memory.tags)
                score = [int]$score
                token_estimate = [int]$memory.token_estimate
                match_terms = @($termMatches)
                tag_matches = @($tagMatches)
                phrase_match = [bool]$phraseMatch
                excluded = [bool]$excluded
                created_at_sort = $createdSort
                is_protected = [bool]$memory.is_protected
                memory = $memory
            }
        }
    }

    return @($scored | Sort-Object `
        @{ Expression = { [int]$_.score }; Descending = $true },
        @{ Expression = { [int]$_.priority_rank }; Descending = $true },
        @{ Expression = { [int64]$_.created_at_sort }; Descending = $true },
        @{ Expression = { [string]$_.id }; Descending = $false })
}

function ValidateMemoryBudgets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$ScoredMemories,
        [int]$MaxMemories = 3,
        [int]$MaxTokens = 500
    )

    $MaxMemories = [math]::Max(0, $MaxMemories)
    $MaxTokens = [math]::Max(0, $MaxTokens)
    $selected = @()
    $rejected = @()
    $totalTokens = 0

    foreach ($memory in @($ScoredMemories | Sort-Object `
        @{ Expression = { [int]$_.score }; Descending = $true },
        @{ Expression = { [int]$_.priority_rank }; Descending = $true },
        @{ Expression = { [int64]$_.created_at_sort }; Descending = $true },
        @{ Expression = { [string]$_.id }; Descending = $false })) {

        if (@($selected).Count -ge $MaxMemories) {
            $rejected += [pscustomobject]@{ id = $memory.id; reason = 'memory_count_budget_exhausted'; token_estimate = $memory.token_estimate; score = $memory.score }
            continue
        }
        if ([int]$memory.score -le 0) {
            $rejected += [pscustomobject]@{ id = $memory.id; reason = 'no_relevance'; token_estimate = $memory.token_estimate; score = $memory.score }
            continue
        }
        if ([int]$memory.token_estimate -gt $MaxTokens) {
            $rejected += [pscustomobject]@{ id = $memory.id; reason = 'exceeds_total_token_budget'; token_estimate = $memory.token_estimate; score = $memory.score }
            continue
        }
        if (($totalTokens + [int]$memory.token_estimate) -gt $MaxTokens) {
            $rejected += [pscustomobject]@{ id = $memory.id; reason = 'exceeds_remaining_token_budget'; token_estimate = $memory.token_estimate; score = $memory.score }
            continue
        }

        $selected += $memory
        $totalTokens += [int]$memory.token_estimate
    }

    return [pscustomobject]@{
        schema_version = 1
        max_memories = $MaxMemories
        max_tokens = $MaxTokens
        selected = @($selected)
        rejected = @($rejected)
        selected_count = @($selected).Count
        total_tokens = $totalTokens
        valid = (@($selected).Count -le $MaxMemories -and $totalTokens -le $MaxTokens)
    }
}

function Select-VorceRelevantMemories {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$MemoryStore = $null,
        [string]$Path = $null,
        [string]$Query = '',
        [string]$Context = '',
        [string[]]$Tags = @(),
        [int]$MaxMemories = 3,
        [int]$MaxTokens = 500,
        [bool]$EnableMemorySelection = $false,
        [AllowNull()][object]$Config = $null,
        [datetime]$Now = (Get-Date)
    )

    $configEnabled = Get-VorceMemoryProperty -InputObject (Get-VorceMemoryProperty -InputObject $Config -Name 'memory_selection' -Default $null) -Name 'enabled' -Default $null
    if ($null -ne $configEnabled) { $EnableMemorySelection = [bool]$configEnabled }

    $configuredMaxMemories = Get-VorceMemoryProperty -InputObject (Get-VorceMemoryProperty -InputObject $Config -Name 'memory_selection' -Default $null) -Name 'max_memories' -Default $null
    if ($null -ne $configuredMaxMemories) { $MaxMemories = [int]$configuredMaxMemories }
    $configuredMaxTokens = Get-VorceMemoryProperty -InputObject (Get-VorceMemoryProperty -InputObject $Config -Name 'memory_selection' -Default $null) -Name 'max_tokens' -Default $null
    if ($null -ne $configuredMaxTokens) { $MaxTokens = [int]$configuredMaxTokens }

    if (-not $EnableMemorySelection) {
        return [pscustomobject]@{
            schema_version = 1
            selection_enabled = $false
            reason = 'disabled_by_default'
            max_memories = $MaxMemories
            max_tokens = $MaxTokens
            selected = @()
            rejected = @()
            scored = @()
            selected_count = 0
            total_tokens = 0
        }
    }

    if ([string]::IsNullOrWhiteSpace($Query) -and [string]::IsNullOrWhiteSpace($Context) -and @($Tags).Count -eq 0) {
        return [pscustomobject]@{
            schema_version = 1
            selection_enabled = $true
            reason = 'no_selection_context'
            max_memories = $MaxMemories
            max_tokens = $MaxTokens
            selected = @()
            rejected = @()
            scored = @()
            selected_count = 0
            total_tokens = 0
        }
    }

    $inventory = LoadAndNormalizeMemories -MemoryStore $MemoryStore -Path $Path -Now $Now
    $analysis = DetectExpiredDuplicateAndInvalidMemories -InputObject $inventory -Now $Now
    $scored = @(ScoreMemoryRelevance -Memories $inventory -Analysis $analysis -Query $Query -Context $Context -Tags $Tags -Now $Now)
    $budget = ValidateMemoryBudgets -ScoredMemories $scored -MaxMemories $MaxMemories -MaxTokens $MaxTokens

    return [pscustomobject]@{
        schema_version = 1
        selection_enabled = $true
        reason = if ($budget.selected_count -gt 0) { 'selected' } else { 'no_relevant_memory_within_budget' }
        max_memories = $budget.max_memories
        max_tokens = $budget.max_tokens
        selected = @($budget.selected)
        rejected = @($budget.rejected)
        scored = @($scored)
        selected_count = $budget.selected_count
        total_tokens = $budget.total_tokens
    }
}

function Format-VorceSelectedMemoriesForPrompt {
    param([AllowNull()][object]$Selection)

    if ($null -eq $Selection -or @($Selection.selected).Count -eq 0) { return '' }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Relevant Vorce Memories:') | Out-Null
    foreach ($memory in @($Selection.selected)) {
        $lines.Add("- [$($memory.id)] $($memory.text)") | Out-Null
    }
    return ($lines -join [Environment]::NewLine)
}

function BuildMaintenancePlan {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$MemoryStore = $null,
        [AllowNull()][object]$Analysis = $null,
        [string]$Path = $null,
        [datetime]$Now = (Get-Date)
    )

    $read = $null
    if ($Path) {
        $read = Read-VorceMemoryStore -Path $Path
        $MemoryStore = $read.store
    }
    if ($null -eq $Analysis) {
        $Analysis = DetectExpiredDuplicateAndInvalidMemories -MemoryStore $MemoryStore -Now $Now
    }

    $actions = @()
    $seen = @{}
    $actionIndex = 1

    function Add-MemoryPlanAction {
        param(
            [Parameter(Mandatory)][string]$MemoryId,
            [int]$OriginalIndex,
            [Parameter(Mandatory)][string]$Reason,
            [bool]$Protected
        )

        if ($script:seen.ContainsKey($MemoryId)) { return }
        $script:seen[$MemoryId] = $true
        $operation = if ($Protected) { 'keep' } else { 'delete' }
        $script:actions += [pscustomobject]@{
            action_id = ('mem-action-{0:0000}' -f $script:actionIndex)
            memory_id = $MemoryId
            original_index = $OriginalIndex
            operation = $operation
            reason = $Reason
            protected = [bool]$Protected
            approved = $false
        }
        $script:actionIndex++
    }

    foreach ($invalid in @($Analysis.invalid | Sort-Object original_index, memory_id)) {
        Add-MemoryPlanAction -MemoryId $invalid.memory_id -OriginalIndex $invalid.original_index -Reason ('invalid:' + (@($invalid.reasons) -join ',')) -Protected ([bool]$invalid.protected)
    }
    foreach ($expired in @($Analysis.expired | Sort-Object original_index, memory_id)) {
        Add-MemoryPlanAction -MemoryId $expired.memory_id -OriginalIndex $expired.original_index -Reason ('expired:' + $expired.reason) -Protected ([bool]$expired.protected)
    }
    foreach ($duplicate in @($Analysis.duplicates | Sort-Object original_index, memory_id)) {
        Add-MemoryPlanAction -MemoryId $duplicate.memory_id -OriginalIndex $duplicate.original_index -Reason ('duplicate_of:' + $duplicate.duplicate_of) -Protected ([bool]$duplicate.protected)
    }

    $plan = [pscustomobject]@{
        schema_version = 1
        plan_id = "memory-maintenance-$($Now.ToUniversalTime().ToString('yyyyMMddHHmmss'))"
        created_at = $Now.ToUniversalTime().ToString('o')
        source_path = $Path
        approval_required = $true
        actions = @($actions)
        summary = [pscustomobject]@{
            action_count = @($actions).Count
            delete_candidates = @($actions | Where-Object { $_.operation -eq 'delete' }).Count
            protected_kept = @($actions | Where-Object { $_.operation -eq 'keep' }).Count
        }
        analysis_summary = $Analysis.summary
    }
    $plan | Add-Member -NotePropertyName plan_hash -NotePropertyValue (Get-VorceMemoryStableHash -InputObject $plan) -Force
    return $plan
}

function ApplyApprovedMaintenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [AllowNull()][object]$MemoryStore = $null,
        [string]$Path = $null,
        [string]$BackupDirectory = $null,
        [switch]$DryRun
    )

    $read = $null
    if ($Path) {
        $read = Read-VorceMemoryStore -Path $Path
        $MemoryStore = $read.store
    }
    if ($null -eq $MemoryStore) {
        $MemoryStore = [pscustomobject]@{ schema_version = 1; memories = @() }
    }

    $beforeHash = Get-VorceMemoryStableHash -InputObject $MemoryStore
    $rawMemories = @(Get-VorceMemoryItemsFromStore -MemoryStore $MemoryStore)
    $removeById = @{}
    $removeByIndex = @{}
    $approvedActions = @()
    $skippedActions = @()

    foreach ($action in @($Plan.actions)) {
        $approved = [bool](Get-VorceMemoryProperty -InputObject $action -Name 'approved' -Default $false)
        if (-not $approved) {
            $skippedActions += [pscustomobject]@{ action_id = $action.action_id; memory_id = $action.memory_id; reason = 'not_approved' }
            continue
        }

        if ($action.operation -ne 'delete') {
            $skippedActions += [pscustomobject]@{ action_id = $action.action_id; memory_id = $action.memory_id; reason = 'non_delete_operation' }
            continue
        }

        if ([bool]$action.protected) {
            $skippedActions += [pscustomobject]@{ action_id = $action.action_id; memory_id = $action.memory_id; reason = 'protected_memory' }
            continue
        }

        $approvedActions += $action
        if (-not [string]::IsNullOrWhiteSpace([string]$action.memory_id)) { $removeById[[string]$action.memory_id] = $true }
        if ($null -ne $action.original_index) { $removeByIndex[[int]$action.original_index] = $true }
    }

    $updatedMemories = @()
    $removed = @()
    $index = 0
    foreach ($memory in $rawMemories) {
        $id = [string](Get-VorceMemoryProperty -InputObject $memory -Name 'id' -Default '')
        $protectedNow = Test-VorceProtectedMemory -Memory $memory
        $marked = (($id -and $removeById.ContainsKey($id)) -or $removeByIndex.ContainsKey($index))
        if ($marked -and -not $protectedNow) {
            $removed += [pscustomobject]@{ id = $id; original_index = $index }
        } else {
            $updatedMemories += $memory
        }
        $index++
    }

    $updatedStore = New-VorceMemoryStoreWithMemories -OriginalStore $MemoryStore -Memories $updatedMemories
    $afterHash = Get-VorceMemoryStableHash -InputObject $updatedStore
    $backupPath = $null

    if (@($removed).Count -gt 0 -and $Path -and -not $DryRun) {
        if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
            $BackupDirectory = Join-Path (Split-Path -Parent (Split-Path -Parent $Path)) 'memory-maintenance/backups'
        }
        if (-not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
        }
        $backupPath = Join-Path $BackupDirectory ("autopilot-memories.$(Get-Date -Format 'yyyyMMddHHmmss').bak.json")
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        $updatedStore | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding UTF8
    }

    return [pscustomobject]@{
        schema_version = 1
        applied_at = (Get-Date).ToUniversalTime().ToString('o')
        dry_run = [bool]$DryRun
        before_hash = $beforeHash
        after_hash = $afterHash
        backup_path = $backupPath
        approved_action_count = @($approvedActions).Count
        removed_count = @($removed).Count
        removed = @($removed)
        skipped = @($skippedActions)
        updated_store = $updatedStore
    }
}

function Get-VorceIssueLabels {
    param([AllowNull()][object]$Issue)

    $labels = Get-VorceMemoryProperty -InputObject $Issue -Name 'labels' -Default @()
    return @($labels | ForEach-Object {
        if ($_ -is [string]) {
            $_.ToLowerInvariant()
        } else {
            ([string](Get-VorceMemoryProperty -InputObject $_ -Name 'name' -Default '')).ToLowerInvariant()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-VorceIssueNumber {
    param([AllowNull()][object]$Issue)

    $number = Get-VorceMemoryProperty -InputObject $Issue -Name 'number' -Default $null
    if ($null -eq $number) { $number = Get-VorceMemoryProperty -InputObject $Issue -Name 'id' -Default $null }
    if ($null -eq $number) { return $null }
    return [int]$number
}

function Read-VorceIssueStore {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $issues = Get-VorceMemoryProperty -InputObject $value -Name 'issues' -Default $null
    if ($null -ne $issues) { return @($issues) }
    return @($value)
}

function SyncIssueRelationships {
    [CmdletBinding()]
    param(
        [object[]]$Issues = @(),
        [string]$IssuesPath = $null,
        [string]$PreviousContextPath = $null,
        [datetime]$Now = (Get-Date)
    )

    if ($IssuesPath) { $Issues = @(Read-VorceIssueStore -Path $IssuesPath) }
    $masters = @()
    $children = @()

    foreach ($issue in @($Issues)) {
        $title = [string](Get-VorceMemoryProperty -InputObject $issue -Name 'title' -Default '')
        $labels = @(Get-VorceIssueLabels -Issue $issue)
        $isMaster = $title.StartsWith('MF-StMa_', [System.StringComparison]::OrdinalIgnoreCase) -or $labels -contains 'master-issue'
        $isChild = $title -match '__MF-SubI_' -or $labels -contains 'sub-issue'
        if ($isMaster) { $masters += $issue }
        if ($isChild) { $children += $issue }
    }

    $masterContexts = @()
    foreach ($master in @($masters | Sort-Object { Get-VorceIssueNumber -Issue $_ })) {
        $masterNumber = Get-VorceIssueNumber -Issue $master
        $title = [string](Get-VorceMemoryProperty -InputObject $master -Name 'title' -Default '')
        $body = [string](Get-VorceMemoryProperty -InputObject $master -Name 'body' -Default '')
        $childNumbers = @()

        foreach ($child in @($children)) {
            $childNumber = Get-VorceIssueNumber -Issue $child
            $parentNumber = Get-VorceMemoryProperty -InputObject $child -Name 'master_issue_number' -Default $null
            if ($null -eq $parentNumber) { $parentNumber = Get-VorceMemoryProperty -InputObject $child -Name 'parent_issue_number' -Default $null }
            $childBody = [string](Get-VorceMemoryProperty -InputObject $child -Name 'body' -Default '')
            $bodyMatch = [regex]::Match($childBody, '(?im)(master|parent)\s*:\s*#?(\d+)')
            if ($null -ne $parentNumber -and [int]$parentNumber -eq [int]$masterNumber) {
                $childNumbers += $childNumber
            } elseif ($bodyMatch.Success -and [int]$bodyMatch.Groups[2].Value -eq [int]$masterNumber) {
                $childNumbers += $childNumber
            }
        }

        $childNumbers = @($childNumbers | Where-Object { $null -ne $_ } | Sort-Object -Unique)
        $summaryInput = [ordered]@{
            number = $masterNumber
            title = $title
            body = $body
            child_issue_numbers = @($childNumbers)
        }

        $masterContexts += [pscustomobject]@{
            number = $masterNumber
            title = $title
            body_hash = Get-VorceMemoryStableHash -InputObject $body
            child_issue_numbers = @($childNumbers)
            summary_input_hash = Get-VorceMemoryStableHash -InputObject $summaryInput
        }
    }

    $context = [pscustomobject]@{
        schema_version = 1
        synced_at = $Now.ToUniversalTime().ToString('o')
        master_issues = @($masterContexts)
        master_issue_count = @($masterContexts).Count
    }

    $previous = $null
    if ($PreviousContextPath -and (Test-Path -LiteralPath $PreviousContextPath -PathType Leaf)) {
        $previous = Get-Content -LiteralPath $PreviousContextPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    $previousHashes = @{}
    if ($previous) {
        foreach ($master in @($previous.master_issues)) {
            $previousHashes[[string]$master.number] = [string]$master.summary_input_hash
        }
    }
    $changed = @($masterContexts | Where-Object { -not $previousHashes.ContainsKey([string]$_.number) -or $previousHashes[[string]$_.number] -ne [string]$_.summary_input_hash })
    $context | Add-Member -NotePropertyName changed_master_issue_count -NotePropertyValue @($changed).Count -Force
    return $context
}

function UpdateChangedMasterIssueSummaries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$CurrentContext,
        [AllowNull()][object]$PreviousSummaryStore = $null,
        [string]$PreviousSummaryPath = $null,
        [scriptblock]$SummaryProvider = $null,
        [string]$OutputPath = $null,
        [datetime]$Now = (Get-Date)
    )

    if ($PreviousSummaryPath -and (Test-Path -LiteralPath $PreviousSummaryPath -PathType Leaf)) {
        $PreviousSummaryStore = Get-Content -LiteralPath $PreviousSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $previousByNumber = @{}
    if ($PreviousSummaryStore) {
        foreach ($summary in @($PreviousSummaryStore.summaries)) {
            $previousByNumber[[string]$summary.number] = $summary
        }
    }

    $summaries = @()
    $changedCount = 0
    $llmCallCount = 0

    foreach ($master in @($CurrentContext.master_issues | Sort-Object number)) {
        $previous = $null
        if ($previousByNumber.ContainsKey([string]$master.number)) { $previous = $previousByNumber[[string]$master.number] }
        $unchanged = $previous -and [string]$previous.summary_input_hash -eq [string]$master.summary_input_hash

        if ($unchanged) {
            $summaryText = [string]$previous.summary
            $source = 'unchanged'
        } else {
            $changedCount++
            if ($SummaryProvider) {
                $summaryText = [string](& $SummaryProvider $master $CurrentContext)
                $llmCallCount++
                $source = 'provider'
            } else {
                $summaryText = "Master issue #$($master.number): $($master.title) ($(@($master.child_issue_numbers).Count) child issues)."
                $source = 'local_deterministic'
            }
        }

        $summaries += [pscustomobject]@{
            number = $master.number
            title = $master.title
            summary = $summaryText
            summary_input_hash = $master.summary_input_hash
            child_issue_numbers = @($master.child_issue_numbers)
            source = $source
        }
    }

    $store = [pscustomobject]@{
        schema_version = 1
        updated_at = $Now.ToUniversalTime().ToString('o')
        changed_master_issue_count = $changedCount
        llm_call_count = $llmCallCount
        summaries = @($summaries)
    }

    if ($OutputPath) {
        $dir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $store | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }

    return $store
}

function BuildMemoryUsageStatistics {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$MemoryStore = $null,
        [string]$Path = $null,
        [datetime]$Now = (Get-Date)
    )

    $inventory = LoadAndNormalizeMemories -MemoryStore $MemoryStore -Path $Path -Now $Now
    $analysis = DetectExpiredDuplicateAndInvalidMemories -InputObject $inventory -Now $Now

    function New-CountMap {
        param([object[]]$Values)
        $map = [ordered]@{}
        foreach ($group in @($Values | Group-Object)) {
            $map[$group.Name] = $group.Count
        }
        return [pscustomobject]$map
    }

    $memories = @($inventory.memories)
    return [pscustomobject]@{
        schema_version = 1
        built_at = $Now.ToUniversalTime().ToString('o')
        total_memories = @($memories).Count
        total_estimated_tokens = (@($memories | ForEach-Object { [int]$_.token_estimate }) | Measure-Object -Sum).Sum
        by_type = New-CountMap -Values @($memories | ForEach-Object { $_.type })
        by_priority = New-CountMap -Values @($memories | ForEach-Object { $_.priority })
        by_source = New-CountMap -Values @($memories | ForEach-Object { $_.source })
        protected_count = @($memories | Where-Object { $_.is_protected }).Count
        expired_count = @($analysis.expired).Count
        duplicate_count = @($analysis.duplicates).Count
        invalid_count = @($analysis.invalid).Count
        candidate_count = @($analysis.candidate_ids).Count
    }
}

