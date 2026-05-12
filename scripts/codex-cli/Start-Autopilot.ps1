# scripts/codex-cli/Start-Autopilot.ps1
# Zentrales Start-Skript für den Vorce Autopilot

$ScriptDir = $PSScriptRoot
$DashboardDir = Join-Path $ScriptDir "dashboard"

Write-Host "=====================================" -ForegroundColor Green
Write-Host " STARTE VORCE AUTOPILOT SUITE" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green

# 1. Dashboard-Server im Hintergrund starten
Write-Host "[INIT] Starte Dashboard Web-Server (Vite)..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$DashboardDir'; npm run dev" -WindowStyle Hidden

# 2. Sync-Prozess im Hintergrund starten
Write-Host "[INIT] Starte Dashboard-Sync Service..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-File", (Join-Path $ScriptDir "phases\interval-stats.ps1") -WindowStyle Hidden

# 3. Autopilot-Backend im Vordergrund starten (Interactive)
Write-Host "[INIT] Starte Autopilot Backend (Foreground)..." -ForegroundColor Cyan
Write-Host "Du kannst hier bei Bedarf mit Codex interagieren." -ForegroundColor Yellow
Write-Host "-------------------------------------"
Write-Host "[READY] Dashboard verfügbar unter: http://localhost:5173" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

& (Join-Path $ScriptDir "autopilot.ps1") @args
