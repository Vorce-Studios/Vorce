$prompt = ""
$cleanArgs = @()
$skipNext = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($skipNext) {
        $skipNext = $false
        continue
    }
    if ($args[$i] -eq '--prompt') {
        $prompt = $args[$i+1]
        $cleanArgs += '--prompt'
        $cleanArgs += '-'
        $skipNext = $true
        continue
    }
    $cleanArgs += $args[$i]
}

if ($prompt) {
    $prompt | gemini.cmd @cleanArgs
} else {
    gemini.cmd @cleanArgs
}
exit $LASTEXITCODE
