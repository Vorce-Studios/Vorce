# PromptManager.ps1 (Vorce 3.0)
# Verwaltet das dynamische Laden und Formatieren von Markdown-Prompts

function Get-VorcePrompt {
    param(
        [Parameter(Mandatory)][string]$MainRun,
        [Parameter(Mandatory)][string]$SubRun,
        [Parameter(Mandatory)][string]$PartRun,
        [hashtable]$Variables = @{}
    )

    $promptDir = Join-Path $PSScriptRoot "../../var/prompts"
    $filePath = Join-Path $promptDir "$MainRun/$SubRun/$PartRun.md"

    if (-not (Test-Path $filePath)) {
        # Fallback auf Deliberation
        $filePath = Join-Path $promptDir "deliberation/$PartRun.md"
        if (-not (Test-Path $filePath)) {
            # Fallback auf generische Phasen-Ordner
            $filePath = Join-Path $promptDir "phases/$PartRun.md"
            if (-not (Test-Path $filePath)) {
                Write-VorceStep -Message "Prompt nicht gefunden: $PartRun.md" -Status "WARN"
                return ""
            }
        }
    }

    $content = Get-Content $filePath -Raw -Encoding UTF8

    # Variablen-Ersetzung (Simple {{Key}} Syntax)
    foreach ($key in $Variables.Keys) {
        $placeholder = "{{" + $key + "}}"
        $value = [string]$Variables[$key]
        $content = $content.Replace($placeholder, $value)
    }

    return $content
}

# Ende PromptManager
