@{
    Company = @{
        Name              = 'Vorce-Studios'
        Description       = 'Dynamic local Paperclip control plane for Vorce.'
        InstanceId        = 'vorce-studios'
        PaperclipVersion  = '2026.403.0'
        DeploymentMode    = 'local_trusted'
<<<<<<< HEAD
        ServerPort        = 3144
        DatabasePort      = 5433
=======
        ServerPort        = 3140
        DatabasePort      = 55432
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
        BudgetMonthlyCents = 0
    }

    Project = @{
<<<<<<< HEAD
        Name = 'Vorce Official Release'
        Description = 'Primary Paperclip project for release sequencing, Jules execution, PR review and merge readiness.'
=======
        Name = 'Vorce Release Train'
        Description = 'Primary local control-plane project for release planning, backlog shaping and execution.'
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
    }

    Supervisor = @{
        TickSeconds = 30
        AgentIntervals = @{
<<<<<<< HEAD
            CEO = 300
            OrderManager = 180
=======
            ChiefOfStaff = 60
            DiscoveryScout = 900
            LenaAssistant = 120
            JulesBuilder = 60
            AntigravityBuilder = 120
            JulesSessionMonitor = 300
            PrMonitor = 300
            ReviewPool = 120
            OpsSteward = 90
            CEO = 600
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
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
<<<<<<< HEAD
        MaxConcurrentBuilderSessions = 1
    }

    Atlas = @{
        EnabledByDefault = $false
=======
        MaxConcurrentBuilderSessions = 2
    }

    Atlas = @{
        EnabledByDefault = $true
>>>>>>> 985aead14 (chore: restore Paperclip scripts and docs deleted in 4b1c517a5 (regression fix))
        SummaryPath = '.agent/atlas/SUMMARY.md'
        ReadmePath = '.agent/atlas/README.md'
        CodeAtlasPath = '.agent/atlas/code-atlas.json'
    }
}
