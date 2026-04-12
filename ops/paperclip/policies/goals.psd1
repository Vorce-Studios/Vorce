@{
    Mission = 'Vorce als fehlerfreie, release-faehige und offiziell auslieferbare VJ-Software fertigstellen.'

    Goals = @(
        @{
            Id          = 'R1'
            Title       = 'Release-Faehigkeit herstellen'
            Description = 'Main muss jederzeit mergebar bleiben. Kritische Build-, CI-, Packaging-, Sync- und Control-Plane-Probleme haben Vorrang vor neuen Features.'
            Priority    = 'critical'
            Labels      = @('release', 'ci', 'build', 'paperclip', 'ops')
        }
        @{
            Id          = 'R2'
            Title       = 'Produkt-Korrektheit in Kernpfaden sichern'
            Description = 'Render-, Audio-, Projekt-, Import- und Persistenzfehler zuerst schliessen. Alles, was sichtbare Fehlfunktionen oder Datenverlust verursacht, geht vor.'
            Priority    = 'critical'
            Labels      = @('bug', 'render', 'audio', 'project', 'import', 'persistence')
        }
        @{
            Id          = 'R3'
            Title       = 'Release-kritische Features in Abhaengigkeitsreihenfolge abschliessen'
            Description = 'Nur Features bearbeiten, die fuer den offiziellen Release fehlen und nicht durch offenere Stabilitaetsarbeit blockiert sind.'
            Priority    = 'high'
            Labels      = @('feature', 'enhancement', 'release-critical')
        }
        @{
            Id          = 'R4'
            Title       = 'Issue-zu-PR-Durchsatz mit sauberer Verifikation'
            Description = 'Jedes priorisierte Issue braucht klare Acceptance Criteria, einen Jules- oder Coding-Pfad, Review-Evidence und einen mergebaren PR-Ausgang.'
            Priority    = 'high'
            Labels      = @('workflow', 'review', 'verification', 'jules', 'pr')
        }
        @{
            Id          = 'R5'
            Title       = 'Operator-Overhead und Tokenverbrauch niedrig halten'
            Description = 'Nur notwendige Heartbeats, keine spekulativen Agentenstarts, keine breiten Fan-outs ohne konkreten Hebel.'
            Priority    = 'medium'
            Labels      = @('cost', 'ops', 'automation', 'token-efficiency')
        }
    )

    ReleaseSequence = @(
        @{
            Id          = 'S1'
            Title       = 'Control Plane und Delivery-Zuverlaessigkeit'
            Description = 'Paperclip, GitHub-Issue-Sync, Telegram-Sichtbarkeit, CI, Merge-Gates und lokale Adapter muessen stabil sein, bevor breiter parallel entwickelt wird.'
            GateGoalIds = @('R1', 'R5')
        }
        @{
            Id          = 'S2'
            Title       = 'Kritische Produktfehler und Datenrisiken'
            Description = 'Alle Bugs mit Einfluss auf Render-Ausgabe, Audio, Projektzustand, Import oder Persistenz vorziehen.'
            GateGoalIds = @('R2')
        }
        @{
            Id          = 'S3'
            Title       = 'Release-kritische Kernworkflows'
            Description = 'Nur danach fehlende Kernfeatures fuer den offiziellen Release der eigentlichen Nutzer-Workflows abschliessen.'
            GateGoalIds = @('R3')
        }
        @{
            Id          = 'S4'
            Title       = 'Polish, Dokumentation und offizieller Release'
            Description = 'Erst wenn Stabilitaet und Kernworkflows gruen sind: Packaging, Dokumentation, Release Notes und finale Freigabe.'
            GateGoalIds = @('R1', 'R3', 'R4')
        }
    )

    Prioritization = @{
        BlockerLabels = @('release-blocker', 'critical', 'bug', 'ci', 'build', 'paperclip')
        FeatureLabels = @('feature', 'enhancement', 'release-critical')
        IgnoreLabels  = @('wontfix', 'duplicate', 'question')
        SequenceOrder = @('S1', 'S2', 'S3', 'S4')
    }
}
