# src/runs/ROUTER/ROUTER_MAIN-RUN-02_Monitoring.ps1
param([object]$GlobalState, [object]$Config, [object]$MainState)
return @(
    @{ id = "01"; name = "SystemHealthCheck"; script = "src/runs/SUB-RUN/SUB-RUN-01_MR-02_Monitoring__SystemHealthCheck.ps1" },
    @{ id = "02"; name = "LegacyMonitoring"; script = "src/runs/SUB-RUN/SUB-RUN-02_MR-02_Monitoring__LegacyFallback.ps1" }
)
