# GitHubClient.ps1 (Vorce 3.0)
# Central, shell-free GitHub CLI transport and data access helpers.

function ConvertTo-VorceNativeArgument {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($null -eq $Argument) {
        $Argument = ''
    }

    # ProcessStartInfo.Arguments is required on Windows PowerShell 5.1.
    # This is Windows native argv quoting, not a shell command string.
    $builder = New-Object System.Text.StringBuilder
    $null = $builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                $null = $builder.Append(('\' * ($backslashCount * 2)))
                $backslashCount = 0
            }
            $null = $builder.Append('\"')
            continue
        }

        if ($backslashCount -gt 0) {
            $null = $builder.Append(('\' * $backslashCount))
            $backslashCount = 0
        }
        $null = $builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        $null = $builder.Append(('\' * ($backslashCount * 2)))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Resolve-VorceGitHubExecutable {
    [CmdletBinding()]
    param(
        [string]$ExecutablePath
    )

    $candidate = if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { 'gh' } else { $ExecutablePath }
    if ([System.IO.Path]::IsPathRooted($candidate)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
        return $null
    }

    $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }
    return $null
}

function New-VorceGitHubCommandResult {
    [CmdletBinding()]
    param(
        [string]$CommandPath,
        [string[]]$Arguments,
        [Nullable[int]]$ExitCode,
        [string]$StdOut = '',
        [string]$StdErr = '',
        [bool]$TimedOut = $false,
        [bool]$Started = $false,
        [string]$ErrorClass,
        [int]$TimeoutSeconds,
        [long]$DurationMs = 0
    )

    return [pscustomobject][ordered]@{
        CommandPath = $CommandPath
        Arguments = @($Arguments)
        ExitCode = if ($null -ne $ExitCode) { [int]$ExitCode } else { $null }
        StdOut = [string]$StdOut
        StdErr = [string]$StdErr
        Timeout = [bool]$TimedOut
        TimedOut = [bool]$TimedOut
        TimeoutSeconds = [int]$TimeoutSeconds
        Started = [bool]$Started
        Succeeded = (
            $Started -and
            -not $TimedOut -and
            $null -ne $ExitCode -and
            [int]$ExitCode -eq 0
        )
        ErrorClass = $ErrorClass
        DurationMs = [long]$DurationMs
    }
}

function Invoke-VorceGitHubCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 30,

        [string]$ExecutablePath,

        [string[]]$ArgumentPrefix = @(),

        [string]$WorkingDirectory = (Get-Location).ProviderPath
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $resolvedExecutable = Resolve-VorceGitHubExecutable -ExecutablePath $ExecutablePath
    if (-not $resolvedExecutable) {
        $stopwatch.Stop()
        return New-VorceGitHubCommandResult `
            -CommandPath $ExecutablePath `
            -Arguments $Arguments `
            -ExitCode $null `
            -StdErr "GitHub CLI executable not found: $(if ($ExecutablePath) { $ExecutablePath } else { 'gh' })" `
            -ErrorClass 'command_not_found' `
            -TimeoutSeconds $TimeoutSeconds `
            -DurationMs $stopwatch.ElapsedMilliseconds
    }

    $processArguments = @($ArgumentPrefix) + @($Arguments)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedExecutable
    $startInfo.WorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    if ($null -ne $startInfo.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $processArguments) {
            $startInfo.ArgumentList.Add([string]$argument)
        }
    } else {
        $quotedArguments = @($processArguments | ForEach-Object {
            ConvertTo-VorceNativeArgument -Argument ([string]$_)
        })
        $startInfo.Arguments = $quotedArguments -join ' '
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false

    try {
        $started = $process.Start()
        if (-not $started) {
            throw "Process.Start returned false for '$resolvedExecutable'."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        $timedOut = -not $completed

        if ($timedOut) {
            try {
                $process.Kill()
            } catch {
            }
        }

        $process.WaitForExit()
        $stdOut = $stdoutTask.Result
        $stdErr = $stderrTask.Result
        $exitCode = $process.ExitCode
        $stopwatch.Stop()

        $errorClass = $null
        if ($timedOut) {
            $errorClass = 'timeout'
        } elseif ($exitCode -ne 0) {
            $diagnosticText = "$stdErr`n$stdOut"
            if ($diagnosticText -match '(?i)(authentication|not logged in|auth login|GH_TOKEN|GITHUB_TOKEN|HTTP 401|bad credentials)') {
                $errorClass = 'auth_failed'
            } else {
                $errorClass = 'command_failed'
            }
        }

        return New-VorceGitHubCommandResult `
            -CommandPath $resolvedExecutable `
            -Arguments $Arguments `
            -ExitCode $exitCode `
            -StdOut $stdOut `
            -StdErr $stdErr `
            -TimedOut $timedOut `
            -Started $true `
            -ErrorClass $errorClass `
            -TimeoutSeconds $TimeoutSeconds `
            -DurationMs $stopwatch.ElapsedMilliseconds
    } catch {
        $stopwatch.Stop()
        return New-VorceGitHubCommandResult `
            -CommandPath $resolvedExecutable `
            -Arguments $Arguments `
            -ExitCode $null `
            -StdErr $_.Exception.Message `
            -Started $started `
            -ErrorClass 'start_failed' `
            -TimeoutSeconds $TimeoutSeconds `
            -DurationMs $stopwatch.ElapsedMilliseconds
    } finally {
        $process.Dispose()
    }
}

function Get-VorceGitHubCommandDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )

    $detail = if (-not [string]::IsNullOrWhiteSpace([string]$Result.StdErr)) {
        [string]$Result.StdErr
    } else {
        [string]$Result.StdOut
    }
    return "class=$($Result.ErrorClass), exit=$($Result.ExitCode), timeout=$($Result.TimedOut): $($detail.Trim())"
}

function ConvertFrom-VorceGitHubJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CommandResult
    )

    if (-not $CommandResult.Succeeded) {
        throw (Get-VorceGitHubCommandDiagnostic -Result $CommandResult)
    }
    if ([string]::IsNullOrWhiteSpace([string]$CommandResult.StdOut)) {
        return $null
    }
    return $CommandResult.StdOut | ConvertFrom-Json
}

function Get-VorceGitHubIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [ValidateRange(1, 1000)]
        [int]$Limit = 100
    )

    Write-VorceStep -Message "Lade Issues fuer $Repository (Limit: $Limit)..." -Status "RUN"

    try {
        $result = Invoke-VorceGitHubCommand -Arguments @(
            'issue', 'list',
            '--repo', $Repository,
            '--state', 'open',
            '--json', 'number,title,labels,assignees,body,state,updatedAt',
            '--limit', [string]$Limit
        )
        $issues = ConvertFrom-VorceGitHubJson -CommandResult $result
        if ($null -eq $issues) {
            Write-VorceStep -Message "GitHub Issues sind leer - speichere leeres Array" -Status "WARN"
            return @()
        }
    } catch {
        Write-VorceStep -Message "GitHub Issue-Abruf fehlgeschlagen: $($_.Exception.Message)" -Status "ERROR"
        return @()
    }

    Write-VorceStep -Message "$(@($issues).Count) Issues erfolgreich geladen." -Status "OK"
    return @($issues)
}

function Get-VorceGitHubPRs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [ValidateRange(1, 1000)]
        [int]$Limit = 50,

        [string]$JsonFields = 'number,title,headRefName,baseRefName,mergeable,statusCheckRollup,isDraft,url,updatedAt'
    )

    Write-VorceStep -Message "Lade Pull Requests fuer $Repository..." -Status "RUN"

    try {
        $result = Invoke-VorceGitHubCommand -Arguments @(
            'pr', 'list',
            '--repo', $Repository,
            '--state', 'open',
            '--json', $JsonFields,
            '--limit', [string]$Limit
        )
        $pullRequests = ConvertFrom-VorceGitHubJson -CommandResult $result
        if ($null -eq $pullRequests) {
            Write-VorceStep -Message "GitHub PRs sind leer - speichere leeres Array" -Status "WARN"
            return @()
        }
    } catch {
        Write-VorceStep -Message "GitHub PR-Abruf fehlgeschlagen: $($_.Exception.Message)" -Status "ERROR"
        return @()
    }

    Write-VorceStep -Message "$(@($pullRequests).Count) Pull Requests erfolgreich geladen." -Status "OK"
    return @($pullRequests)
}

function Save-VorceGitHubData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('issues', 'prs')]
        [string]$Type,

        [AllowNull()]
        [object]$Data
    )

    if ($null -eq $Data) {
        Write-VorceStep -Message "GitHub $Type ist null, speichere leeres Array" -Status "WARN"
        $Data = @()
    }

    $fileName = if ($Type -eq 'issues') { 'github-issues.json' } else { 'pull-requests.json' }
    $dbDir = Join-Path $global:VarDir 'db'
    if (-not (Test-Path -LiteralPath $dbDir)) {
        $null = New-Item -ItemType Directory -Path $dbDir -Force
    }

    $filePath = Join-Path $dbDir $fileName
    $Data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $filePath -Encoding UTF8
    Write-VorceStep -Message "GitHub $Type in Datenbank gesichert: $fileName (Anzahl: $(@($Data).Count))" -Status "OK"
}
