# SUB-RUN-01_DataSync.ps1 (Vorce 3.0)
# Synchronisiert GitHub Daten (Issues, PRs)
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir
$ScriptDir = $PSScriptRoot

# BENÖTIGTE MODULE LADEN (via $global:LibDir)
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "integrations/GitHubClient.ps1")
. (Join-Path $global:LibDir "engines/RunEngine.ps1")

Write-VorceStep -Message "Starte DataSync..." -Status "RUN"

# PART-RUNs definieren (Pfade relativ zu $global:VorceRoot)
$PartRuns = @(
    @{
        name="FetchIssues";
        script=(Join-Path $ScriptDir "PART-RUNS/PART-RUN-01_MR-01_Planning__DataSync__FetchIssues.ps1")
    },
    @{
        name="FetchPRs";
        script=(Join-Path $ScriptDir "PART-RUNS/PART-RUN-02_MR-01_Planning__DataSync__FetchPRs.ps1")
    }
)

# Invoke-VorceSubRunParallel aufrufen
$Result = if ($ConfigBag.DryRun) {
    @{ sub_run = "DataSync"; status = "dry_run"; parts = @($PartRuns.name); timestamp = (Get-Date).ToString("o") }
} else {
    Invoke-VorceSubRunParallel -SubRunName "DataSync" -PartRuns $PartRuns -ConfigBag $ConfigBag -MaxParallel 2
}

Write-VorceStep -Message "DataSync abgeschlossen." -Status "OK"
return $Result
