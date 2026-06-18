# PromptManager Test Script
# Testet die Snippet-Funktionalität und Token-Effizienz

# Setze globale Variable für VarDir
$global:VarDir = Join-Path $PSScriptRoot ".." "var"

Write-Host "=== PromptManager Test ===" -ForegroundColor Cyan

# Test 1: Snippet Laden
Write-Host "`n1. Teste Snippet-Laden:" -ForegroundColor Yellow
$snippet = Get-VorcePromptSnippet -SnippetName "Dashboard-Link-Context"
if ($snippet) {
    Write-Host "✓ Snippet erfolgreich geladen" -ForegroundColor Green
    Write-Host "Snippet-Länge: $($snippet.Length) Zeichen"
} else {
    Write-Host "✗ Snippet-Laden fehlgeschlagen" -ForegroundColor Red
}

# Test 2: Mehrere Snippets auflisten
Write-Host "`n2. Teste Snippet-Liste:" -ForegroundColor Yellow
$snippets = Get-VorcePromptSnippets
Write-Host "Gefundene Snippets: $($snippets.Count)"
$snippets | ForEach-Object {
    Write-Host " - $($_.Name): $($_.Content.Length) Zeichen"
}

# Test 3: Snippet-Ersetzung
Write-Host "`n3. Teste Snippet-Ersetzung:" -ForegroundColor Yellow
$testContent = "Dies ist ein Test mit [[SNIPPET:Dashboard-Link-Context]] und weiteren Inhalten."
$replacedContent = Resolve-VorcePromptSnippets -Content $testContent
Write-Host "Original: $testContent"
Write-Host "Ersetzt: $replacedContent"

# Test 4: Prompt mit Snippets und Variablen
Write-Host "`n4. Teste vollständiges Prompt:" -ForegroundColor Yellow
$variables = @{
    JULES_DAILY_LIMIT = 100
    GEMINI_CLI_DAILY_LIMIT = 50
    TARGET_REPOSITORY = "Vorce-Studios/Vorce"
    AUTO_APPROVE = $true
}

$snippetOverrides = @{
    "Dashboard-Link-Context" = "Override-Inhalt für Test"
}

$prompt = Get-VorcePrompt -PromptId "TEST" -MainRun "MAIN-01" -SubRun "SUB-01" -PartRun "PART-01" -Variables $variables -SnippetOverrides $snippetOverrides
Write-Host "Prompt generiert mit Länge: $($prompt.Length) Zeichen"

# Test 5: Token-Effizienz Check
Write-Host "`n5. Teste Token-Effizienz:" -ForegroundColor Yellow

# Analysiere Prompt-Inhalte
$promptsPath = Join-Path $global:VarDir "prompts/runs"
if (Test-Path $promptsPath) {
    $promptFiles = Get-ChildItem -Path $promptsPath -Recurse -Filter "*.md"

    $totalTokens = 0
    $promptFiles | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $tokens = [Math]::Ceiling($content.Length / 4) # Approximation
        $totalTokens += $tokens
        Write-Host "$($_.Name): $tokens Tokens"
    }

    Write-Host "`nGesamtokenanzahl: $totalTokens Tokens" -ForegroundColor Magenta
}

# Test 6: Redundanz-Check
Write-Host "`n6. Teste Redundanz-Check:" -ForegroundColor Yellow

# Suche nach gemeinsamen Inhalten
$commonPhrases = @(
    "Du bist",
    "Deine Aufgabe ist",
    "Du sollst",
    "Bitte",
    "Beachte",
    "Wichtig"
)

$redundancyCount = 0
$commonPhrases | ForEach-Object {
    $phrase = $_
    $matches = 0
    $promptFiles | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match $phrase) {
            $matches++
        }
    }
    if ($matches -gt 1) {
        $redundancyCount += $matches
        Write-Host "Phrase '$phrase' gefunden in $matches Files" -ForegroundColor Yellow
    }
}

Write-Host "Gefundene Redundanzen: $redundancyCount"

# Test 7: Performance-Check
Write-Host "`n7. Teste Performance:" -ForegroundColor Yellow

$startTime = Get-Date
for ($i = 1; $i -le 10; $i++) {
    $null = Get-VorcePrompt -PromptId "TEST" -Variables @{TEST_VAR = "Test$i"}
}
$endTime = Get-Date

$duration = ($endTime - $startTime).TotalMilliseconds
$avgTime = $duration / 10

Write-Host "Durchschnittliche Zeit pro Prompt: $avgTime ms" -ForegroundColor Green

Write-Host "`n=== Test abgeschlossen ===" -ForegroundColor Cyan