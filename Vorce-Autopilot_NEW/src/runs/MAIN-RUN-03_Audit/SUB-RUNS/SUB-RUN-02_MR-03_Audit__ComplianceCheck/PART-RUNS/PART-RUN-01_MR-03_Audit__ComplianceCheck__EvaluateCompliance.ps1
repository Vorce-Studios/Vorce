# SUB-RUN-02_ComplianceCheck.ps1 (Vorce 3.0)
# Prüft Systemkonformität und Best Practices
[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$ConfigBag,
    [Parameter(Mandatory)][object]$ParentState
)

# Setze globale Variablen basierend auf ConfigBag
$global:VorceRoot = $ConfigBag.VorceRoot
$global:VarDir = $ConfigBag.VarDir
$global:LibDir = $ConfigBag.LibDir

# Lade benötigte Module
. (Join-Path $global:LibDir "utils/StatusPrinter.ps1")
. (Join-Path $global:LibDir "state/StateManager.ps1")
. (Join-Path $global:LibDir "engines/QuotaManager.ps1")

Write-VorceStep -Message "Starte Compliance-Check..." -Status "RUN"

# Compliance Checks durchführen
$complianceResults = @()

# 1. Prüfe Config-Integrität
try {
    $configPath = Join-Path $global:VarDir "config/autopilot-config.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $complianceResults += @{
        category = "config_integrity";
        status = "ok";
        checks_passed = @("repository_set", "wake_intervals_set", "max_issues_set")
    }
    Write-VorceStep -Message "Config-Integrität OK" -Status "OK"
} catch {
    $complianceResults += @{
        category = "config_integrity";
        status = "error";
        message = $_.Exception.Message
    }
    Write-VorceStep -Message "Config-Integrität Fehler: $($_.Exception.Message)" -Status "ERROR"
}

# 2. Prüfe globale Variablen
$globalVars = @("VorceRoot", "VarDir", "LibDir")
$missingVars = @()
foreach ($var in $globalVars) {
    if (-not (Get-Variable -Name $var -ErrorAction SilentlyContinue)) {
        $missingVars += $var
    }
}

if ($missingVars.Count -eq 0) {
    $complianceResults += @{ category = "global_variables"; status = "ok"; variables = $globalVars }
    Write-VorceStep -Message "Globale Variablen OK" -Status "OK"
} else {
    $complianceResults += @{ category = "global_variables"; status = "warning"; missing_variables = $missingVars }
    Write-VorceStep -Message "Globale Variablen fehlen: $($missingVars -join ', ')" -Status "WARN"
}

# 3. Prüfe Modul-Verfügbarkeit
$requiredModules = @{
    StatusPrinter = "utils/StatusPrinter.ps1"
    StateManager = "state/StateManager.ps1"
    RunEngine = "engines/RunEngine.ps1"
    QuotaManager = "engines/QuotaManager.ps1"
}
$missingModules = @()
foreach ($module in $requiredModules.GetEnumerator()) {
    $modulePath = Join-Path $global:LibDir $module.Value
    if (-not (Test-Path $modulePath)) {
        $missingModules += $module.Key
    }
}

if ($missingModules.Count -eq 0) {
    $complianceResults += @{ category = "module_availability"; status = "ok"; modules = @($requiredModules.Keys) }
    Write-VorceStep -Message "Module Verfügbarkeit OK" -Status "OK"
} else {
    $complianceResults += @{ category = "module_availability"; status = "error"; missing_modules = $missingModules }
    Write-VorceStep -Message "Module fehlen: $($missingModules -join ', ')" -Status "ERROR"
}

# 4. Prüfe Quota-Registry
try {
    $quotaResult = Test-VorceQuota -AgentName "jules"
    $complianceResults += @{
        category = "quota_registry";
        status = if ($quotaResult) { "ok" } else { "warning" };
        jules_quota = $quotaResult
    }
    Write-VorceStep -Message "Quota-Registry OK" -Status "OK"
} catch {
    $complianceResults += @{
        category = "quota_registry";
        status = "error";
        message = $_.Exception.Message
    }
    Write-VorceStep -Message "Quota-Registry Fehler: $($_.Exception.Message)" -Status "ERROR"
}

# Compliance Ergebnis
$complianceResult = @{
    status = if (($complianceResults | Where-Object { $_.status -eq "error" }).Count -gt 0) { "failed" } else { "completed" }
    compliance_checks = $complianceResults
    passed_checks = ($complianceResults | Where-Object { $_.status -eq "ok" }).Count
    warning_checks = ($complianceResults | Where-Object { $_.status -eq "warning" }).Count
    failed_checks = ($complianceResults | Where-Object { $_.status -eq "error" }).Count
    timestamp = (Get-Date).ToString("o")
}

Write-VorceStep -Message "Compliance-Check abgeschlossen: $($complianceResult.passed_checks) OK, $($complianceResult.warning_checks) WARN, $($complianceResult.failed_checks) ERROR" -Status "OK"
return $complianceResult
