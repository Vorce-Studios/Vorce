# PromptManager.ps1 (Vorce 3.0)
# Verwaltet das dynamische Laden und Formatieren von Markdown-Prompts

function Get-VorcePromptRegistry {
    $registryPath = Join-Path $global:VarDir "prompts/prompt-registry.json"
    if (-not (Test-Path $registryPath)) { return $null }
    return Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-VorcePrompt {
    param(
        [string]$PromptId,
        [string]$MainRun,
        [string]$SubRun,
        [string]$PartRun,
        [hashtable]$Variables = @{}
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

    # Variablen-Ersetzung (Simple {{Key}} Syntax)
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
