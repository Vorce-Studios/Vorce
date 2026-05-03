Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath
. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')
. (Join-Path $ScriptDir 'lib\AfkMode.ps1')

$system = Get-VorceStudiosSystemPolicy
$paths = Get-VorceStudiosPaths
$company = Find-VorceStudiosCompany -Name $system.Company.Name

$state = @{
    timestamp = Get-VorceStudiosTimestamp
    apiBase = Get-VorceStudiosApiBase
    paperclipReady = Test-VorceStudiosPaperclipReady
    boardAccess = Test-VorceStudiosBoardAccess
    serverProcess = Get-VorceStudiosServerProcessInfo
    operationalStatus = (Get-VorceStudiosRuntimeState).mode
}

if ($company) {
    $state['company'] = @{ id = $company.id; name = $company.name; issuePrefix = $company.issuePrefix }
    $dashboard = Get-VorceStudiosDashboard -CompanyId ([string]$company.id)
    $state['dashboard'] = $dashboard
}

$state['atlas'] = Get-VorceStudiosAtlasState
$state
