@{
    Roles = @{
        ceo            = 'Victor (CEO / Chief Architect)'
        order_manager  = 'Julia (Order Management / Jules & PR Operator)'
        qwen_reviewer  = 'Elias (Reviewer / Coder, Qwen)'
        codex_reviewer = 'Caleb (Reviewer / Coder, Codex)'
    }

    Heartbeats = @{
        EnabledRoles  = @('ceo', 'order_manager')
        DisabledRoles = @('qwen_reviewer', 'codex_reviewer')
        IntervalsSec  = @{
            ceo           = 300
            order_manager = 180
        }
    }

    ReviewRouting = @{
        Qwen = @{
            UseWhen = @(
                'standard-pr-review',
                'regression-scan',
                'test-gap-check',
                'merge-readiness-review'
            )
            RequiresExplicitWakeup = $true
        }
        Codex = @{
            UseWhen = @(
                'high-risk-diff',
                'architecture-change',
                'hard-debugging',
                'release-blocker-review'
            )
            RequiresExplicitWakeup = $true
        }
    }

    ExecutionModel = @{
        CEOOwnsStrategy = $true
        CEOOwnsSequencing = $true
        OrderManagerOwnsJulesFlow = $true
        OrderManagerOwnsPrTracking = $true
        ReviewersOnDemandOnly = $true
        AutoWakeReviewers = $false
    }
}
