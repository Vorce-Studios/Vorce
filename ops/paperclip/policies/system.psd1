@{
    Company = @{
        Name              = 'Vorce-Studios'
        Description       = 'Dynamic local Paperclip control plane for Vorce.'
        InstanceId        = 'vorce-studios'
        PaperclipVersion  = '2026.403.0'
        DeploymentMode    = 'local_trusted'
        ServerPort        = 3140
        DatabasePort      = 55432
        BudgetMonthlyCents = 0
    }

    Project = @{
        Name = 'Vorce Release Train'
        Description = 'Primary local control-plane project for release planning, backlog shaping and execution.'
    }

    Supervisor = @{
        TickSeconds = 30
        AgentIntervals = @{
            ChiefOfStaff = 60
            DiscoveryScout = 900
            JulesBuilder = 60
            ReviewPool = 120
            OpsSteward = 90
            CEO = 600
        }
        MaintenanceIntervals = @{
            GitHubSync = 300
        }
    }

    Runtime = @{
        NativeHeartbeatScheduler = $false
        DefaultMode = 'stopped'
        StopWaitMinutes = 20
        MaxConcurrentReviews = 1
        MaxConcurrentBuilderSessions = 2
    }

    Atlas = @{
        EnabledByDefault = $true
        SummaryPath = '.agent/atlas/SUMMARY.md'
        ReadmePath = '.agent/atlas/README.md'
        CodeAtlasPath = '.agent/atlas/code-atlas.json'
    }
}
