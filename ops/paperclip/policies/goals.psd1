@{
    Mission = 'Vorce als stabile, performante und shipping-faehige VJ-Software mit einer verlaesslichen lokalen AI-Kontrollschicht ausliefern.'

    Goals = @(
        @{
            Id          = 'G1'
            Title       = 'Shipping-Blocker und Produktionsfehler beseitigen'
            Description = 'Startup-, FFmpeg-, macOS-, Transport- und Sicherheitsprobleme priorisiert abraeumen, damit Vorce stabil startet, laeuft und validierbar bleibt.'
            Priority    = 'critical'
            Labels      = @('bug', 'security', 'testing', 'stability', 'macos', 'ffmpeg')
        }
        @{
            Id          = 'G2'
            Title       = 'Render-, Media- und IO-Pipeline auf Release-Niveau bringen'
            Description = 'Realtime-Render-Queue, Media-Decoder, Timeline, Cluster-Control, Hue-Transport und Video-IO als belastbare Kernfaehigkeiten fertigstellen.'
            Priority    = 'high'
            Labels      = @('feature', 'enhancement', 'render', 'media', 'io', 'performance')
        }
        @{
            Id          = 'G3'
            Title       = 'Autonome Delivery-Engine und Entwickler-Workflow absichern'
            Description = 'Paperclip, GitHub-Issue-Sync, Telegram, lokale Adapter, Goals, Skills und CI so verdrahten, dass Vorce ohne manuelles Nachpflegen steuerbar bleibt.'
            Priority    = 'medium'
            Labels      = @('paperclip', 'automation', 'ci', 'devex', 'documentation', 'sync')
        }
        @{
            Id          = 'G4'
            Title       = 'Release-Readiness und Plattformreichweite ausbauen'
            Description = 'Professional Video I/O, Multi-Instance-Workflows, Release-Polish, Demos und Community-taugliche Auslieferung fuer die naechsten Vorce-Meilensteine absichern.'
            Priority    = 'medium'
            Labels      = @('release', 'platform', 'video-io', 'cluster', 'community')
        }
    )

    GoalAlignment = @{
        DefaultGoal             = 'G2'
        BugDefaultGoal          = 'G1'
        SecurityDefaultGoal     = 'G1'
        CiCdDefaultGoal         = 'G3'
        DocumentationDefaultGoal = 'G3'
        ReleaseDefaultGoal      = 'G4'
    }
}
