@{
    Mission = 'Vorce als zuverlaessige, performante VJ-Software an die Community ausliefern.'

    Goals = @(
        @{
            Id          = 'G1'
            Title       = 'Stabilitaet und Qualitaet'
            Description = 'Alle kritischen Bugs fixen, Test-Coverage erhoehen, CI/CD zuverlaessig halten.'
            Priority    = 'critical'
            Labels      = @('bug', 'security', 'testing', 'performance')
        }
        @{
            Id          = 'G2'
            Title       = 'Feature-Completion fuer v1.0'
            Description = 'Audio-Backend, Render-Pipeline, Media-Import und UI-Widgets fertigstellen.'
            Priority    = 'high'
            Labels      = @('feature', 'enhancement', 'phase-core')
        }
        @{
            Id          = 'G3'
            Title       = 'Developer Experience'
            Description = 'Build-Zeiten optimieren, Dokumentation aktuell halten, Onboarding vereinfachen.'
            Priority    = 'medium'
            Labels      = @('documentation', 'devex', 'dependencies')
        }
        @{
            Id          = 'G4'
            Title       = 'Community und Release'
            Description = 'Release-Pipeline, Changelog-Automation, Community-Feedback-Loop etablieren.'
            Priority    = 'medium'
            Labels      = @('release', 'ci', 'community')
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
