[CmdletBinding()]
param()

$projectRoot = Split-Path -Parent $PSScriptRoot
$excludedRoots = @(
    (Join-Path $projectRoot 'web/Dashboard/node_modules'),
    (Join-Path $projectRoot 'docs/Planning&Develoment/Archive')
)

$parserErrors = New-Object System.Collections.Generic.List[object]
$parsedFiles = 0

Get-ChildItem -LiteralPath $projectRoot -Recurse -File -Filter '*.ps1' | ForEach-Object {
    $fullPath = $_.FullName
    $excluded = $false
    foreach ($excludedRoot in $excludedRoots) {
        if ($fullPath.StartsWith($excludedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $excluded = $true
            break
        }
    }

    if (-not $excluded) {
        $parsedFiles++
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$errors) | Out-Null

        foreach ($parserError in $errors) {
            $parserErrors.Add([pscustomobject]@{
                file = $fullPath
                line = $parserError.Extent.StartLineNumber
                column = $parserError.Extent.StartColumnNumber
                text = $parserError.Extent.Text
                message = $parserError.Message
            })
        }
    }
}

Write-Host "Gepruefte PowerShell-Dateien: $parsedFiles"

if ($parserErrors.Count -gt 0) {
    Write-Host "Parserfehler gefunden:" -ForegroundColor Red
    $parserErrors | Sort-Object file, line, column | Format-Table -AutoSize
    exit 1
}

Write-Host "Keine Parserfehler gefunden."
