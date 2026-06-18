# PromptManager.ps1 (Vorce 3.0)
# Verwaltet das dynamische Laden und Formatieren von Markdown-Prompts

function Get-VorcePromptRegistry {
    $registryPath = Join-Path $global:VarDir "prompts/prompt-registry.json"
    if (-not (Test-Path $registryPath)) { return $null }
    return Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Snippet Management
function Get-VorcePromptSnippet {
    <#
    .SYNOPSIS
        Lädt Snippets aus dem shared/snippets Verzeichnis
    .DESCRIPTION
        Lädt wiederverwendbare Prompt-Bausteine für die automatische Ersetzung
    #>
    param(
        [string]$SnippetName,
        [string]$SnippetPath
    )

    $snippetDir = Join-Path $global:VarDir "prompts/shared/snippets"

    # Versuche, das Snippet zu finden
    if ($SnippetPath) {
        $filePath = Join-Path $snippetDir $SnippetPath
    } elseif ($SnippetName) {
        $filePath = Join-Path $snippetDir "$SnippetName.md"
        # Füge .md hinzu, falls nicht vorhanden
        if (-not (Test-Path $filePath)) {
            $filePath = Join-Path $snippetDir "$SnippetName"
        }
    } else {
        Write-VorceStep -Message "Kein Snippet-Name oder -Pfad angegeben" -Status "ERROR"
        return $null
    }

    if (-not (Test-Path $filePath)) {
        Write-VorceStep -Message "Snippet nicht gefunden: $filePath" -Status "WARN"
        return $null
    }

    try {
        $content = Get-Content $filePath -Raw -Encoding UTF8
        return $content
    }
    catch {
        Write-VorceStep -Message "Fehler beim Laden des Snippets: $filePath" -Status "ERROR"
        return $null
    }
}

function Get-VorcePromptSnippets {
    <#
    .SYNOPSIS
        Listet alle verfügbaren Snippets auf
    #>
    $snippetDir = Join-Path $global:VarDir "prompts/shared/snippets"
    if (-not (Test-Path $snippetDir)) {
        return @()
    }

    Get-ChildItem -Path $snippetDir -Filter "*.md" | ForEach-Object {
        @{
            Name = $_.BaseName
            Path = $_.FullName
            Content = (Get-Content $_.FullName -Raw -Encoding UTF8)
        }
    }
}

function Resolve-VorcePromptSnippets {
    <#
    .SYNOPSIS
        Ersetzt Snippet-Platzhalter im Prompt
    .DESCRIPTION
        Sucht nach [[SNIPPET:Name]] im Prompt und ersetzt sie durch den Inhalt des Snippets
    #>
    param(
        [string]$Content,
        [hashtable]$SnippetOverrides = @{}
    )

    # Finde alle Snippet-Platzhalter
    $snippetPattern = '\[\[SNIPPET:([^\]]+)\]\]'
    $matches = Select-String -InputObject $Content -Pattern $snippetPattern -AllMatches

    if (-not $matches) {
        return $Content
    }

    foreach ($match in $matches.Matches) {
        $snippetName = $match.Groups[1].Value

        # Versuche, das Snippet zu laden
        $snippetContent = $null

        # Prüfe, ob es Override gibt
        if ($SnippetOverrides.ContainsKey($snippetName)) {
            $snippetContent = $SnippetOverrides[$snippetName]
        } else {
            $snippetContent = Get-VorcePromptSnippet -SnippetName $snippetName
        }

        if ($snippetContent) {
            # Ersetze den Platzhalter durch den Snippet-Inhalt
            $Content = $Content.Replace($match.Value, $snippetContent)
        } else {
            Write-VorceStep -Message "Snippet nicht gefunden: $snippetName" -Status "WARN"
            # Behalte den Platzhalter bei, falls kein Snippet gefunden wurde
        }
    }

    return $Content
}

function Get-VorcePrompt {
    param(
        [string]$PromptId,
        [string]$MainRun,
        [string]$SubRun,
        [string]$PartRun,
        [hashtable]$Variables = @{},
        [hashtable]$SnippetOverrides = @{}
    )

    $promptDir = Join-Path $global:VarDir "prompts"
    $registry = Get-VorcePromptRegistry
    $lookupId = if ($PromptId) { $PromptId } else { $PartRun }
    $registeredPath = if ($registry -and $lookupId -and $registry.prompts.PSObject.Properties.Name -contains $lookupId) {
        $registry.prompts.$lookupId.path
    } else {
        $null
    }
    $filePath = if ($registeredPath) { Join-Path $promptDir $registeredPath } else { Join-Path $promptDir "runs/$MainRun/$SubRun/$PartRun.md" }

    if (-not (Test-Path $filePath)) {
        Write-VorceStep -Message "Prompt nicht gefunden: $lookupId" -Status "WARN"
        return ""
    }

    $content = Get-Content $filePath -Raw -Encoding UTF8

    # 1. Snippet-Ersetzung (vor der Variablen-Ersetzung)
    $content = Resolve-VorcePromptSnippets -Content $content -SnippetOverrides $SnippetOverrides

    # 2. Variablen-Ersetzung (Simple {{Key}} Syntax)
    foreach ($key in $Variables.Keys) {
        $placeholder = "{{" + $key + "}}"
        $value = [string]$Variables[$key]
        $content = $content.Replace($placeholder, $value)
        $content = $content.Replace('${' + $key + '}', $value)
        $content = $content.Replace('$' + $key, $value)
    }

    return $content
}

# Ende PromptManager
