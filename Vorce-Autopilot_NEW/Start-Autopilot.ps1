# Start-Autopilot.ps1 (Vorce 3.0)
# Infrastruktur-Bootstrapper fuer Dashboard und Hintergrunddienste
[CmdletBinding()]
param(
    [switch]$NoDashboard,
    [switch]$NoSync
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = $PSScriptRoot
$DashboardDir = Join-Path $ScriptDir "web/Dashboard"
$ToolsDir = Join-Path $ScriptDir "src/tools"
$VarDir = Join-Path $ScriptDir "var"
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction Stop).Source }

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " VORCE 3.0 - INFRASTRUCTURE BOOT" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# 1. Dashboard Health Check / Start
if (-not $NoDashboard.IsPresent) {
    Write-Host "[BOOT] Pruefe Dashboard (Port 5173)..." -ForegroundColor Gray
    
    $isListening = $false
    try {
        $conn = Get-NetTCPConnection -LocalPort 5173 -State Listen -ErrorAction SilentlyContinue
        if ($conn) { $isListening = $true }
    } catch {}

    if ($isListening) {
        Write-Host "[BOOT] Dashboard laeuft bereits." -ForegroundColor Green
    } else {
        Write-Host "[BOOT] Starte Dashboard Web-Server (Vite)..." -ForegroundColor Yellow
        if (-not (Test-Path (Join-Path $DashboardDir "node_modules"))) {
            Write-Host "[BOOT] node_modules fehlen. Fuehre npm install aus..." -ForegroundColor Cyan
            Start-Process npm.cmd -ArgumentList "install", "--silent" -WorkingDirectory $DashboardDir -Wait -NoNewWindow
        }
        
        Start-Process $pwsh -ArgumentList @("-NoProfile", "-Command", "Set-Location -LiteralPath '$DashboardDir'; npm.cmd run dev -- --host 0.0.0.0") -WindowStyle Hidden
        
        Write-Host "[BOOT] Dashboard gestartet (Hintergrund)." -ForegroundColor Green
    }
}

# 2. Sync / Background Tools
if (-not $NoSync.IsPresent) {
    Write-Host "[BOOT] Starte Hintergrund-Dienste..." -ForegroundColor Gray
    $syncScript = Join-Path $ToolsDir "services/sync-service.ps1"
    if (Test-Path $syncScript) {
        $syncListening = Get-NetTCPConnection -LocalPort 5174 -State Listen -ErrorAction SilentlyContinue
        if (-not $syncListening) {
            Start-Process $pwsh -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $syncScript, "-VorceRoot", $ScriptDir) -WindowStyle Hidden
        }
    }
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "[READY] Infrastruktur bereit." -ForegroundColor Cyan
Write-Host "-------------------------------------"
Write-Host "Dashboard: http://localhost:5173"
Write-Host "=====================================" -ForegroundColor Cyan
