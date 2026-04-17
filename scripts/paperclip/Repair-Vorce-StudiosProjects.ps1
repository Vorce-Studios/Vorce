[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ScriptDir = Split-Path -Parent $PSCommandPath

. (Join-Path $ScriptDir 'lib\VorceStudiosConfig.ps1')
. (Join-Path $ScriptDir 'lib\PaperclipApi.ps1')

Ensure-VorceStudiosRuntimeDirectories
Import-VorceStudiosPaperclipEnvironment

$companyState = Get-VorceStudiosCompanyState
if ($null -eq $companyState.company -or [string]::IsNullOrWhiteSpace([string]$companyState.company.id)) {
    throw 'Vorce-Studios ist noch nicht initialisiert.'
}

$projectState = Ensure-VorceStudiosPrimaryProject -CompanyId ([string]$companyState.company.id) -NormalizeIssues
if ($null -ne $projectState.Project) {
    $companyState['project'] = @{
        id = [string]$projectState.Project.id
        name = [string]$projectState.Project.name
    }
    Set-VorceStudiosCompanyState -State $companyState
}

[pscustomobject]@{
    primaryProject = $companyState.project
    duplicateProjects = @($projectState.Duplicates | ForEach-Object {
        [pscustomobject]@{
            id = [string]$_.id
            name = [string]$_.name
        }
    })
    migratedIssueCount = [int]$projectState.MigratedIssueCount
    migratedIssues = @($projectState.MigratedIssues)
}
