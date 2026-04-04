Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'VorceStudiosConfig.ps1')
. (Join-Path $PSScriptRoot 'CapacityLedger.ps1')

function Invoke-VorceStudiosCliPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('gemini', 'qwen', 'codex', 'copilot')][string]$Tool,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory = (Get-VorceStudiosRoot),
        [int]$TimeoutSeconds = 180
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $filePath = $null
        $arguments = @()

        switch ($Tool) {
            'gemini' {
                $filePath = 'gemini'
                $arguments = @('--prompt', $Prompt, '--approval-mode', 'yolo', '--output-format', 'text')
            }
            'qwen' {
                $filePath = 'qwen'
                $arguments = @('--prompt', $Prompt, '--approval-mode', 'yolo', '--output-format', 'text')
            }
            'codex' {
                $filePath = 'codex'
                $arguments = @('exec', $Prompt, '-C', $WorkingDirectory, '--skip-git-repo-check', '-s', 'read-only', '-o', $stdoutPath)
            }
            'copilot' {
                $filePath = 'copilot'
                $arguments = @('-p', $Prompt, '--output-format', 'text')
            }
        }

        if ($Tool -ne 'codex') {
            $process = Start-Process -FilePath $filePath -ArgumentList $arguments -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
        } else {
            $process = Start-Process -FilePath $filePath -ArgumentList $arguments -WorkingDirectory $WorkingDirectory -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
        }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            throw "Timeout nach $TimeoutSeconds Sekunden beim Tool '$Tool'."
        }

        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }

        if ($process.ExitCode -ne 0) {
            if (Test-VorceStudiosQuotaFailureText -Text ($stdout + "`n" + $stderr)) {
                Set-VorceStudiosToolState -Tool $Tool -Status 'quota_exhausted' -Notes 'Quota or rate limit detected.'
            }
            throw ("Tool '{0}' fehlgeschlagen (ExitCode {1}): {2}" -f $Tool, $process.ExitCode, ($stderr.Trim()))
        }

        if (Test-VorceStudiosQuotaFailureText -Text ($stdout + "`n" + $stderr)) {
            Set-VorceStudiosToolState -Tool $Tool -Status 'quota_exhausted' -Notes 'Quota or rate limit detected.'
        }

        if ($null -eq $stdout) { $stdout = '' }
        if ($null -eq $stderr) { $stderr = '' }

        return @{
            tool = $Tool
            stdout = $stdout.Trim()
            stderr = $stderr.Trim()
            exitCode = $process.ExitCode
        }
    } finally {
        foreach ($path in @($stdoutPath, $stderrPath)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Invoke-VorceStudiosReviewPrompt {
    param(
        [Parameter(Mandatory)][string[]]$ToolChain,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$WorkingDirectory = (Get-VorceStudiosRoot)
    )

    $selectedTool = Get-VorceStudiosPreferredTool -Chain $ToolChain
    if ([string]::IsNullOrWhiteSpace($selectedTool)) {
        throw 'Kein verfuegbares Review-Tool in der Fallback-Kette.'
    }

    return Invoke-VorceStudiosCliPrompt -Tool $selectedTool -Prompt $Prompt -WorkingDirectory $WorkingDirectory
}
