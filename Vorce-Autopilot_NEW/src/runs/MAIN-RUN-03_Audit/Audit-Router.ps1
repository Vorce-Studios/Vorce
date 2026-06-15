# Audit-Router.ps1 (Vorce 3.0)
# Dynamisches Routing für MAIN-RUN-03_Audit basierend auf Systemintegrität und Compliance
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$MainState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")

Write-VorceStep -Message "Starte Audit-Routing..." -Status "RUN"

# Definiere die Sub-RUNs (Standard-Liste, einige werden bedingt aktiviert)
$subRuns = @(
    @{ id="01"; name="DataSync"; script="src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-01_MR-03_Audit__DataSync/SUB-RUN-01_MR-03_Audit__DataSync.ps1" },
    @{ id="02"; name="ComplianceCheck"; script="src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-02_MR-03_Audit__ComplianceCheck/SUB-RUN-02_MR-03_Audit__ComplianceCheck.ps1" }
)

# Prüfe ob JulesSupervision aktiviert werden soll
if ($ConfigBag.GlobalState.active_delegations) {
    $julesSessions = @($ConfigBag.GlobalState.active_delegations | Where-Object { $_.delegatedTo -eq "jules" })
    if ($julesSessions.Count -gt 0) {
        $subRuns += @{
            id="03";
            name="JulesSupervision";
            script="src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-03_MR-03_Audit__JulesSupervision/SUB-RUN-03_MR-03_Audit__JulesSupervision.ps1"
        }
        Write-VorceStep -Message "JulesSupervision aktiviert für $($julesSessions.Count) aktive Sessions" -Status "OK"
    }
}

# Prüfe ob AlertDisposition aktiviert werden soll
if ($ConfigBag.GlobalState.PSObject.Properties.Name -contains "alerts" -and $ConfigBag.GlobalState.alerts.Count -gt 0) {
    $subRuns += @{
        id="04";
        name="AlertDisposition";
        script="src/runs/MAIN-RUN-03_Audit/SUB-RUNS/SUB-RUN-04_MR-03_Audit__AlertDisposition/SUB-RUN-04_MR-03_Audit__AlertDisposition.ps1"
    }
    Write-VorceStep -Message "AlertDisposition aktiviert für $($ConfigBag.GlobalState.alerts.Count) aktive Alerts" -Status "OK"
}

# Sortiere die Sub-RUNs nach ID
$subRuns = $subRuns | Sort-Object { [int]$_.id }

Write-VorceStep -Message "Geplante Audit-Sub-RUNs: $($subRuns.Count)" -Status "INFO"
foreach ($sub in $subRuns) {
    Write-VorceStep -Message "  - $($sub.name) (ID: $($sub.id))" -Status "INFO"
}

# Rückgabe: Array von Sub-RUN Definitionen
return $subRuns
