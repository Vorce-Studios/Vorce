[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

$goals = Get-VorceStudiosPolicy -Name 'goals'
$companyState = Get-VorceStudiosCompanyState

if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    Write-Host 'Fehler: Keine Company gefunden. Bitte zuerst Start-Vorce-Studios.ps1 ausfuehren.' -ForegroundColor Red
    exit 1
}

$companyId = [string]$companyState.company.id
$created = 0

foreach ($goal in $goals.Goals) {
    $id = [string]$goal.Id
    Write-Host "Erstelle Goal $id : $($goal.Title)..." -NoNewline

    try {
        $result = Invoke-VorceStudiosApi -Method POST -Path "/api/companies/$companyId/goals" -Body @{
            id = $id
            title = [string]$goal.Title
            description = [string]$goal.Description
            priority = [string]$goal.Priority
            labels = @($goal.Labels)
        } -IgnoreFailure

        if ($null -ne $result) {
            Write-Host ' OK' -ForegroundColor Green
            $created++
        } else {
            Write-Host ' EXISTIERT' -ForegroundColor Yellow
        }
    } catch {
        if ($_.Exception.Message -match '409|already exists|duplicate') {
            Write-Host ' EXISTIERT' -ForegroundColor Yellow
        } else {
            Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host "$created/$($goals.Goals.Count) Goals neu erstellt." -ForegroundColor Cyan
