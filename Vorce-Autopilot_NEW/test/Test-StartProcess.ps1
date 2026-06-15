# Test-StartProcess.ps1
# param(
#     [string]$PwshPath,
#     [string]$GeminiPs1Path
# )

# Hardcoded paths for isolated testing
$PwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"
$GeminiPs1Path = "C:\Users\Vinyl\AppData\Roaming\npm\gemini.ps1"

Write-Host "--- Starting Test-StartProcess.ps1 ---"
Write-Host "PwshPath: $PwshPath"
Write-Host "GeminiPs1Path: $GeminiPs1Path"

$outputFile = "test_output.txt"
$errorFile = "test_error.txt" # New error file
$promptInputFile = "test_prompt.txt"

Set-Content -Path $promptInputFile -Value "What is 1+1?" -Encoding UTF8

$agentArgs = @("-NoProfile", "-File", $GeminiPs1Path, "--yolo")

Write-Host "FilePath: $PwshPath"
Write-Host "ArgumentList: $($agentArgs -join ' ')"
Write-Host "RedirectStandardOutput: $outputFile"
Write-Host "RedirectStandardError: $errorFile"
Write-Host "RedirectStandardInput: $promptInputFile"

try {
    $process = Start-Process -FilePath $PwshPath -ArgumentList $agentArgs -RedirectStandardOutput $outputFile -RedirectStandardError $errorFile -RedirectStandardInput $promptInputFile -NoNewWindow -Wait -PassThru
    
    if ($null -eq $process) {
        Write-Host "Error: Start-Process returned null process object." -ForegroundColor Red
        exit 1
    }

    if ($process.ExitCode -ne 0) {
        $stdOutContent = if (Test-Path -LiteralPath $outputFile) { Get-Content -LiteralPath $outputFile -Raw -Encoding UTF8 } else { "" }
        $stdErrContent = if (Test-Path -LiteralPath $errorFile) { Get-Content -LiteralPath $errorFile -Raw -Encoding UTF8 } else { "" }
        $combinedOutput = ($stdOutContent, $stdErrContent | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
        Write-Host "Error: Process exited with code $($process.ExitCode). Combined Output: $($combinedOutput | Select-Object -First 200)" -ForegroundColor Red
        exit 1
    }
    
    $stdOutContent = Get-Content -Path $outputFile -Raw -Encoding UTF8
    $stdErrContent = Get-Content -Path $errorFile -Raw -Encoding UTF8
    $output = ($stdOutContent, $stdErrContent | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
    
    Write-Host "Success: Process completed. Output length: $($output.Length)" -ForegroundColor Green
    Write-Host "Output:" -ForegroundColor Green
    Write-Host $output -ForegroundColor Cyan
    exit 0
} catch {
    Write-Host "Catch Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item $outputFile, $errorFile, $promptInputFile -ErrorAction SilentlyContinue
}

Write-Host "--- Test-StartProcess.ps1 Finished ---"
