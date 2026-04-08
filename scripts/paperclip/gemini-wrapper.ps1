# gemini-wrapper.ps1 - wrapper for Paperclip gemini adapter
# Fixes Gemini CLI v0.36.0 breaking change: positional args now default to interactive mode
# Converts positional prompts to -p flag for non-interactive use
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AllArgs
)

$hasPrompt = $false
$extraArgs = @()
$positionalPrompt = $null

for ($i = 0; $i -lt $AllArgs.Count; $i++) {
    $arg = $AllArgs[$i]
    if ($arg -eq '-p' -or $arg -eq '--prompt') {
        $hasPrompt = $true
        $extraArgs += $arg
        $i++
        if ($i -lt $AllArgs.Count) {
            $extraArgs += $AllArgs[$i]
        }
    }
    elseif ($arg -eq '--output-format') {
        $extraArgs += $arg
        $i++
        if ($i -lt $AllArgs.Count) {
            $extraArgs += $AllArgs[$i]
        }
    }
    elseif (-not $hasPrompt -and $null -eq $positionalPrompt) {
        # First positional arg = prompt, convert to -p
        $positionalPrompt = $arg
        $hasPrompt = $true
    }
    else {
        $extraArgs += $arg
    }
}

# Build final args: if we had a positional prompt, prepend -p
if ($null -ne $positionalPrompt) {
    $finalArgs = @('-p', $positionalPrompt) + $extraArgs
}
else {
    $finalArgs = $extraArgs
}

& gemini @finalArgs
