@{
    HumanGates = @{
        UiValidation = 'Awaiting manual UI validation from the owner.'
        ReleaseApproval = 'Awaiting release approval from the owner.'
        ArchitectureApproval = 'Awaiting architecture approval from the owner.'
        HighRiskMergeApproval = 'Awaiting high-risk merge approval from the owner.'
    }

    MandatoryApprovalConditions = @(
        'architecture_change',
        'new_dependency',
        'ci_change',
        'release_candidate',
        'persistence_change',
        'compatibility_change',
        'manual_ui_gate'
    )

    MergeRules = @{
        RequireGreenChecks = $true
        RequireHumanUiPassWhenVisible = $true
        AllowAutoMergeForLowRisk = $true
        AllowAutoMergeForHighRisk = $false
    }
}
