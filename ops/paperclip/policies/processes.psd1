@{
    Workflows = @{
        FeatureImplementation = @{
            Description = 'Standard-Ablauf fuer neue Features.'
            Steps       = @(
                'discovery_scan',
                'planning_sweep',
                'architecture_review',
                'implementation_dispatch',
                'automated_review',
                'qa_validation',
                'human_gate_if_ui',
                'merge_steward',
                'documentation_update'
            )
        }
        BugFix = @{
            Description = 'Schnellpfad fuer Bug-Fixes.'
            Steps       = @(
                'regression_analysis',
                'implementation_dispatch',
                'test_verification',
                'automated_review',
                'merge_steward'
            )
        }
        ReleasePreparation = @{
            Description = 'Release-Vorbereitung mit Freigabeprozess.'
            Steps       = @(
                'changelog_generation',
                'version_bump',
                'full_test_suite',
                'release_review',
                'ceo_release_approval',
                'release_dispatch'
            )
        }
        PostMortem = @{
            Description = 'Nachbereitung nach Fehlern oder gescheiterten Sessions.'
            Steps       = @(
                'failure_analysis',
                'regression_playbook_update',
                'process_improvement_suggestion'
            )
        }
        ParallelImplementation = @{
            Description = 'Multi-Agent-Missionen ueber antigravity-swarm fuer groessere Aufgaben.'
            Steps       = @(
                'planning_sweep',
                'swarm_preset_selection',
                'swarm_mission_planning',
                'swarm_orchestration',
                'swarm_validation',
                'automated_review',
                'merge_steward'
            )
        }
        SessionMonitoring = @{
            Description = 'Ueberwachung von Jules-Sessions auf Timeouts oder AWAITING_USER_FEEDBACK.'
            Steps       = @(
                'session_heartbeat_check',
                'session_diagnostic',
                'support_comment_dispatch',
                'ops_escalation'
            )
        }
        PullRequestMonitoring = @{
            Description = 'Ueberwachung von PR-Starts, Merge-Konflikten und CI-Zeiten.'
            Steps       = @(
                'pr_status_check',
                'conflict_resolution_check',
                'retry_dispatch',
                'ops_escalation'
            )
        }
    }

    AutoTriggers = @{
        OnMerge      = @('documentation_update')
        OnFailedCI   = @('regression_analysis', 'pr_status_check')
        OnNewRelease = @('changelog_generation')
        WeeklyDigest = @('planning_sweep', 'health_check')
        OnBlockedSession = @('session_diagnostic')
    }

    EscalationRules = @{
        ToCeo   = @('architecture_change', 'release_candidate', 'high_risk_merge', 'conflict_resolution')
        ToReview = @('any_pr', 'dependency_change', 'ci_change')
        ToHuman = @('manual_ui_gate', 'approval_required', 'clarification_needed')
    }
}
