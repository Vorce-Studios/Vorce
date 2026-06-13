# Typed access to the @Vorce Project Manager.

Set-StrictMode -Version Latest

$script:VorceProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:VorceProjectItemsCachePath = Join-Path $script:VorceProjectRoot "var/db/project-items.json"

function Get-VorceProjectSettings {
    return [pscustomobject]@{
        Owner  = if ($env:VORCE_PROJECT_OWNER) { $env:VORCE_PROJECT_OWNER } else { "Vorce-Studios" }
        Number = if ($env:VORCE_PROJECT_NUMBER) { [int]$env:VORCE_PROJECT_NUMBER } else { 1 }
    }
}

function Invoke-VorceGhJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & gh @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "gh $($Arguments -join ' ') fehlgeschlagen: $($output | Out-String)"
        return $null
    }
    if ([string]::IsNullOrWhiteSpace(($output | Out-String))) { return $null }
    return ($output | Out-String | ConvertFrom-Json)
}

function Get-VorceProjectSchema {
    $settings = Get-VorceProjectSettings
    $data = Invoke-VorceGhJson -Arguments @("project", "field-list", [string]$settings.Number, "--owner", $settings.Owner, "--format", "json")
    if ($null -eq $data -or $null -eq $data.fields) { return [pscustomobject]@{ fields = @() } }
    return $data
}

function Get-VorceProjectItems {
    $settings = Get-VorceProjectSettings
    $data = Invoke-VorceGhJson -Arguments @("project", "item-list", [string]$settings.Number, "--owner", $settings.Owner, "--limit", "1000", "--format", "json")
    if ($null -eq $data -or $null -eq $data.items) {
        if (Test-Path -LiteralPath $script:VorceProjectItemsCachePath) {
            $fileInfo = Get-Item -LiteralPath $script:VorceProjectItemsCachePath
            if ($fileInfo.LastWriteTime -ge (Get-Date).AddMinutes(-5)) {
                try {
                    $cachedData = Get-Content -LiteralPath $script:VorceProjectItemsCachePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                    if ($null -ne $cachedData -and $null -ne $cachedData.items) {
                        Write-Warning "[PROJECT] Live-Abfrage fehlgeschlagen. Verwende Project-Item-Cache (Alter: $([Math]::Round(((Get-Date) - $fileInfo.LastWriteTime).TotalMinutes, 1)) Min)."
                        return @($cachedData.items)
                    }
                } catch {
                    Write-Warning "[PROJECT] Project-Item-Cache konnte nicht gelesen werden: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "[PROJECT] Project-Item-Cache ist aelter als 5 Minuten und wird ignoriert."
            }
        }
        return @()
    }

    try {
        if (Get-Command Write-SafeJson -ErrorAction SilentlyContinue) {
            Write-SafeJson -FilePath $script:VorceProjectItemsCachePath -Data $data
        } else {
            $data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:VorceProjectItemsCachePath -Encoding UTF8
        }
    } catch {
        Write-Warning "[PROJECT] Project-Item-Cache konnte nicht aktualisiert werden: $($_.Exception.Message)"
    }
    return @($data.items)
}

function Get-VorceProjectItemMapByIssueNumber {
    param([object[]]$Items = @())

    if ($Items.Count -eq 0) { $Items = @(Get-VorceProjectItems) }
    $map = @{}
    foreach ($item in $Items) {
        if ($null -ne $item.content -and [string]$item.content.type -eq "Issue" -and $null -ne $item.content.number) {
            $map[[int]$item.content.number] = $item
        }
    }
    return $map
}

function Resolve-VorceProjectAgentValue {
    param([AllowNull()][string]$Agent)

    switch -Regex (([string]$Agent).Trim()) {
        '^(jules|AgentJules)$' { return "AgentJules" }
        '^(gemini|gemini_cli|Gemini CLI)$' { return "Gemini CLI" }
        '^(codex|codex_cli|Codex CLI)$' { return "Codex CLI" }
        '^(claude|claude_code|Claude Code)$' { return "Claude Code" }
        '^(cline|cline_cli|Cline CLI)$' { return "Cline CLI" }
        default { return "Gemini CLI" }
    }
}

function Resolve-VorceInternalAgentValue {
    param([AllowNull()][string]$Agent)

    switch (([string]$Agent).Trim()) {
        "AgentJules" { return "jules" }
        "Gemini CLI" { return "gemini_cli" }
        "Codex CLI" { return "codex_cli" }
        "Claude Code" { return "claude_code" }
        "Cline CLI" { return "cline_cli" }
        default { return "gemini_cli" }
    }
}

function Get-VorceTaskIdFromTitle {
    param([Parameter(Mandatory)][string]$Title)

    if ($Title -match '^(\*D\*\*-\d{3})_') { return $Matches[1] }
    if ($Title -match '^(M\.\.\.-\d{3})_') { return $Matches[1] }
    if ($Title -match '^(___M-\d{3}_s\d+)_') { return $Matches[1] }
    return $Title
}

function Get-VorceProjectItem {
    param(
        [Parameter(Mandatory)][string]$IssueUrl,
        [object[]]$KnownItems = @()
    )

    if ($IssueUrl -match '/issues/(\d+)$') {
        $number = [int]$Matches[1]
        $map = Get-VorceProjectItemMapByIssueNumber -Items $KnownItems
        if ($map.ContainsKey($number)) { return $map[$number] }
    }

    $settings = Get-VorceProjectSettings
    $added = Invoke-VorceGhJson -Arguments @("project", "item-add", [string]$settings.Number, "--owner", $settings.Owner, "--url", $IssueUrl, "--format", "json")
    if ($null -eq $added -or [string]::IsNullOrWhiteSpace([string]$added.id)) {
        throw "Project-Item konnte fuer $IssueUrl nicht ermittelt werden."
    }
    return $added
}

function Set-VorceProjectItemFields {
    param(
        [Parameter(Mandatory)][string]$IssueUrl,
        [Parameter(Mandatory)][hashtable]$Fields
    )

    $settings = Get-VorceProjectSettings
    $project = Invoke-VorceGhJson -Arguments @("project", "view", [string]$settings.Number, "--owner", $settings.Owner, "--format", "json")
    $schema = Get-VorceProjectSchema
    if ($null -eq $project -or [string]::IsNullOrWhiteSpace([string]$project.id)) {
        throw "@Vorce Project Manager ist fuer Schreibzugriffe nicht erreichbar."
    }
    $item = Get-VorceProjectItem -IssueUrl $IssueUrl

    foreach ($entry in $Fields.GetEnumerator()) {
        if ($null -eq $entry.Value -or [string]::IsNullOrWhiteSpace([string]$entry.Value)) { continue }
        $field = @($schema.fields | Where-Object { [string]$_.name -eq [string]$entry.Key } | Select-Object -First 1)
        if ($field.Count -eq 0) {
            throw "Project-Feld '$($entry.Key)' fehlt im @Vorce Project Manager."
        }

        $commandArguments = @("project", "item-edit", "--id", [string]$item.id, "--project-id", [string]$project.id, "--field-id", [string]$field[0].id)
        if ([string]$field[0].type -eq "ProjectV2SingleSelectField") {
            $option = @($field[0].options | Where-Object { [string]$_.name -eq [string]$entry.Value } | Select-Object -First 1)
            if ($option.Count -eq 0) {
                throw "Wert '$($entry.Value)' ist fuer Project-Feld '$($entry.Key)' nicht definiert."
            }
            $commandArguments += @("--single-select-option-id", [string]$option[0].id)
        } else {
            $commandArguments += @("--text", [string]$entry.Value)
        }
        $null = Invoke-VorceGhJson -Arguments $commandArguments
    }

    # Invalidate cache
    Remove-Item -LiteralPath $script:VorceProjectItemsCachePath -Force -ErrorAction SilentlyContinue
}

function Sync-VorceProjectFieldsSafe {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][int]$IssueNumber,
        [Parameter(Mandatory)][hashtable]$Fields
    )

    try {
        Set-VorceProjectItemFields -IssueUrl "https://github.com/$Repository/issues/$IssueNumber" -Fields $Fields
        return $true
    } catch {
        Write-Warning "[PROJECT] Sync fuer Issue #$IssueNumber fehlgeschlagen: $($_.Exception.Message)"
        return $false
    }
}

function New-VorceManagedIssue {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Body,
        [string]$TaskType = "Feature",
        [ValidateSet("A", "B", "C")][string]$Priority = "B",
        [string]$Agent = "gemini_cli",
        [ValidateSet("simple", "detailed", "n_a")][string]$ReviewType = "simple",
        [string]$OriginLabel = ""
    )

    $labels = if ([string]::IsNullOrWhiteSpace($OriginLabel)) { @() } else { @($OriginLabel) }
    $issueUrl = New-GitHubIssue -Repository $Repository -Title $Title -Body $Body -Labels $labels
    $issueNumber = if ($issueUrl -match '/issues/(\d+)') { [int]$Matches[1] } else { throw "Issue-Nummer fehlt in URL: $issueUrl" }

    Set-VorceProjectItemFields -IssueUrl $issueUrl -Fields @{
        "Status"      = "Planed"
        "task_id"     = Get-VorceTaskIdFromTitle -Title $Title
        "task_type"   = $TaskType
        "priority"    = $Priority
        "agent"       = Resolve-VorceProjectAgentValue -Agent $Agent
        "description" = if ([string]::IsNullOrWhiteSpace($Body)) { $Title } else { ($Body -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1) }
        "review_type" = $ReviewType
    }

    return [pscustomobject]@{ Url = $issueUrl; Number = $issueNumber; Title = $Title }
}
