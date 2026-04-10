@{
    Company = @{
        Name              = 'Vorce-Studios'
        Description       = 'Dynamic local Paperclip control plane for Vorce.'
        InstanceId        = 'vorce-studios'
        PaperclipVersion  = '2026.403.0'
        DeploymentMode    = 'local_trusted'
        ServerPort        = 3144
        DatabasePort      = 5433
        BudgetMonthlyCents = 0
    }

    Project = @{
        Name = 'Vorce Official Release'
        Description = 'Primary Paperclip project for release sequencing, Jules execution, PR review and merge readiness.'
    }

    Supervisor = @{
        TickSeconds = 30
        AgentIntervals = @{
            CEO = 300
            OrderManager = 180
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
        MaxConcurrentBuilderSessions = 1
    }

    Atlas = @{
        EnabledByDefault = $false
        SummaryPath = '.agent/atlas/SUMMARY.md'
        ReadmePath = '.agent/atlas/README.md'
        CodeAtlasPath = '.agent/atlas/code-atlas.json'
    }
}
