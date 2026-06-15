# CheckAndDoing-Router.ps1 (Vorce 3.0)
# Dynamisches Routing für MAIN-RUN-02_CheckAndDoing basierend auf aktiven Sessions und Status
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

Write-VorceStep -Message "Starte CheckAndDoing-Routing..." -Status "RUN"

# Definiere die Sub-RUNs (Standard-Liste, einige werden bedingt aktiviert)
$subRuns = @(
    @{ id="01"; name="SessionSync"; script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync/SUB-RUN-01_MR-02_CheckAndDoing__SessionSync.ps1" },
    @{ id="06"; name="Housekeeping"; script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping/SUB-RUN-06_MR-02_CheckAndDoing__Housekeeping.ps1" }
)

# Prüfe ob JulesCheck aktiviert werden soll
if ($ConfigBag.GlobalState.active_delegations) {
    $julesSessions = @($ConfigBag.GlobalState.active_delegations | Where-Object { $_.delegatedTo -eq "jules" })
    if ($julesSessions.Count -gt 0) {
        $subRuns += @{
            id="02";
            name="JulesCheck";
            script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck/SUB-RUN-02_MR-02_CheckAndDoing__JulesCheck.ps1"
        }
        Write-VorceStep -Message "JulesCheck aktiviert für $($julesSessions.Count) aktive Sessions" -Status "OK"
    }
}

# Prüfe ob LocalAgentCheck aktiviert werden soll
$processes = Get-Process | Where-Object { $_.ProcessName -match "(claude|gemini|cline)" } -ErrorAction SilentlyContinue
if ($processes.Count -gt 0) {
    $subRuns += @{
        id="03";
        name="LocalAgentCheck";
        script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck/SUB-RUN-03_MR-02_CheckAndDoing__LocalAgentCheck.ps1"
    }
    Write-VorceStep -Message "LocalAgentCheck aktiviert für $($processes.Count) laufende Prozesse" -Status "OK"
}

# Prüfe ob ReviewDispatch aktiviert werden soll
$ghPrResult = if (Get-Command gh -ErrorAction SilentlyContinue) { gh pr list --state open --repo $ConfigBag.Config.repository --json number,isDraft 2>$null } else { $null }
if ($ghPrResult) {
    try {
        $prs = $ghPrResult | ConvertFrom-Json
        if ($prs.Count -gt 0) {
            $subRuns += @{
                id="04";
                name="ReviewDispatch";
                script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch/SUB-RUN-04_MR-02_CheckAndDoing__ReviewDispatch.ps1"
            }
            Write-VorceStep -Message "ReviewDispatch aktiviert für $($prs.Count) PRs im Review-Status" -Status "OK"
        }
    } catch {
        # JSON Parsing fehlgeschlagen, ignoriere
    }
}

# Prüfe ob JulesRefill aktiviert werden soll
if ($ConfigBag.Config.jules.monitoring_refill_enabled) {
    $quotaOK = Test-VorceQuota -AgentName "jules"
    if ($quotaOK) {
        $subRuns += @{
            id="05";
            name="JulesRefill";
            script="src/runs/MAIN-RUN-02_CheckAndDoing/SUB-RUNS/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill/SUB-RUN-05_MR-02_CheckAndDoing__JulesRefill.ps1"
        }
        Write-VorceStep -Message "JulesRefill aktiviert (Quota verfügbar)" -Status "OK"
    } else {
        Write-VorceStep -Message "JulesRefill deaktiviert (Quota erschöpft)" -Status "WARN"
    }
}

# Sortiere die Sub-RUNs nach ID
$subRuns = $subRuns | Sort-Object { [int]$_.id }

Write-VorceStep -Message "Geplante CheckAndDoing-Sub-RUNs: $($subRuns.Count)" -Status "INFO"
foreach ($sub in $subRuns) {
    Write-VorceStep -Message "  - $($sub.name) (ID: $($sub.id))" -Status "INFO"
}

# Rückgabe: Array von Sub-RUN Definitionen
return $subRuns
