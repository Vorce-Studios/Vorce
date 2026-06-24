[CmdletBinding()]
param(
    [ValidateSet('success', 'exit', 'timeout')]
    [string]$Mode = 'success',

    [string]$PromptArgument,
    [string]$PromptFile,
    [string]$CapturePath,
    [string]$StdoutText = 'OK',
    [string]$StderrText = '',
    [switch]$NoStdout,
    [int]$ExitCode = 0,
    [int]$SleepMilliseconds = 0,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

$promptSource = 'stdin'
$prompt = ''
$promptFileExisted = $false

if ($PSBoundParameters.ContainsKey('PromptArgument')) {
    $promptSource = 'argument'
    $prompt = $PromptArgument
} elseif (-not [string]::IsNullOrWhiteSpace($PromptFile)) {
    $promptSource = 'tempfile'
    $promptFileExisted = Test-Path -LiteralPath $PromptFile
    if ($promptFileExisted) {
        $prompt = [System.IO.File]::ReadAllText($PromptFile)
    }
} else {
    $prompt = [Console]::In.ReadToEnd()
}

if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
    $captureDirectory = Split-Path -Parent $CapturePath
    if ($captureDirectory -and -not (Test-Path -LiteralPath $captureDirectory)) {
        $null = New-Item -ItemType Directory -Path $captureDirectory -Force
    }

    [pscustomobject]@{
        mode = $Mode
        prompt_source = $promptSource
        prompt = $prompt
        prompt_file = $PromptFile
        prompt_file_existed = $promptFileExisted
        remaining_arguments = @($RemainingArguments)
        process_id = $PID
    } |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $CapturePath -Encoding UTF8
}

if ($Mode -eq 'timeout') {
    if ($SleepMilliseconds -le 0) { $SleepMilliseconds = 5000 }
    Start-Sleep -Milliseconds $SleepMilliseconds
}

if (-not $NoStdout -and -not [string]::IsNullOrEmpty($StdoutText)) {
    [Console]::Out.Write($StdoutText)
}
if (-not [string]::IsNullOrEmpty($StderrText)) {
    [Console]::Error.Write($StderrText)
}

if ($Mode -eq 'exit' -and $ExitCode -eq 0) {
    $ExitCode = 1
}
exit $ExitCode
