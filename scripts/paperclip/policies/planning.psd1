@{
    Discovery = @{
        IssueLimit = 120
        ImportLimit = 10
        ReadyStatuses = @('Todo')
    }
    Scoring = @{
        PriorityWeights = @{
            'priority: critical' = 120
            'priority: high' = 90
            'priority: medium' = 55
            'priority: low' = 20
        }
        LabelBonuses = @{
            'bug' = 50
            'security' = 40
            'testing' = 15
            'performance' = 15
            'dependencies' = 20
            'jules-task' = 10
            'Todo-UserISU' = 12
        }
        StatusPenalties = @{
            'status: blocked' = -40
            'status: in-progress' = 35
            'status: needs-review' = 25
        }
        ProjectStatusBonuses = @{
            'Todo' = 15
            'JulesSession' = 20
            'PR-Checks' = 30
            'Review PR' = 35
            'QA Test' = 40
        }
        GoalAlignmentBonuses = @{
            'G1_stability' = 30
            'G2_feature' = 20
            'G3_devex' = 10
            'G4_community' = 10
        }
        DependencyAwareness = @{
            'blocked-by-other-issue' = -25
            'blocks-other-issues' = 15
        }
        AgeStaleness = @{
            DaysOldThreshold = 30
            BonusPerDay = 1
            MaxBonus = 20
        }
    }
    Buckets = @{
        Critical = 120
        High = 80
        Medium = 45
    }
}
