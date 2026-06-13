# Vorce-Autopilot/src/lib/autopilot-session-manager.ps1
# Coordinates autonomous Codex planning/monitoring sessions.

Set-StrictMode -Version Latest

$script:ScriptRoot = Resolve-Path (Join-Path $PSScriptRoot "../..")
$script:VarDbDir = Join-Path $script:ScriptRoot "var/db"
$script:VarLogDir = Join-Path $script:ScriptRoot "var/log"
$script:VarRunDir = Join-Path $script:ScriptRoot "var/runtime"

$script:AutopilotTaskJournalPath = Join-Path $script:VarDbDir "autopilot-tasks.md"
$script:AutopilotSessionLockPath = Join-Path $script:VarDbDir "autopilot-session-lock.md"
$script:AutopilotTmpDir = Join-Path $script:VarDbDir "tmp"
$script:AutopilotToolsDir = Join-Path $script:ScriptRoot "tools"

# Ensure all var folders exist
foreach ($dir in @($script:VarDbDir, $script:VarLogDir, $script:VarRunDir, $script:AutopilotTmpDir)) {
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-AutopilotTaskJournalPath { return $script:AutopilotTaskJournalPath }
function Get-AutopilotSessionLockPath { return $script:AutopilotSessionLockPath }

function Initialize-AutopilotTaskJournal {
    if (Test-Path $script:AutopilotTaskJournalPath) { return }

    $content = @"
# Vorce Autopilot Task Journal

This file is the shared handoff state for autonomous Codex planning and monitoring sessions.

## Current Tasks
- _No tasks recorded yet._

## Active Delegations
- _No active delegations recorded yet._

## Monitoring Notes
- _No monitoring notes recorded yet._

## Decisions / Escalations
- _No decisions recorded yet._

## Session Log
- $(Get-Date -Format o) - Journal initialized.
"@
    Set-Content -Path $script:AutopilotTaskJournalPath -Value $content -Encoding UTF8
}

function Add-AutopilotJournalEvent {
    param(
        [Parameter(Mandatory)][string]$SessionType,
        [Parameter(Mandatory)][string]$Message
    )

    Initialize-AutopilotTaskJournal
    $entry = "- {0} - **{1}**: {2}" -f (Get-Date -Format o), $SessionType, $Message
    Add-Content -Path $script:AutopilotTaskJournalPath -Value $entry -Encoding UTF8
}

function Write-AutopilotSessionLock {
    param(
        [Parameter(Mandatory)][string]$Status,
        [string]$SessionType = "",
        [string]$Owner = "",
        [int]$TtlMinutes = 90
    )

    $now = Get-Date
    $content = @"
# Vorce Autopilot Session Lock

status: $Status
session_type: $SessionType
owner: $Owner
pid: $PID
started_at: $($now.ToString("o"))
expires_at: $($now.AddMinutes($TtlMinutes).ToString("o"))

This file prevents overlapping autonomous Codex sessions.
"@
    Set-Content -Path $script:AutopilotSessionLockPath -Value $content -Encoding UTF8
}

function Read-AutopilotSessionLock {
    if (-not (Test-Path $script:AutopilotSessionLockPath)) { return $null }

    $data = [ordered]@{}
    foreach ($line in (Get-Content -Path $script:AutopilotSessionLockPath -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*([a-z_]+):\s*(.*)\s*$') {
            $data[$Matches[1]] = $Matches[2]
        }
    }
    return [pscustomobject]$data
}

function Test-AutopilotSessionLockAvailable {
    $lock = Read-AutopilotSessionLock
    if ($null -eq $lock) { return $true }
    if (-not ($lock.PSObject.Properties.Name -contains "status") -or [string]$lock.status -ne "running") { return $true }

    $expiresAt = [datetimeoffset]::MinValue
    if (($lock.PSObject.Properties.Name -contains "expires_at") -and [datetimeoffset]::TryParse([string]$lock.expires_at, [ref]$expiresAt)) {
        if ($expiresAt.LocalDateTime -le (Get-Date)) { return $true }
    }

    if ($lock.PSObject.Properties.Name -contains "pid") {
        $lockPid = 0
        if ([int]::TryParse([string]$lock.pid, [ref]$lockPid) -and $lockPid -gt 0) {
            if ($null -eq (Get-Process -Id $lockPid -ErrorAction SilentlyContinue)) { return $true }
        }
    }

    return $false
}

function Clear-AutopilotSessionLock {
    Write-AutopilotSessionLock -Status "idle" -SessionType "" -Owner "" -TtlMinutes 1
}

function Get-LatestCodexSessionFile {
    $root = Join-Path $HOME ".codex\sessions"
    if (-not (Test-Path $root)) { return $null }
    return Get-ChildItem -Path $root -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-CodexSessionIdFromPath {
    param([Parameter(Mandatory)][string]$Path)

    $leaf = Split-Path -Leaf $Path
    if ($leaf -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
        return $Matches[1]
    }
    return $null
}

function Find-CodexSessionFileByMarker {
    param(
        [Parameter(Mandatory)][string]$Marker,
        [Parameter(Mandatory)][datetime]$Since
    )

    $root = Join-Path $HOME ".codex\sessions"
    if (-not (Test-Path $root)) { return $null }

    $candidates = @(Get-ChildItem -Path $root -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Since.AddMinutes(-1) } |
        Sort-Object LastWriteTimeUtc -Descending)

    foreach ($file in $candidates) {
        try {
            if (Select-String -Path $file.FullName -Pattern $Marker -SimpleMatch -Quiet -ErrorAction SilentlyContinue) {
                return $file
            }
        } catch {
            continue
        }
    }

    return $null
}

function Resolve-AutopilotPowerShellHost {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return (Get-Command powershell -ErrorAction Stop).Source
}

function Write-AutopilotCodexStatus {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$SessionType,
        [string]$Model = "",
        [int]$ProcessId = 0,
        [string]$Message = ""
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [ordered]@{
        schema_version = 1
        status         = $Status
        session_type   = $SessionType
        model          = $Model
        pid            = $ProcessId
        message        = $Message
        updated_at     = (Get-Date -Format o)
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Read-AutopilotCodexStatus {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

function Get-ProcessTreeIds {
    param([Parameter(Mandatory)][int]$RootProcessId)

    $ids = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootProcessId)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($ids.Contains($current)) { continue }
        $ids.Add($current)

        $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { [int]$_.ParentProcessId -eq $current })
        foreach ($child in $children) {
            $queue.Enqueue([int]$child.ProcessId)
        }
    }

    return @($ids)
}

function Stop-ProcessTree {
    param([Parameter(Mandatory)][int]$RootProcessId)

    $ids = @(Get-ProcessTreeIds -RootProcessId $RootProcessId | Sort-Object -Descending)
    foreach ($id in $ids) {
        try {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Add-AutopilotStatusInstructions {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$StatusPath,
        [Parameter(Mandatory)][string]$SessionType
    )

    return @"
$Prompt

Pflicht am Ende dieser $SessionType-Session:
Nachdem du das Task-Journal vollstaendig aktualisiert hast und bevor du aufhoerst, schreibe folgenden JSON-Status nach:
$StatusPath

Inhalt:
{
  "schema_version": 1,
  "status": "completed",
  "session_type": "$SessionType",
  "message": "Task journal updated",
  "updated_at": "<ISO-8601 timestamp>"
}

Erst danach ist diese Session fuer den Autopilot beendet.
"@.Trim()
}

function Invoke-AutopilotCodexSession {
    param(
        [Parameter(Mandatory)][string]$SessionType,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][object]$State,
        [string]$Model = "gpt-5.4-mini",
        [switch]$ResumeMainSession,
        [switch]$VisibleTerminal,
        [switch]$VisibleExecTerminal,
        [switch]$DryRun
    )

    # Prepend dynamic memories depending on SessionType to reduce token usage
    if (Get-Command Format-MemoryBlock -ErrorAction SilentlyContinue) {
        $memoryBlock = Format-MemoryBlock -TaskType $SessionType
        if (-not [string]::IsNullOrWhiteSpace($memoryBlock)) {
            $Prompt = "$memoryBlock`n$Prompt"
        }
    }

    Initialize-AutopilotTaskJournal
    if (-not (Test-AutopilotSessionLockAvailable)) {
        Add-AutopilotJournalEvent -SessionType $SessionType -Message "Skipped Codex session because another session is still running."
        return [pscustomobject]@{ Success = $false; Skipped = $true; Reason = "LOCKED" }
    }

    if ($DryRun.IsPresent) {
        Add-AutopilotJournalEvent -SessionType $SessionType -Message "DRY RUN: would start Codex $SessionType session with model $Model."
        return [pscustomobject]@{ Success = $true; Skipped = $false; DryRun = $true }
    }

    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Add-AutopilotJournalEvent -SessionType $SessionType -Message "Codex CLI is not available."
        return [pscustomobject]@{ Success = $false; Skipped = $false; Reason = "NO_CODEX" }
    }

    $owner = "autopilot-$SessionType"
    Write-AutopilotSessionLock -Status "running" -SessionType $SessionType -Owner $owner -TtlMinutes 90
    Add-AutopilotJournalEvent -SessionType $SessionType -Message "Starting Codex $SessionType session with model $Model."

    $outputPath = Join-Path $script:AutopilotTmpDir ("codex-{0}-last-message.md" -f $SessionType)
    $promptPath = Join-Path $script:AutopilotTmpDir ("codex-{0}-prompt.md" -f $SessionType)
    $logPath = Join-Path $script:AutopilotTmpDir ("codex-{0}-visible.log" -f $SessionType)
    $statusPath = Join-Path $script:AutopilotTmpDir ("codex-{0}-status.json" -f $SessionType)
    $latestBefore = Get-LatestCodexSessionFile
    $startedAt = Get-Date
    $args = @("exec", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--output-last-message", $outputPath, "-")

    if ($ResumeMainSession.IsPresent -and ($State.PSObject.Properties.Name -contains "codex_main_session_id") -and -not [string]::IsNullOrWhiteSpace([string]$State.codex_main_session_id)) {
        $args = @("exec", "resume", "--model", $Model, "--dangerously-bypass-approvals-and-sandbox", "--output-last-message", $outputPath, [string]$State.codex_main_session_id, "-")
    }

    try {
        if ($VisibleTerminal.IsPresent -or $VisibleExecTerminal.IsPresent) {
            $isInteractiveVisible = $VisibleTerminal.IsPresent -and -not $VisibleExecTerminal.IsPresent
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
            Write-AutopilotCodexStatus -Path $statusPath -Status "starting" -SessionType $SessionType -Model $Model -Message "Preparing visible Codex session."
            if ($isInteractiveVisible) {
                $visiblePrompt = Add-AutopilotStatusInstructions -Prompt $Prompt -StatusPath $statusPath -SessionType $SessionType
            } else {
                $visiblePrompt = $Prompt
            }
            Set-Content -Path $promptPath -Value $visiblePrompt -Encoding UTF8
            $runnerPath = Join-Path $script:AutopilotToolsDir "run-visible-codex-session.ps1"
            if (-not (Test-Path -LiteralPath $runnerPath)) {
                throw "Visible Codex runner not found: $runnerPath"
            }

            $powerShellHost = Resolve-AutopilotPowerShellHost
            $runnerArgs = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $runnerPath,
                "-PromptPath", $promptPath,
                "-Model", $Model,
                "-RepositoryRoot", (Resolve-Path (Join-Path $script:ScriptRoot "..")),
                "-LogPath", $logPath,
                "-StatusPath", $statusPath
            )
            if (-not [string]::IsNullOrWhiteSpace($outputPath)) {
                $runnerArgs += @("-OutputPath", $outputPath)
            }

            if ($ResumeMainSession.IsPresent -and ($State.PSObject.Properties.Name -contains "codex_main_session_id") -and -not [string]::IsNullOrWhiteSpace([string]$State.codex_main_session_id)) {
                $runnerArgs += @("-SessionId", [string]$State.codex_main_session_id)
            }
            if ($VisibleExecTerminal.IsPresent) {
                $runnerArgs += "-NonInteractiveExec"
            }
            $runnerArgs += @("-SessionLabel", $SessionType)

            Add-AutopilotJournalEvent -SessionType $SessionType -Message "Opened visible Codex terminal for $SessionType session. Log: $logPath"
            $process = Start-Process -FilePath $powerShellHost -ArgumentList $runnerArgs -WindowStyle Normal -PassThru
            if ($isInteractiveVisible) {
                Write-AutopilotCodexStatus -Path $statusPath -Status "running" -SessionType $SessionType -Model $Model -ProcessId $process.Id -Message "Visible Codex session is running."
            }
            Write-Host "[CODEX] Sichtbare $SessionType-Session gestartet. PID=$($process.Id) Log=$logPath" -ForegroundColor Green

            $statusCompleted = $false
            while (-not $process.HasExited) {
                Start-Sleep -Seconds $(if ($isInteractiveVisible) { 30 } else { 2 })
                $process.Refresh()
                if ($isInteractiveVisible) {
                    $status = Read-AutopilotCodexStatus -Path $statusPath
                    if ($null -ne $status -and [string]$status.status -eq "completed") {
                        $statusCompleted = $true
                        Write-Host "[CODEX] $SessionType-Status completed erkannt. Schliesse sichtbares Codex-Fenster. PID=$($process.Id)" -ForegroundColor Green
                        Add-AutopilotJournalEvent -SessionType $SessionType -Message "Status completed detected; closing visible Codex terminal PID $($process.Id)."
                        Stop-ProcessTree -RootProcessId $process.Id
                        break
                    }
                }
            }

            try { $process.WaitForExit(5000) | Out-Null } catch { }
            $exitCode = if ($statusCompleted) { 0 } else { $process.ExitCode }
            Write-Host "[CODEX] Sichtbare $SessionType-Session beendet. ExitCode=$exitCode" -ForegroundColor $(if ($exitCode -eq 0) { "Green" } else { "Red" })
            if (-not $isInteractiveVisible) {
                $statusValue = if ($exitCode -eq 0) { "completed" } else { "failed" }
                Write-AutopilotCodexStatus -Path $statusPath -Status $statusValue -SessionType $SessionType -Model $Model -ProcessId $process.Id -Message "Visible Codex exec session exited with code $exitCode."
            }
            $output = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 } else { "" }
        } else {
            Write-Host "[CODEX] Headless $SessionType-Session gestartet. Model=$Model" -ForegroundColor Green
            $output = $Prompt | & codex @args 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }

        if ($ResumeMainSession.IsPresent -and (-not ($State.PSObject.Properties.Name -contains "codex_main_session_id") -or [string]::IsNullOrWhiteSpace([string]$State.codex_main_session_id))) {
            $latestAfter = Find-CodexSessionFileByMarker -Marker "VORCE_AUTOPILOT_MAIN_PLANNING_SESSION" -Since $startedAt
            if ($null -eq $latestAfter) {
                $latestAfter = Get-LatestCodexSessionFile
            }
            if ($latestAfter -and ($null -eq $latestBefore -or $latestAfter.FullName -ne $latestBefore.FullName -or $latestAfter.LastWriteTime -ge $startedAt)) {
                $sessionId = Get-CodexSessionIdFromPath -Path $latestAfter.FullName
                if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
                    $State | Add-Member -MemberType NoteProperty -Name "codex_main_session_id" -Value $sessionId -Force
                    Save-AutopilotState -State $State
                    Add-AutopilotJournalEvent -SessionType $SessionType -Message "Recorded Codex main session id $sessionId."
                }
            }
        }

        if ($exitCode -eq 0) {
            Write-Host "[CODEX] $SessionType-Session erfolgreich beendet. LastMessage=$outputPath" -ForegroundColor Green
            Add-AutopilotJournalEvent -SessionType $SessionType -Message "Codex session completed. Last message: $outputPath"
        } else {
            $outputLines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $relevantLines = @($outputLines | Where-Object { $_ -match '(?i)\b(error|failed|failure|limit|quota|exceeded|exception|denied)\b' })
            $displayLines = if ($relevantLines.Count -gt 0) { @($relevantLines | Select-Object -Last 6) } else { @($outputLines | Select-Object -Last 12) }
            $trimmedOutput = (($displayLines -join " | ") -replace '\s+', ' ').Trim()
            if ($trimmedOutput.Length -gt 1500) { $trimmedOutput = "..." + $trimmedOutput.Substring($trimmedOutput.Length - 1500) }
            Write-Host "[CODEX] $SessionType-Session FEHLER. ExitCode=$exitCode" -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($trimmedOutput)) {
                Write-Host "[CODEX] Fehlerausgabe: $trimmedOutput" -ForegroundColor Red
            }
            Add-AutopilotJournalEvent -SessionType $SessionType -Message "Codex session failed with exit code $exitCode. Output: $($output.Trim())"
        }

        return [pscustomobject]@{
            Success = ($exitCode -eq 0)
            Skipped = $false
            ExitCode = $exitCode
            OutputPath = $outputPath
            Output = $output
        }
    } catch {
        Add-AutopilotJournalEvent -SessionType $SessionType -Message "Codex session threw: $($_.Exception.Message)"
        return [pscustomobject]@{ Success = $false; Skipped = $false; Reason = $_.Exception.Message }
    } finally {
        Clear-AutopilotSessionLock
    }
}
