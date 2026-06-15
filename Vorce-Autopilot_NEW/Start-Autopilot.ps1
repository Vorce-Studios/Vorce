# Start-Autopilot.ps1 (Vorce 3.0)
# Infrastruktur-Bootstrapper fuer Dashboard und Hintergrunddienste
[CmdletBinding()]
param(
    [switch]$NoDashboard,
    [switch]$NoSync,
    [switch]$NoAutopilot,
    [switch]$Stop,
    [switch]$Restart,
    [switch]$Visible,
    [switch]$Detach
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$DashboardDir = Join-Path $ScriptDir "web/Dashboard"
$ToolsDir = Join-Path $ScriptDir "src/tools"
$VarDir = Join-Path $ScriptDir "var"
$LogDir = Join-Path $VarDir "log"
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction Stop).Source }
$npm = (Get-Command npm.cmd -CommandType Application -ErrorAction Stop).Source
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Test-HttpHealth {
    param([string]$Uri)

    try {
        $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Test-DashboardHealth {
    return (Test-HttpHealth -Uri "http://localhost:5173/api/health") -and
           (Test-HttpHealth -Uri "http://localhost:5173/")
}

function Wait-DashboardHealth {
    param([int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-DashboardHealth) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-ProcessTree {
    param([Parameter(Mandatory)][int]$ProcessId)

    $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $ProcessId })
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-VorceInfrastructure {
    $stopped = New-Object System.Collections.Generic.HashSet[int]
    $ports = @(5173, 5174)

    foreach ($port in $ports) {
        $listeners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
        foreach ($listener in $listeners) {
            if ([int]$listener.OwningProcess -le 4) {
                Write-Host "[STOP] Port $port wird von System-PID $($listener.OwningProcess) belegt; wird nicht beendet." -ForegroundColor DarkYellow
                continue
            }
            if ($stopped.Add([int]$listener.OwningProcess)) {
                Write-Host "[STOP] Beende Listener auf Port $port (PID $($listener.OwningProcess))..." -ForegroundColor Yellow
                Stop-ProcessTree -ProcessId ([int]$listener.OwningProcess)
            }
        }
    }

    $scriptPatterns = @(
        [regex]::Escape((Join-Path $ScriptDir "autopilot.ps1")),
        [regex]::Escape((Join-Path $ToolsDir "services/sync-service.ps1")),
        [regex]::Escape($DashboardDir)
    )
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $cmd = [string]$_.CommandLine
        $scriptPatterns | Where-Object { $cmd -match $_ }
    })

    foreach ($process in $processes) {
        if ($stopped.Add([int]$process.ProcessId)) {
            Write-Host "[STOP] Beende Vorce-Prozess PID $($process.ProcessId)..." -ForegroundColor Yellow
            Stop-ProcessTree -ProcessId ([int]$process.ProcessId)
        }
    }

    if ($stopped.Count -eq 0) {
        Write-Host "[STOP] Keine laufenden Vorce-Infrastrukturprozesse gefunden." -ForegroundColor Green
    } else {
        Write-Host "[STOP] $($stopped.Count) Prozess(e) beendet." -ForegroundColor Green
    }
}

function Start-VorceProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$StdOut,
        [string]$StdErr
    )

    $startArgs = @{
        FilePath = $FilePath
        ArgumentList = $ArgumentList
        WorkingDirectory = $WorkingDirectory
        PassThru = $true
    }

    if ($Visible.IsPresent) {
        $quotedFile = '"' + $FilePath + '"'
        $quotedArgs = @($ArgumentList | ForEach-Object {
            $arg = [string]$_
            if ($arg -match '[\s&()^=;!+,`~]') {
                '"' + ($arg -replace '"', '\"') + '"'
            } else {
                $arg
            }
        })
        $command = "cd /d `"$WorkingDirectory`" && $quotedFile $($quotedArgs -join ' ')"
        $startArgs.FilePath = "cmd.exe"
        $startArgs.ArgumentList = @("/k", $command)
        $startArgs.WorkingDirectory = $WorkingDirectory
        $startArgs.WindowStyle = "Normal"
    } else {
        $startArgs.WindowStyle = "Hidden"
        if ($StdOut) { $startArgs.RedirectStandardOutput = $StdOut }
        if ($StdErr) { $startArgs.RedirectStandardError = $StdErr }
    }

    return Start-Process @startArgs
}

$managedProcesses = @()

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " VORCE 3.0 - INFRASTRUCTURE BOOT" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

if ($Stop.IsPresent -or $Restart.IsPresent) {
    Stop-VorceInfrastructure
    if (-not $Restart.IsPresent) {
        return
    }
}

# 1. Dashboard Health Check / Start
if (-not $NoDashboard.IsPresent) {
    Write-Host "[BOOT] Pruefe Dashboard (Port 5173)..." -ForegroundColor Gray
    
    $isHealthy = Test-DashboardHealth

    if ($isHealthy) {
        Write-Host "[BOOT] Dashboard laeuft bereits." -ForegroundColor Green
    } else {
        $staleListeners = @(Get-NetTCPConnection -LocalPort 5173 -State Listen -ErrorAction SilentlyContinue)
        foreach ($listener in $staleListeners) {
            Write-Host "[BOOT] Beende fehlerhaften Listener auf Port 5173 (PID $($listener.OwningProcess))..." -ForegroundColor Yellow
            Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
        }

        Write-Host "[BOOT] Starte Dashboard Web-Server (Vite)..." -ForegroundColor Yellow
        if (-not (Test-Path (Join-Path $DashboardDir "node_modules"))) {
            Write-Host "[BOOT] node_modules fehlen. Fuehre npm install aus..." -ForegroundColor Cyan
            Start-Process $npm -ArgumentList "install", "--silent" -WorkingDirectory $DashboardDir -Wait -NoNewWindow
        }

        $dashboardOut = Join-Path $LogDir "dashboard-vite.log"
        $dashboardErr = Join-Path $LogDir "dashboard-vite-error.log"
        $dashboardProcess = Start-VorceProcess `
            -FilePath $npm `
            -ArgumentList @("run", "dev", "--", "--host", "0.0.0.0") `
            -WorkingDirectory $DashboardDir `
            -StdOut $dashboardOut `
            -StdErr $dashboardErr
        $managedProcesses += $dashboardProcess

        if (-not (Wait-DashboardHealth)) {
            $details = if (Test-Path $dashboardErr) { Get-Content $dashboardErr -Raw } else { "Kein Fehlerprotokoll vorhanden." }
            throw "Dashboard wurde nicht gesund gestartet. Details: $details"
        }

        Write-Host "[BOOT] Dashboard gestartet (PID $($dashboardProcess.Id))." -ForegroundColor Green
    }
}

# 2. Sync / Background Tools
if (-not $NoSync.IsPresent) {
    Write-Host "[BOOT] Starte Hintergrund-Dienste..." -ForegroundColor Gray
    $syncScript = Join-Path $ToolsDir "services/sync-service.ps1"
    if (Test-Path $syncScript) {
        $syncListening = Get-NetTCPConnection -LocalPort 5174 -State Listen -ErrorAction SilentlyContinue
        if (-not $syncListening) {
            $syncOut = Join-Path $LogDir "sync-service.log"
            $syncErr = Join-Path $LogDir "sync-service-error.log"
            $syncProcess = Start-VorceProcess `
                -FilePath $pwsh `
                -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $syncScript, "-VorceRoot", $ScriptDir) `
                -WorkingDirectory $ScriptDir `
                -StdOut $syncOut `
                -StdErr $syncErr
            $managedProcesses += $syncProcess
        }
    }
}

# 3. Autopilot Loop
if (-not $NoAutopilot.IsPresent) {
    Write-Host "[BOOT] Pruefe Autopilot Loop..." -ForegroundColor Gray
    $autopilotScript = Join-Path $ScriptDir "autopilot.ps1"
    $existingAutopilot = @(Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -match [regex]::Escape($autopilotScript) -and
            $_.CommandLine -notmatch "-RunOnce"
        })

    if ($existingAutopilot.Count -gt 0) {
        Write-Host "[BOOT] Autopilot Loop laeuft bereits (PID $($existingAutopilot[0].ProcessId))." -ForegroundColor Green
    } else {
        if (-not (Test-Path $autopilotScript)) {
            throw "Autopilot Einstiegspunkt nicht gefunden: $autopilotScript"
        }

        $autopilotOut = Join-Path $LogDir "autopilot-service.log"
        $autopilotErr = Join-Path $LogDir "autopilot-service-error.log"
        $autopilotProcess = Start-VorceProcess `
            -FilePath $pwsh `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $autopilotScript, "-StartupSequence", "-StartupDelaySeconds", "8") `
            -WorkingDirectory $ScriptDir `
            -StdOut $autopilotOut `
            -StdErr $autopilotErr
        $managedProcesses += $autopilotProcess
        Write-Host "[BOOT] Autopilot Loop gestartet (PID $($autopilotProcess.Id))." -ForegroundColor Green
    }
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[READY] Infrastruktur bereit." -ForegroundColor Cyan
Write-Host "-------------------------------------"
Write-Host "Dashboard: http://localhost:5173"
Write-Host "=====================================" -ForegroundColor Cyan

if (-not $Detach.IsPresent) {
    Write-Host "[RUNNING] Infrastruktur-Monitor aktiv. Beenden mit Ctrl+C." -ForegroundColor Green
    while ($true) {
        foreach ($process in $managedProcesses) {
            if ($process.HasExited) {
                throw "Hintergrundprozess PID $($process.Id) wurde unerwartet beendet. Details stehen in $LogDir."
            }
        }
        Start-Sleep -Seconds 2
    }
}
