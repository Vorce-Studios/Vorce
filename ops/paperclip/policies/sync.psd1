@{
    GitHub = @{
        Repository = 'Vorce-Studios/Vorce'
        ProjectOwner = 'Vorce-Studios'
        ProjectNumber = 1
        SourceOfTruth = 'github'
        Plugin = @{
            GitHubIssuesId = 'paperclip-plugin-github-issues'
            TelegramId = 'paperclip-plugin-telegram'
        }
        Labels = @{
            Ensure = @(
                @{ Name = 'sync: paperclip'; Color = '1d76db'; Description = 'Managed by Vorce-Studios control plane' }
                @{ Name = 'gate: approval'; Color = '5319e7'; Description = 'Waiting for owner approval' }
                @{ Name = 'gate: ui-test'; Color = '5319e7'; Description = 'Waiting for manual UI validation' }
                @{ Name = 'review: passed'; Color = '0e8a16'; Description = 'Automated review passed' }
                @{ Name = 'review: changes-requested'; Color = 'd73a4a'; Description = 'Review requested follow-up changes' }
            )
            Managed = @(
                'status: in-progress',
                'status: blocked',
                'status: needs-review',
                'status: needs-testing',
                'status: ready-to-merge',
                'gate: approval',
                'gate: ui-test',
                'review: passed',
                'review: changes-requested',
                'sync: paperclip'
            )
        }
        ProjectFields = @{
            Required = @(
                @{ Name = 'Queue State'; DataType = 'SINGLE_SELECT'; Options = @('issue-only', 'user-review', 'approved-awaiting-dispatch', 'dispatched', 'blocked', 'closed') }
                @{ Name = 'jules_session_status'; DataType = 'SINGLE_SELECT'; Options = @('n_a', 'queued', 'planning', 'waiting', 'running', 'failed', 'completed') }
                @{ Name = 'pr_checks_status'; DataType = 'SINGLE_SELECT'; Options = @('n_a', 'pending', 'failed', 'passed') }
                @{ Name = 'review_status'; DataType = 'SINGLE_SELECT'; Options = @('n_a', 'pending', 'changes_requested', 'passed', 'manual_ui_required') }
                @{ Name = 'human_gate'; DataType = 'SINGLE_SELECT'; Options = @('none', 'manual_ui_gate', 'approval_required', 'clarification') }
                @{ Name = 'paperclip_issue'; DataType = 'TEXT' }
            )
            Names = @{
                Status = 'Status'
                QueueState = 'Queue State'
                JulesSessionStatus = 'jules_session_status'
                PrChecksStatus = 'pr_checks_status'
                WorkBranch = 'work_branch'
                LastUpdate = 'last_update'
                LinkedPr = 'Linked PR'
                Agent = 'agent'
                SubAgent = 'sub_agent'
                PermitIssue = 'permit_issue'
                TaskType = 'task_type'
                Priority = 'priority'
                Description = 'description'
                TaskId = 'task_id'
                Area = 'area'
                ReviewStatus = 'review_status'
                HumanGate = 'human_gate'
                PaperclipIssue = 'paperclip_issue'
            }
        }
    }
    Mapping = @{
        HiddenCommentKeys = @{
            PaperclipIssueId = 'vorce-paperclip-issue-id'
            PaperclipIssueKey = 'vorce-paperclip-issue-key'
            OrchestrationStatus = 'vorce-orchestration-status'
            ReviewStatus = 'vorce-review-status'
            HumanGate = 'vorce-human-gate'
            ApprovalId = 'vorce-approval-id'
            ApprovalStatus = 'vorce-approval-status'
            Executor = 'vorce-executor'
            PlannerScore = 'vorce-planner-score'
            PlannerBucket = 'vorce-planner-bucket'
            LastPlannerUpdate = 'vorce-planner-updated'
        }
    }
}
