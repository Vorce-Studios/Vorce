# src/runs/ROUTER/ROUTER_MAIN-RUN-03_Audit.ps1
param([object]$GlobalState, [object]$Config, [object]$MainState)
return @(
    @{ id = "01"; name = "ConsistencyAudit"; script = "src/runs/SUB-RUN/SUB-RUN-01_MR-03_Audit__ConsistencyAudit.ps1" },
    @{ id = "02"; name = "LegacyAudit"; script = "src/runs/SUB-RUN/SUB-RUN-02_MR-03_Audit__LegacyFallback.ps1" }
)
